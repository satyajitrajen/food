import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/numeric_keypad.dart';

class ManagerPinDialog extends StatefulWidget {
  final String actionTitle;
  final String description;

  const ManagerPinDialog({
    super.key,
    this.actionTitle = 'Manager Authorization',
    this.description = 'Enter Manager/Admin PIN to authorize this sensitive action.',
  });

  /// Returns the verified PIN (for server-side manager gates) or null when
  /// the authorization was cancelled/failed.
  static Future<String?> show(BuildContext context, {String? title, String? description}) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManagerPinDialog(
        actionTitle: title ?? 'Manager Authorization',
        description: description ?? 'Enter Manager/Admin PIN to authorize this sensitive action.',
      ),
    );
    return result;
  }

  @override
  State<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<ManagerPinDialog> {
  String _pin = '';
  String? _errorMessage;
  bool _verifying = false;

  Future<void> _verifyPin() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    final provider = context.read<PosProvider>();
    final staff = await provider.verifyManagerPin(_pin);
    if (!mounted) return;
    if (staff != null) {
      Navigator.of(context).pop(_pin);
    } else {
      setState(() {
        _verifying = false;
        _errorMessage = 'Invalid Manager PIN. Try again.';
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SizedBox(
          width: 440,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrangeLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.lock_outline, color: AppColors.primaryOrange, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.actionTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_verifying)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isFilled ? AppColors.primaryOrange : AppColors.creamSubtle,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isFilled ? AppColors.primaryOrange : AppColors.borderMedium,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.nonVegRed, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 20),
              NumericKeypad(
                onKeyPressed: (digit) {
                  if (_pin.length < 4) {
                    setState(() {
                      _pin += digit;
                      _errorMessage = null;
                    });
                    if (_pin.length == 4) {
                      _verifyPin();
                    }
                  }
                },
                onDelete: () {
                  if (_pin.isNotEmpty) {
                    setState(() {
                      _pin = _pin.substring(0, _pin.length - 1);
                      _errorMessage = null;
                    });
                  }
                },
                onClear: () {
                  setState(() {
                    _pin = '';
                    _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Demo Manager PIN: 9999 or Admin PIN: 0000',
                style: TextStyle(color: AppColors.textLight, fontSize: 11),
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
