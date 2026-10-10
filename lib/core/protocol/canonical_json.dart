import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Largest integer JavaScript represents exactly (2^53 − 1). The cloud is
/// JavaScript, so protocol integers must stay inside ±this.
const maxSafeInteger = 9007199254740991;

/// Canonical JSON (docs/PROTOCOL.md §2): object keys sorted by UTF-16 code
/// units, no whitespace, strings escaped exactly like `jsonEncode` /
/// `JSON.stringify`, integers only. Used for command body hashes and event
/// content hashes, which the host and the cloud must compute identically.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

void _write(StringBuffer out, Object? v) {
  switch (v) {
    case null:
      out.write('null');
    case final bool b:
      out.write(b ? 'true' : 'false');
    case final int i:
      if (i > maxSafeInteger || i < -maxSafeInteger) {
        throw const FormatException('Integer outside the safe range');
      }
      out.write(i);
    case double _:
      throw const FormatException('Only integers are allowed');
    case final String s:
      _checkSurrogates(s);
      out.write(jsonEncode(s));
    case final List<Object?> list:
      out.write('[');
      for (var i = 0; i < list.length; i++) {
        if (i > 0) out.write(',');
        _write(out, list[i]);
      }
      out.write(']');
    case final Map<Object?, Object?> map:
      final keys = map.keys.map((k) {
        if (k is! String) throw const FormatException('Object keys must be strings');
        _checkSurrogates(k);
        return k;
      }).toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(jsonEncode(keys[i]));
        out.write(':');
        _write(out, map[keys[i]]);
      }
      out.write('}');
    default:
      throw FormatException('Not a JSON value: ${v.runtimeType}');
  }
}

/// Lone UTF-16 surrogates have no canonical UTF-8 form; refuse them.
void _checkSurrogates(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= s.length) throw const FormatException('Invalid text (lone surrogate)');
      final d = s.codeUnitAt(i + 1);
      if (d < 0xDC00 || d > 0xDFFF) throw const FormatException('Invalid text (lone surrogate)');
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      throw const FormatException('Invalid text (lone surrogate)');
    }
  }
}

/// Lower-case hex SHA-256 of the UTF-8 bytes of [text].
String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

/// `sha256Hex(canonicalJson(value))`.
String canonicalHash(Object? value) => sha256Hex(canonicalJson(value));

/// base64url without padding.
String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> b64urlDecode(String text) {
  final pad = (4 - text.length % 4) % 4;
  return base64Url.decode(text + '=' * pad);
}
