import 'order_model.dart';

enum KOTStatus { newTicket, preparing, ready, served, cancelled }

class KitchenOrderTicket {
  final String id;
  final String kotNumber; // e.g. 'KOT #1204'
  final String orderId;
  final String? tableNumber;
  final OrderType orderType;
  final String waiterName;
  final DateTime createdAt;
  KOTStatus status;
  final List<OrderItem> items;
  final String? specialInstructions;

  KitchenOrderTicket({
    required this.id,
    required this.kotNumber,
    required this.orderId,
    this.tableNumber,
    required this.orderType,
    required this.waiterName,
    required this.createdAt,
    this.status = KOTStatus.newTicket,
    required this.items,
    this.specialInstructions,
  });

  String get statusLabel {
    switch (status) {
      case KOTStatus.newTicket:
        return 'New';
      case KOTStatus.preparing:
        return 'Preparing';
      case KOTStatus.ready:
        return 'Ready';
      case KOTStatus.served:
        return 'Served';
      case KOTStatus.cancelled:
        return 'Cancelled';
    }
  }

  int get totalQuantity =>
      items.where((i) => !i.isCancelled).fold(0, (sum, i) => sum + i.quantity);
}
