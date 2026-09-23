import 'package:flutter/widgets.dart';

/// A [StatefulBuilder] that also owns the dialog's [TextEditingController]s and
/// disposes them when the dialog route is finally unmounted.
///
/// Disposing a controller right after `showDialog` returns is unsafe: that
/// future completes when the route is popped, but the dialog — and any field
/// that still holds focus — stays mounted through the exit transition. The
/// live TextField then touches a disposed controller and throws
/// "A TextEditingController was used after being disposed", which cascades
/// into framework asserts (`_dependents.isEmpty`) while the tree tears down.
class DialogControllerScope extends StatefulWidget {
  final List<TextEditingController> controllers;
  final StatefulWidgetBuilder builder;

  const DialogControllerScope({
    super.key,
    required this.controllers,
    required this.builder,
  });

  @override
  State<DialogControllerScope> createState() => _DialogControllerScopeState();
}

class _DialogControllerScopeState extends State<DialogControllerScope> {
  @override
  void dispose() {
    // Descendants are unmounted before this State disposes, so the TextFields
    // referencing these controllers are already gone.
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
