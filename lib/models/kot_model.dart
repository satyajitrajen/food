import 'order_model.dart';

enum KOTStatus { newTicket, preparing, ready, served, cancelled }

class KitchenOrderTicket {
  /// Local optimistic tickets carry a terminal-generated id until the server
  /// ack adopts its authoritative id/number (see PosProvider._upsertServerKot).
  String id;
  final String outletId;
  String kotNumber; // e.g. 'KOT #1204'
  final String orderId;
  final String? tableNumber;
  final OrderType orderType;
  final String waiterName;
  final DateTime createdAt;
  KOTStatus status;
  final List<OrderItem> items;
  final String? specialInstructions;

  /// True while this ticket is a local optimistic write awaiting the server's
  /// authoritative copy; used to reconcile the SSE/ack ticket with the
  /// optimistic one instead of rendering both.
  bool pendingServerAck;

  KitchenOrderTicket({
    required this.id,
    required this.outletId,
    required this.kotNumber,
    required this.orderId,
    this.tableNumber,
    required this.orderType,
    required this.waiterName,
    required this.createdAt,
    this.status = KOTStatus.newTicket,
    required this.items,
    this.specialInstructions,
    this.pendingServerAck = false,
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
