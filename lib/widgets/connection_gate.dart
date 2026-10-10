import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/pos_provider.dart';

/// Root messenger so save errors can be shown from anywhere.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The app is online-only: while the server can't be reached this covers
/// every screen with a "No connection" panel (nothing could be saved), and
/// every change the server did not save is announced in a snackbar.
class ConnectionGate extends StatefulWidget {
  final Widget child;
  const ConnectionGate({super.key, required this.child});

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  StreamSubscription<String>? _errors;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _errors ??= context.read<PosProvider>().saveErrors.listen((message) {
      appMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    super.dispose();
  }

  Future<void> _retry(PosProvider provider) async {
    setState(() => _checking = true);
    await provider.triggerSync();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final blocked = provider.bootstrapDone && provider.isOfflineMode;
    return Stack(
      children: [
        widget.child,
        if (blocked)
          Positioned.fill(
            child: Material(
              color: AppColors.creamBg,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 56, color: AppColors.warning),
                          const SizedBox(height: 16),
                          const Text('No connection',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          const Text(
                            'Everything is saved on the server, so the app needs the internet to work. '
                            'It continues by itself as soon as the connection is back.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, height: 1.4),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _checking ? null : () => _retry(provider),
                            icon: _checking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(_checking ? 'Checking…' : 'Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
