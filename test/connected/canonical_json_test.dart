import 'dart:convert';
import 'dart:io';

import 'package:cafedesk/core/protocol/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keys are sorted by UTF-16 code units, no whitespace', () {
    expect(canonicalJson({'b': 1, 'a': 2, 'B': 3, 'é': 4, 'aa': 5}), '{"B":3,"a":2,"aa":5,"b":1,"é":4}');
    expect(
      canonicalJson({
        'x': [
          3,
          {'z': null, 'y': true},
        ],
        'w': <String, Object?>{},
      }),
      '{"w":{},"x":[3,{"y":true,"z":null}]}',
    );
  });

  test('strings are escaped like jsonEncode / JSON.stringify; non-ASCII is kept', () {
    expect(
      canonicalJson('a"b\\c\n\t\u0001₹é😀'),
      r'"a\"b\\c\n\t\u0001'
      '₹é😀"',
    );
  });

  test('floats, unsafe integers, lone surrogates and non-string keys are refused', () {
    expect(() => canonicalJson(1.5), throwsFormatException);
    expect(() => canonicalJson({'a': 1.0}), throwsFormatException);
    expect(() => canonicalJson(9007199254740992), throwsFormatException);
    expect(() => canonicalJson('\uD800'), throwsFormatException);
    expect(() => canonicalJson({1: 'x'}), throwsFormatException);
    expect(canonicalJson(-9007199254740991), '-9007199254740991');
  });

  test('hashes are lower-case hex SHA-256 of the UTF-8 canonical text', () {
    expect(canonicalHash(<String, Object?>{}), sha256Hex('{}'));
    expect(sha256Hex('{}'), '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a');
  });

  final vectors = File('protocol/vectors/canonical_hash.json');
  test(
    'shared vectors match the cloud implementation',
    () {
      final cases = jsonDecode(vectors.readAsStringSync()) as List<Object?>;
      expect(cases.length, greaterThanOrEqualTo(12));
      for (final c in cases.cast<Map<String, Object?>>()) {
        expect(canonicalJson(c['input']), c['canonical'], reason: c['name']! as String);
        expect(canonicalHash(c['input']), c['sha256'], reason: c['name']! as String);
      }
    },
    skip: vectors.existsSync() ? null : 'protocol/vectors/canonical_hash.json not written yet',
  );
}
