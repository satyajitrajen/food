enum TableStatus { available, occupied, reserved, billing, cleaning }

class RestaurantTable {
  final String id;
  final String tableNumber;
  final int seats;
  String floor; // Dining section, e.g. 'Garden', 'AC Dining', 'Bar'
  TableStatus status;
  String? activeOrderId;
  double currentOrderAmount;
  int runningMinutes;
  int guestCount;
  String? assignedWaiter;
  String? mergedWithTableId;

  RestaurantTable({
    required this.id,
    required this.tableNumber,
    required this.seats,
    required this.floor,
    this.status = TableStatus.available,
    this.activeOrderId,
    this.currentOrderAmount = 0.0,
    this.runningMinutes = 0,
    this.guestCount = 0,
    this.assignedWaiter,
    this.mergedWithTableId,
  });

  String get statusLabel {
    switch (status) {
      case TableStatus.available:
        return 'Available';
      case TableStatus.occupied:
        return 'Occupied';
      case TableStatus.reserved:
        return 'Reserved';
      case TableStatus.billing:
        return 'Billing';
      case TableStatus.cleaning:
        return 'Cleaning';
    }
  }
}
