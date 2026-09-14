import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  // Guards against out-of-order responses: shorter queries are simulated as
  // slower (broader) than longer ones, so a stale request can resolve after
  // a newer one. Only the response matching the latest request is applied.
  int _requestId = 0;

  void onQueryChanged(String query) {
    _search(query);
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    if (query.trim().isEmpty) {
      results.clear();
      hasSearched.value = false;
      return;
    }
    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(query);
      if (requestId != _requestId) return;
      results.assignAll(found);
    } catch (e) {
      if (requestId != _requestId) return;
      LogService.error('search failed', e);
    }
    if (requestId != _requestId) return;
    isLoading.value = false;
  }
}
