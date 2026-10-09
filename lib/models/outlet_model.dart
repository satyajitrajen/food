class Outlet {
  final String id;
  final String name;
  final String address;
  final String terminal;
  final bool isOnline;
  final String gstin;
  final String fssai;
  final String phone;
  final String email;

  /// IANA zone the outlet's business day is counted in.
  final String timezone;

  Outlet({
    required this.id,
    required this.name,
    this.address = '',
    this.terminal = '',
    this.isOnline = true,
    this.gstin = '',
    this.fssai = '',
    this.phone = '',
    this.email = '',
    this.timezone = 'Asia/Kolkata',
  });

  /// Placeholder before any outlet is hydrated or restored.
  static final Outlet none = Outlet(id: '', name: '');

  bool get isNone => id.isEmpty;

  Outlet copyWith({
    String? name,
    String? address,
    String? terminal,
    bool? isOnline,
    String? gstin,
    String? fssai,
    String? phone,
    String? email,
    String? timezone,
  }) =>
      Outlet(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        terminal: terminal ?? this.terminal,
        isOnline: isOnline ?? this.isOnline,
        gstin: gstin ?? this.gstin,
        fssai: fssai ?? this.fssai,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        timezone: timezone ?? this.timezone,
      );
}
