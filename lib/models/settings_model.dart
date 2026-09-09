class RestaurantSettings {
  final String restaurantName;
  final String address;
  final String phone;
  final String email;
  final String gstin;
  final String fssai;
  final double gstPercentage;
  final bool isGstInclusive;
  final double defaultServiceChargePercent;
  final double defaultPackagingCharge;
  final double defaultDeliveryCharge;

  // Printers
  final String billingPrinter;
  final String kitchenPrinter;
  final String barPrinter;
  final bool autoPrintKOT;
  final bool allowReprint;

  // Managed dining sections (e.g. Garden, AC Dining, Bar). Tables carry the
  // section name as their floor. Empty list => sections derive from tables.
  final List<String> sections;

  // UPI QR customer payments: primary = upiId (QR generated per bill),
  // upiQrImage = optional uploaded override.
  final String upiId;
  final String upiName;
  final String upiQrImage;

  RestaurantSettings({
    this.restaurantName = 'Spice Haven Resto & Bar',
    this.address = 'Plot 42, High Street, Baner, Pune - 411045',
    this.phone = '+91 98765 43210',
    this.email = 'baner@spicehaven.com',
    this.gstin = '27AAAAA0000A1Z5',
    this.fssai = '11521000000123',
    this.gstPercentage = 5.0,
    this.isGstInclusive = false,
    this.defaultServiceChargePercent = 5.0,
    this.defaultPackagingCharge = 25.0,
    this.defaultDeliveryCharge = 40.0,
    this.billingPrinter = 'EPSON TM-T88VI (Counter)',
    this.kitchenPrinter = 'TVS RP3200 (Main Kitchen)',
    this.barPrinter = 'STAR Micronics (Bar Counter)',
    this.autoPrintKOT = true,
    this.allowReprint = true,
    this.sections = const ['Ground Floor', 'First Floor', 'Outdoor'],
    this.upiId = '',
    this.upiName = '',
    this.upiQrImage = '',
  })  : assert(gstPercentage >= 0 && gstPercentage <= 100),
        assert(defaultServiceChargePercent >= 0 && defaultServiceChargePercent <= 100),
        assert(defaultPackagingCharge >= 0),
        assert(defaultDeliveryCharge >= 0);

  RestaurantSettings copyWith({
    String? restaurantName,
    String? address,
    String? phone,
    String? email,
    String? gstin,
    String? fssai,
    double? gstPercentage,
    bool? isGstInclusive,
    double? defaultServiceChargePercent,
    double? defaultPackagingCharge,
    double? defaultDeliveryCharge,
    String? billingPrinter,
    String? kitchenPrinter,
    String? barPrinter,
    bool? autoPrintKOT,
    bool? allowReprint,
    List<String>? sections,
    String? upiId,
    String? upiName,
    String? upiQrImage,
  }) {
    return RestaurantSettings(
      restaurantName: restaurantName ?? this.restaurantName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstin: gstin ?? this.gstin,
      fssai: fssai ?? this.fssai,
      gstPercentage: gstPercentage ?? this.gstPercentage,
      isGstInclusive: isGstInclusive ?? this.isGstInclusive,
      defaultServiceChargePercent:
          defaultServiceChargePercent ?? this.defaultServiceChargePercent,
      defaultPackagingCharge:
          defaultPackagingCharge ?? this.defaultPackagingCharge,
      defaultDeliveryCharge: defaultDeliveryCharge ?? this.defaultDeliveryCharge,
      billingPrinter: billingPrinter ?? this.billingPrinter,
      kitchenPrinter: kitchenPrinter ?? this.kitchenPrinter,
      barPrinter: barPrinter ?? this.barPrinter,
      autoPrintKOT: autoPrintKOT ?? this.autoPrintKOT,
      allowReprint: allowReprint ?? this.allowReprint,
      sections: sections ?? this.sections,
      upiId: upiId ?? this.upiId,
      upiName: upiName ?? this.upiName,
      upiQrImage: upiQrImage ?? this.upiQrImage,
    );
  }
}
