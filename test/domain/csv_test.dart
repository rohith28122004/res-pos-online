import 'dart:convert';

import 'package:cafedesk/core/csv/csv.dart';
import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formula-looking text is neutralised; numbers stay numbers', () {
    final out = encodeCsv([
      ['=SUM(A1:A9)', '+1', '-cmd', '@x', 'plain', CsvNumber('-94.50'), 7],
    ]);
    expect(out, "'=SUM(A1:A9),'+1,'-cmd,'@x,plain,-94.50,7\r\n");
  });

  test('quotes, commas and newlines are escaped', () {
    expect(
      encodeCsv([
        ['a,b', 'say "hi"', 'two\nlines'],
      ]),
      '"a,b","say ""hi""","two\nlines"\r\n',
    );
  });

  test('bytes carry a UTF-8 BOM and keep ₹ and Tamil', () {
    final bytes = encodeCsvBytes([
      ['₹', 'காபி'],
    ]);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.sublist(3)), '₹,காபி\r\n');
  });

  test('parser handles quotes, CRLF, BOM, blank lines', () {
    final rows = parseCsv('﻿a,b,c\r\n"x, y","He said ""hi""",\r\n\r\nlast,"multi\nline",z\n');
    expect(rows, [
      ['a', 'b', 'c'],
      ['x, y', 'He said "hi"', ''],
      ['last', 'multi\nline', 'z'],
    ]);
  });

  test('round trip and unclosed quote', () {
    final data = [
      ['Coffee', 'Small', '=evil'],
    ];
    expect(parseCsv(encodeCsv(data)).single, ['Coffee', 'Small', "'=evil"]);
    expect(parseCsv(encodeCsv(data)).single.map(unguardCsvText).toList(), ['Coffee', 'Small', '=evil']);
    expect(unguardCsvText("'=SUM(1)"), '=SUM(1)');
    expect(() => parseCsv('"oops'), throwsA(isA<ValidationException>()));
  });
}
