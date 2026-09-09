import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import 'pin_login_screen.dart';

/// First-run terminal setup for SaaS terminals: binds this device to an
/// organization via its join code (from the owner's welcome e-mail / console),
/// then loads that org's outlets + staff for PIN login.
class OrgSetupScreen extends StatefulWidget {
  /// When true this replaces the currently bound tenant (change-org flow).
  final bool rebind;

  const OrgSetupScreen({super.key, this.rebind = false});

  @override
  State<OrgSetupScreen> createState() => _OrgSetupScreenState();
}

class _OrgSetupScreenState extends State<OrgSetupScreen> {
  final TextEditingController _codeC = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeC.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final provider = context.read<PosProvider>();
    try {
      if (widget.rebind) {
        await provider.rebindOrg(_codeC.text);
      } else {
        await provider.bootstrapOrg(_codeC.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      );
    } on ApiException catch (e) {
      _fail(e.message);
    } on NetworkException catch (e) {
      _fail('Cannot reach the server: ${e.message}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.restaurant_menu_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome to FoodPOS',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your organization code to set up this terminal.\n'
                    'It is shown in your welcome e-mail and the owner console.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeC,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'Organization code',
                      hintText: 'e.g. ABCD-1234',
                      prefixIcon: const Icon(Icons.business_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _continue(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                      onPressed: _busy ? null : _continue,
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Continue',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
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
