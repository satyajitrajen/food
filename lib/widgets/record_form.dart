import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import 'confirm_dialog.dart';

/// One text field of a [showRecordForm] dialog.
class FormFieldSpec {
  final String key;
  final String label;
  final String initial;
  final TextInputType keyboard;
  final bool required;
  final bool numeric;
  final IconData? icon;

  const FormFieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.keyboard = TextInputType.text,
    this.required = false,
    this.numeric = false,
    this.icon,
  });
}

/// Edit dialog that saves on the server: [onSave] gets the trimmed values
/// and returns null once saved, or the reason it was not saved (shown in the
/// dialog, which stays open). Returns true when saved.
Future<bool> showRecordForm(
  BuildContext context, {
  required String title,
  required List<FormFieldSpec> fields,
  required Future<String?> Function(Map<String, String> values) onSave,
  String saveLabel = 'Save',
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecordFormDialog(title: title, fields: fields, onSave: onSave, saveLabel: saveLabel),
  );
  return saved == true;
}

class _RecordFormDialog extends StatefulWidget {
  final String title;
  final List<FormFieldSpec> fields;
  final Future<String?> Function(Map<String, String> values) onSave;
  final String saveLabel;

  const _RecordFormDialog({
    required this.title,
    required this.fields,
    required this.onSave,
    required this.saveLabel,
  });

  @override
  State<_RecordFormDialog> createState() => _RecordFormDialogState();
}

class _RecordFormDialogState extends State<_RecordFormDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final values = {for (final e in _controllers.entries) e.key: e.value.text.trim()};
    for (final f in widget.fields) {
      if (f.required && values[f.key]!.isEmpty) {
        setState(() => _error = '${f.label} is required');
        return;
      }
      if (f.numeric && values[f.key]!.isNotEmpty && double.tryParse(values[f.key]!) == null) {
        setState(() => _error = '${f.label} must be a number');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(values);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in widget.fields) ...[
                TextField(
                  controller: _controllers[f.key],
                  keyboardType: f.numeric ? const TextInputType.numberWithOptions(decimal: true) : f.keyboard,
                  inputFormatters: f.numeric
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                      : null,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: f.required ? f.label : '${f.label} (optional)',
                    prefixIcon: f.icon == null ? null : Icon(f.icon),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : widget.saveLabel),
        ),
      ],
    );
  }
}

/// Confirms, runs a server delete and reports the outcome in a snackbar.
/// Returns true when deleted.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  required Future<String?> Function() action,
  required String doneText,
}) async {
  final ok = await showConfirmDialog(context, title: title, message: message, confirmLabel: 'Delete');
  if (!ok || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final error = await action();
  messenger.showSnackBar(SnackBar(
    content: Text(error == null ? doneText : 'Not deleted: $error'),
    backgroundColor: error == null ? AppColors.success : AppColors.danger,
  ));
  return error == null;
}
