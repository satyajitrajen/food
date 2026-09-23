import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subscription_model.dart';
import '../../providers/pos_provider.dart';
import 'pin_login_screen.dart';

/// Self-service SaaS onboarding: creates the organization + owner account +
/// 7-day Pro trial + first outlet + admin staff (POST /api/v1/auth/register),
/// binds this terminal to the new org, then shows the org code + one-time
/// admin PIN so the owner can finish PIN login.
class OrgRegistrationScreen extends StatefulWidget {
  const OrgRegistrationScreen({super.key});

  @override
  State<OrgRegistrationScreen> createState() => _OrgRegistrationScreenState();
}

class _OrgRegistrationScreenState extends State<OrgRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgC = TextEditingController();
  final _ownerC = TextEditingController();
  final _emailC = TextEditingController();
  final _passwordC = TextEditingController();
  final _outletC = TextEditingController();
  final _terminalC = TextEditingController(text: 'Counter 1');
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  RegisterOrgResult? _result;

  @override
  void dispose() {
    _orgC.dispose();
    _ownerC.dispose();
    _emailC.dispose();
    _passwordC.dispose();
    _outletC.dispose();
    _terminalC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final provider = context.read<PosProvider>();
    try {
      final result = await provider.registerOrg(
        orgName: _orgC.text,
        ownerName: _ownerC.text,
        email: _emailC.text,
        password: _passwordC.text,
        outletName: _outletC.text,
        terminal: _terminalC.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on ApiException catch (e) {
      _fail(e.code == 'email_taken' ? 'An account with this email already exists' : e.message);
    } on NetworkException {
      _fail('Cannot reach the server. Check the connection and try again.');
    } on FormatException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Something went wrong. Try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  void _continueToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _result == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _result == null ? _form() : _success(_result!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create your organization',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Start your 7-day free trial on Pro — no card needed.\n'
            'Authorize auto-pay anytime during the trial; the first charge happens on day 8.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _field(_orgC, 'Restaurant name', 'e.g. Sharma Bhojnalaya',
              validator: _required),
          const SizedBox(height: 12),
          _field(_ownerC, 'Your name', 'e.g. Priya Sharma',
              validator: _required),
          const SizedBox(height: 12),
          _field(_emailC, 'Work email', 'you@restaurant.com',
              keyboard: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              }),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordC,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Password (min 8 characters)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 8) ? 'Password must be at least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          _field(_outletC, 'First outlet name', 'e.g. Main Outlet',
              validator: _required),
          const SizedBox(height: 12),
          _field(_terminalC, 'Counter name (optional)', 'e.g. Main Counter',
              helper:
                  'Shown on bills & reports to identify this billing counter.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    color: AppColors.nonVegRed, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Start 7-day free trial',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Widget _field(TextEditingController c, String label, String hint,
      {String? Function(String?)? validator,
      TextInputType? keyboard,
      String? helper}) {
    return TextFormField(
      controller: c,
      enabled: !_busy,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  Widget _success(RegisterOrgResult result) {
    final trialText = result.trialEndsAt == null
        ? '7-day free trial is live'
        : 'Free trial until ${DateFormat('dd MMM yyyy').format(result.trialEndsAt!.toLocal())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: AppColors.vegGreen, size: 56),
        const SizedBox(height: 12),
        const Text(
          'Your trial is live',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '${result.orgName} · $trialText.\nThis device is set up — keep these safe:',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        _codeCard('Organization code (enter on this device)', result.orgCode),
        const SizedBox(height: 12),
        _codeCard('Initial POS admin PIN (shown once)', result.adminPin,
            warn: true),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryGreenLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Enable auto-pay in Settings → Subscription before the trial ends — '
            'the mandate is authorized now and the first charge happens automatically on day 8.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            onPressed: _continueToLogin,
            child: const Text('Continue to PIN login',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _codeCard(String label, String value, {bool warn = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.5)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () => _copy(label.split(' (').first, value),
              ),
            ],
          ),
          if (warn)
            const Text('Save it now — it will not be shown again.',
                style: TextStyle(
                    color: AppColors.nonVegRed, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
