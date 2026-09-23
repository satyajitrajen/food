import 'dart:math';
import 'package:flutter/material.dart';

/// Single source of truth for bottom system insets (Android gesture bar /
/// 3-button nav, iOS home indicator).
///
/// Bottom-docked surfaces (sticky cart/action bars, sheets, FABs) must use
/// this instead of a bare inner `SafeArea`: on some devices (notably Samsung
/// + Android 15 edge-to-edge enforcement with an opaque nav bar) a `SafeArea`
/// inside `Scaffold.bottomSheet`/column footers yields ~zero lift and content
/// slides under the system bar. `viewPadding` is keyboard-independent, so the
/// bar never jumps when the keyboard opens.
class BottomInsets {
  /// Bottom padding for a bottom-docked bar: system inset + minimum breathing
  /// room so content never touches the system bar or screen edge.
  static EdgeInsets bar(BuildContext context, {double min = 12}) {
    return EdgeInsets.only(
      bottom: max(MediaQuery.viewPaddingOf(context).bottom, min),
    );
  }

  /// Full padding for a bottom-docked bar with horizontal/vertical spacing.
  static EdgeInsets barAll(
    BuildContext context, {
    double horizontal = 20,
    double vertical = 14,
    double minBottom = 12,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      vertical,
      horizontal,
      max(MediaQuery.viewPaddingOf(context).bottom, minBottom) + vertical,
    );
  }
}
