class Customer {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? gstin;
  final String? notes;
  int visits;
  double lifetimeSpend;
  double outstandingCredit;
  DateTime? lastVisit;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.gstin,
    this.notes,
    this.visits = 1,
    this.lifetimeSpend = 0.0,
    this.outstandingCredit = 0.0,
    this.lastVisit,
  });
}
