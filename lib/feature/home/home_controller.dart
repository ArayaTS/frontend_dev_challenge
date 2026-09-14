import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class HomeController extends GetxController {
  final DealRepo dealRepo;

  HomeController({required this.dealRepo});

  final deals = <DealModel>[].obs;
  final flashDeals = <DealModel>[].obs;
  final isLoading = true.obs;
  final todayOnly = false.obs;
  final scrollOffset = 0.0.obs;

  final scrollController = ScrollController();
  final refreshController = RefreshController();

  int _page = 1;
  int _totalPages = 1;
  bool _isFetchingMore = false;

  // Bumped by every refreshDeals() call so a loadMore() request in flight at
  // the time of a refresh can tell its result is stale once it resolves,
  // instead of appending pre-refresh pages onto the freshly reset list.
  int _loadGeneration = 0;

  bool get hasMore => _page < _totalPages;

  List<DealModel> get visibleDeals => todayOnly.value
      ? deals.where((d) => d.pickupWindow.isToday).toList()
      : deals.toList();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _initialLoad();
  }

  void _onScroll() {
    scrollOffset.value = scrollController.offset;
  }

  Future<void> _initialLoad() async {
    isLoading.value = true;
    try {
      await Future.wait([refreshDeals(), _loadFlashDeals()]);
    } catch (e) {
      LogService.error('initial load failed', e);
    }
    isLoading.value = false;
  }

  Future<void> _loadFlashDeals() async {
    flashDeals.assignAll(await dealRepo.fetchFlashDeals());
  }

  Future<void> refreshDeals() async {
    final generation = ++_loadGeneration;
    final res = await dealRepo.fetchDeals(page: 1);
    if (generation != _loadGeneration) return;
    _page = 1;
    _totalPages = res.totalPages;
    deals.assignAll(res.items);
    refreshController.refreshCompleted();
  }

  Future<void> loadMore() async {
    if (_isFetchingMore) return;
    if (!hasMore) {
      refreshController.loadNoData();
      return;
    }
    _isFetchingMore = true;
    final generation = _loadGeneration;
    final requestedPage = _page + 1;
    try {
      final res = await dealRepo.fetchDeals(page: requestedPage);
      // A refresh started (and possibly finished) while this page was in
      // flight: it reset the list to page 1, so appending this now-stale
      // page would duplicate cards or overshoot the catalog size.
      if (generation == _loadGeneration) {
        _page = requestedPage;
        _totalPages = res.totalPages;
        deals.addAll(res.items);
      }
    } catch (e) {
      LogService.error('loadMore failed', e);
    } finally {
      _isFetchingMore = false;
      refreshController.loadComplete();
    }
  }

  void scrollToTop() {
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  void onClose() {
    scrollController.dispose();
    refreshController.dispose();
    super.onClose();
  }
}
