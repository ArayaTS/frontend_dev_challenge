import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../app_config.dart';
import '../../routes/routes.dart';
import '../shared_widget/deal_card.dart';
import '../shared_widget/impression_tracker.dart';
import '../shared_widget/shimmer_deal_card.dart';
import 'home_controller.dart';
import 'widget/flash_deals_section.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // scrollOffset changes on every scroll pixel. It must only affect the
    // tiny bits of UI that actually depend on it (app bar elevation, the
    // scroll-to-top FAB) — not the whole screen. Previously a single Obx
    // wrapped the entire Scaffold, so the whole feed (every DealCard, every
    // image) rebuilt on every scroll frame.
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(() => AppBar(
              elevation: controller.scrollOffset.value > 4 ? 2 : 0,
              shadowColor: Colors.black26,
              title: const Row(
                children: [
                  Icon(Icons.eco, color: AppConfig.primaryGreen),
                  SizedBox(width: 8),
                  Text('Rescu',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => Get.toNamed(Routes.search),
                ),
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () => Get.toNamed(Routes.map),
                ),
                IconButton(
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => Get.toNamed(Routes.orders),
                ),
                IconButton(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: () => Get.toNamed(Routes.cart),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'deeplink') _showDeepLinkDialog(context);
                    if (value == 'analytics') {
                      Get.toNamed(Routes.analyticsDebug);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'deeplink', child: Text('Simulate deep link…')),
                    PopupMenuItem(
                        value: 'analytics', child: Text('Analytics debug')),
                  ],
                ),
              ],
            )),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return ListView(
            children: const [
              ShimmerDealCard(),
              ShimmerDealCard(),
              ShimmerDealCard(),
            ],
          );
        }
        // Read once per rebuild: visibleDeals filters the full list, so
        // calling it from inside itemBuilder would re-filter on every card.
        final visibleDeals = controller.visibleDeals;
        return SmartRefresher(
          controller: controller.refreshController,
          enablePullDown: true,
          enablePullUp: true,
          onRefresh: controller.refreshDeals,
          onLoading: controller.loadMore,
          child: CustomScrollView(
            controller: controller.scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (controller.flashDeals.isNotEmpty)
                      FlashDealsSection(deals: controller.flashDeals),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          const Text('Nearby deals',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          FilterChip(
                            label: const Text('Pickup today'),
                            selected: controller.todayOnly.value,
                            onSelected: (v) => controller.todayOnly.value = v,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Lazily built/disposed as cards scroll on/off screen, instead
              // of every card (and its image) existing at once for the
              // whole session.
              SliverList.builder(
                itemCount: visibleDeals.length,
                itemBuilder: (context, index) => ImpressionTracker(
                  dealId: visibleDeals[index].id,
                  source: 'home_feed',
                  position: index,
                  child: DealCard(deal: visibleDeals[index]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      }),
      floatingActionButton: Obx(() {
        if (controller.scrollOffset.value <= 800) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton.small(
          onPressed: controller.scrollToTop,
          child: const Icon(Icons.arrow_upward),
        );
      }),
    );
  }

  void _showDeepLinkDialog(BuildContext context) {
    final textController =
        TextEditingController(text: 'rescu://open/deal?id=42&source=push');
    Get.dialog(
      AlertDialog(
        title: const Text('Simulate deep link'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            helperText: 'e.g. rescu://open/deal?id=42&source=push',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final uri = Uri.tryParse(textController.text.trim());
              Get.back();
              if (uri == null) return;
              final route =
                  uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
              Get.toNamed(route);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
