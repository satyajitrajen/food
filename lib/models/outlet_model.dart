class Outlet {
  final String id;
  final String name;
  final String address;
  final String terminal;
  final bool isOnline;
  final String gstin;
  final String fssai;
  final String phone;

  Outlet({
    required this.id,
    required this.name,
    required this.address,
    required this.terminal,
    this.isOnline = true,
    required this.gstin,
    required this.fssai,
    required this.phone,
  });
}
