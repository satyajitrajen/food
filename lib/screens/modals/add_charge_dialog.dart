import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

class AddChargeDialog extends StatefulWidget {
  const AddChargeDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const AddChargeDialog(),
    );
  }

  @override
  State<AddChargeDialog> createState() => _AddChargeDialogState();
}

class _AddChargeDialogState extends State<AddChargeDialog> {
  late TextEditingController _serviceController;
  late TextEditingController _packagingController;
  late TextEditingController _deliveryController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    _serviceController = TextEditingController(
      text: provider.activeOrder?.serviceCharge.toStringAsFixed(0) ?? '0',
    );
    _packagingController = TextEditingController(
      text: provider.activeOrder?.packagingCharge.toStringAsFixed(0) ?? '0',
    );
    _deliveryController = TextEditingController(
      text: provider.activeOrder?.deliveryCharge.toStringAsFixed(0) ?? '0',
    );
  }

  @override
  void dispose() {
    _serviceController.dispose();
    _packagingController.dispose();
    _deliveryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Additional Charges', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _serviceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Service Charge (₹)',
                  prefixIcon: Icon(Icons.room_service_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _packagingController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Packaging Charge (₹)',
                  prefixIcon: Icon(Icons.takeout_dining_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deliveryController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Delivery Charge (₹)',
                  prefixIcon: Icon(Icons.delivery_dining_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                    onPressed: () {
                      final sc = double.tryParse(_serviceController.text) ?? 0.0;
                      final pk = double.tryParse(_packagingController.text) ?? 0.0;
                      final dl = double.tryParse(_deliveryController.text) ?? 0.0;

                      if (sc < 0 || pk < 0 || dl < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Charges cannot be negative'),
                            backgroundColor: AppColors.nonVegRed,
                          ),
                        );
                        return;
                      }

                      provider.addCharges(
                        serviceCharge: sc,
                        packaging: pk,
                        delivery: dl,
                      );
                      Navigator.of(context).pop();
                    },
                      child: const Text('Update Charges'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}
}
