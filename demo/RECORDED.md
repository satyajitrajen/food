# Recorded demo coverage — 9 October 2026

Pixel 6 API 36 emulator, portrait 1080 × 2400, isolated `tool/demo_main.dart` release build. Clips are silent. All business records shown are fictional, in memory, with API calls disabled.

| File | Actual recorded content |
|---|---|
| recordings/01-sales-demo.mp4 | Admin PIN login; opening shift with default denomination float ₹5000; table T1 with two guests; three dishes and customization dialogs; cart; KOT preview and submission; order detail; bill with ₹600 subtotal and ₹30 GST; cash collection of ₹630 from ₹1000; receipt with ₹370 change. |
| recordings/01-sales-demo-quick.mp4 | Same sales take at twice the playback speed, 30 fps. |
| recordings/02-operations-tour.mp4 | More hub; KDS New → Preparing → Ready with confirmations; past cash transaction; refund dialog inspection (cancelled); expense creation ₹100; cash drawer ₹5530 = ₹5000 + ₹630 − ₹100; reports showing one order, ₹630 gross sales, ₹100 expenses, ₹530 estimated margin and category/item breakdown. Kitchen status was demonstrated after payment in this separate UI tour. |
| recordings/02-operations-tour-quick.mp4 | Same operations tour at twice the playback speed, 30 fps. |
| recordings/receipt.png | Cash receipt still. |

The remaining scenarios in SCENARIOS.md are shooting scripts, not recorded or verified end-to-end. The local fixture has no invoice issuer: “Invoice: pending sync” is expected and remains visible. These takes demonstrate the existing UI, not server reconciliation, actual payment processing or a physical printer.

Validation: demo entry point passes targeted Flutter analysis and builds as an x64 release APK. The demo isolation widget test passes. Recording script passes PowerShell syntax parsing. PIN picker tests pass; existing KOT navigation dialog test fails because its fixture does not provide PosProvider. The actual demo app successfully displays the KOT-sent dialog and navigates to order details.

The emulator now runs the isolated demo. To return it to the normal app, run `flutter run -d emulator-5554` from the repo root. The demo uses the same Android package as the normal app; do not distribute its APK as a production build.
