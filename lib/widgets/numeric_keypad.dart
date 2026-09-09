import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class NumericKeypad extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onDelete;
  final VoidCallback? onClear;
  final VoidCallback? onSubmit;
  final String submitLabel;

  const NumericKeypad({
    super.key,
    required this.onKeyPressed,
    required this.onDelete,
    this.onClear,
    this.onSubmit,
    this.submitLabel = 'Enter',
  });

  Widget _buildKey(String label, {VoidCallback? customAction, Color? bgColor, Color? textColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: bgColor ?? Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.borderLight, width: 1.2),
          ),
          child: InkWell(
            onTap: customAction ?? () => onKeyPressed(label),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 58,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textColor ?? AppColors.textDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildKey('1'),
            _buildKey('2'),
            _buildKey('3'),
          ],
        ),
        Row(
          children: [
            _buildKey('4'),
            _buildKey('5'),
            _buildKey('6'),
          ],
        ),
        Row(
          children: [
            _buildKey('7'),
            _buildKey('8'),
            _buildKey('9'),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Material(
                  color: AppColors.creamSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.borderLight, width: 1.2),
                  ),
                  child: InkWell(
                    onTap: onClear ?? onDelete,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      child: const Text(
                        'C',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildKey('0'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Material(
                  color: AppColors.creamSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.borderLight, width: 1.2),
                  ),
                  child: InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.backspace_outlined,
                        color: AppColors.textDark,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (onSubmit != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                submitLabel,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
