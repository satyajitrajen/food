import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';

class SelectOrderTypeDialog extends StatelessWidget {
  final Function(OrderType type) onSelectType;

  const SelectOrderTypeDialog({super.key, required this.onSelectType});

  static void show(BuildContext context, {required Function(OrderType type) onSelectType}) {
    showDialog(
      context: context,
      builder: (ctx) => SelectOrderTypeDialog(onSelectType: onSelectType),
    );
  }

  Widget _buildTypeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: 560,
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
                  const Text(
                    'Select Order Type',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how this order will be served and billed.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildTypeCard(
                context: context,
                title: 'Dine-In',
                subtitle: 'Choose floor table, assign seats & waiter service.',
                icon: Icons.table_restaurant,
                color: AppColors.primaryOrange,
                bgColor: AppColors.primaryOrangeLight,
                onTap: () => onSelectType(OrderType.dineIn),
              ),
              const SizedBox(height: 12),
              _buildTypeCard(
                context: context,
                title: 'Takeaway / Parcel',
                subtitle: 'Direct counter parcel order with packaging slip.',
                icon: Icons.takeout_dining,
                color: AppColors.vegGreen,
                bgColor: AppColors.vegGreenBg,
                onTap: () => onSelectType(OrderType.takeaway),
              ),
              const SizedBox(height: 12),
              _buildTypeCard(
                context: context,
                title: 'Delivery Order',
                subtitle: 'Direct home delivery with customer address & tracking.',
                icon: Icons.delivery_dining,
                color: AppColors.infoBlue,
                bgColor: AppColors.infoBlueBg,
                onTap: () => onSelectType(OrderType.delivery),
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
