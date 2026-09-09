import 'dart:convert';
import 'dart:typed_data';

/// Minimal ESC/POS byte builder (thermal receipt + KOT formatting).
class EscPosBuilder {
  final BytesBuilder _b = BytesBuilder();

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  EscPosBuilder() {
    _b.add([_esc, 0x40]); // initialize
  }

  EscPosBuilder align(int mode) {
    _b.add([_esc, 0x61, mode]); // 0 left, 1 center, 2 right
    return this;
  }

  EscPosBuilder bold(bool on) {
    _b.add([_esc, 0x45, on ? 1 : 0]);
    return this;
  }

  EscPosBuilder doubleSize(bool on) {
    _b.add([_gs, 0x21, on ? 0x11 : 0x00]);
    return this;
  }

  /// Text must be latin1-encodable (thermal fonts are legacy codepages).
  EscPosBuilder text(String line) {
    _b.add(latin1.encode(_sanitize(line)));
    _b.add([0x0A]);
    return this;
  }

  EscPosBuilder divider([String char = '-']) {
    return text(char * 32);
  }

  EscPosBuilder feed(int lines) {
    _b.add(List.filled(lines, 0x0A));
    return this;
  }

  EscPosBuilder cut() {
    _b.add([_gs, 0x56, 0x42, 0x00]);
    return this;
  }

  static String _sanitize(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (r >= 32 && r <= 126) {
        sb.writeCharCode(r);
      } else if (r == 0x20B9) {
        sb.write('Rs.');
      } else if (r == 0x2022) {
        sb.write('*');
      } else {
        sb.write('?');
      }
    }
    return sb.toString();
  }

  List<int> build() => _b.takeBytes();
}
