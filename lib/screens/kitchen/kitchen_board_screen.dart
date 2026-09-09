import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/kot_model.dart';
import '../../widgets/custom_badge.dart';
import '../auth/pin_login_screen.dart';

class KitchenBoardScreen extends StatefulWidget {
  /// When true the app bar shows a lock button — used on a dedicated kitchen
  /// terminal that boots straight into the KDS (role 'kitchen').
  final bool showLock;

  const KitchenBoardScreen({super.key, this.showLock = false});

  @override
  State<KitchenBoardScreen> createState() => _KitchenBoardScreenState();
}

class _KitchenBoardScreenState extends State<KitchenBoardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final kots = provider.kots;

    final newKots = kots.where((k) => k.status == KOTStatus.newTicket).toList();
    final preparingKots = kots.where((k) => k.status == KOTStatus.preparing).toList();
    final readyKots = kots.where((k) => k.status == KOTStatus.ready).toList();
    final servedKots = kots.where((k) => k.status == KOTStatus.served).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Kitchen Display (KDS)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.showLock)
            IconButton(
              tooltip: 'Lock Kitchen Terminal',
              icon: const Icon(Icons.lock_outline, size: 20),
              onPressed: () {
                provider.logout();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                  (route) => false,
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryOrange,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primaryOrange,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(text: 'New (${newKots.length})'),
            Tab(text: 'Preparing (${preparingKots.length})'),
            Tab(text: 'Ready (${readyKots.length})'),
            Tab(text: 'Served (${servedKots.length})'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildKOTList(newKots, provider),
            _buildKOTList(preparingKots, provider),
            _buildKOTList(readyKots, provider),
            _buildKOTList(servedKots, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildKOTList(List<KitchenOrderTicket> tickets, PosProvider provider) {
    if (tickets.isEmpty) {
      return const Center(
        child: Text('No orders in this station', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final kot = tickets[index];
        final timeStr = DateFormat('hh:mm a').format(kot.createdAt);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          kot.kotNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrangeLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kot.tableNumber != null ? 'Table ${kot.tableNumber}' : kot.orderType.name.toUpperCase(),
                            style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    StatusBadge.forKOT(kot.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Time: $timeStr · Waiter: ${kot.waiterName} · ${kot.totalQuantity} items',
                  style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                ),
                const Divider(height: 20, color: AppColors.borderLight),
                // Items
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: kot.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.quantity} × ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                          VegMark(isVeg: item.menuItem.isVeg, size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                if (item.selectedModifiers.isNotEmpty)
                                  Text(
                                    '+ ${item.selectedModifiers.map((m) => m.name).join(", ")}',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                if (item.itemNote != null)
                                  Text(
                                    'Special: "${item.itemNote}"',
                                    style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (kot.specialInstructions != null && kot.specialInstructions!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.saffronAmberBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Ticket Note: ${kot.specialInstructions}',
                      style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (kot.status == KOTStatus.newTicket)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.saffronAmber),
                        onPressed: () => provider.updateKOTStatus(kot.id, KOTStatus.preparing),
                        icon: const Icon(Icons.soup_kitchen, size: 16),
                        label: const Text('Start Preparing'),
                      )
                    else if (kot.status == KOTStatus.preparing)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                        onPressed: () => provider.updateKOTStatus(kot.id, KOTStatus.ready),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Mark Ready'),
                      )
                    else if (kot.status == KOTStatus.ready)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.textDark),
                        onPressed: () => provider.updateKOTStatus(kot.id, KOTStatus.served),
                        icon: const Icon(Icons.room_service_outlined, size: 16),
                        label: const Text('Mark Served'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
