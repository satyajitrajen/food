import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/outlet_model.dart';

class SelectOutletScreen extends StatelessWidget {
  const SelectOutletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Select Outlet & Terminal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Connected Restaurant Outlets',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select which outlet and billing counter terminal this device is operating on.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              for (Outlet outlet in provider.outlets) ...[
                Builder(
                  builder: (context) {
                    final isSelected = provider.currentOutlet.id == outlet.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryOrange : AppColors.borderLight,
                          width: isSelected ? 2 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          provider.selectOutlet(outlet);
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Switched to ${outlet.name} (${outlet.terminal})'),
                              backgroundColor: AppColors.vegGreen,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primaryOrangeLight : AppColors.creamSubtle,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.store_mall_directory_outlined,
                                  color: isSelected ? AppColors.primaryOrange : AppColors.textMuted,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          outlet.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: outlet.isOnline ? AppColors.vegGreenBg : AppColors.nonVegRedBg,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            outlet.isOnline ? 'Online' : 'Offline',
                                            style: TextStyle(
                                              color: outlet.isOnline ? AppColors.vegGreen : AppColors.nonVegRed,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Terminal ${outlet.terminal} · GST: ${outlet.gstin}',
                                      style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      outlet.address,
                                      style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: AppColors.primaryOrange, size: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
}
