/// Minimal RFC 4180 CSV writer/reader.
///
/// The writer neutralises spreadsheet formula injection: any *text* cell that
/// starts with `=`, `+`, `-`, `@`, tab or carriage return is prefixed with a
/// single quote. Numeric cells ([CsvNumber]) are validated decimals and are
/// written as-is so negative amounts stay numbers.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../errors/app_exception.dart';

sealed class CsvCell {
  const CsvCell();
}

class CsvText extends CsvCell {
  const CsvText(this.value);
  final String value;
}

class CsvNumber extends CsvCell {
  CsvNumber(this.value) {
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'not a plain decimal');
    }
  }
  final String value;
}

CsvCell csvCell(Object? v) => switch (v) {
  null => const CsvText(''),
  final CsvCell c => c,
  final int i => CsvNumber('$i'),
  final bool b => CsvText(b ? 'yes' : 'no'),
  _ => CsvText('$v'),
};

const _formulaStarts = {'=', '+', '-', '@', '\t', '\r'};

String escapeCsvText(String value) {
  var v = value;
  if (v.isNotEmpty && _formulaStarts.contains(v[0])) v = "'$v";
  final needsQuotes = v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
  if (needsQuotes) v = '"${v.replaceAll('"', '""')}"';
  return v;
}

String encodeCsv(List<List<Object?>> rows) {
  final out = StringBuffer();
  for (final row in rows) {
    out.write(
      row
          .map((v) {
            final cell = csvCell(v);
            return switch (cell) {
              CsvText(:final value) => escapeCsvText(value),
              CsvNumber(:final value) => value,
            };
          })
          .join(','),
    );
    out.write('\r\n');
  }
  return out.toString();
}

/// UTF-8 with BOM so spreadsheet apps detect the encoding (₹, Tamil names...).
Uint8List encodeCsvBytes(List<List<Object?>> rows) {
  final body = utf8.encode(encodeCsv(rows));
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body]);
}

/// Parses CSV text into rows of strings. Handles quotes, escaped quotes,
/// CRLF/LF, a UTF-8 BOM and a trailing newline. Blank lines are skipped.
List<List<String>> parseCsv(String input) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldStarted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(c);
      i++;
      continue;
    }
    if (c == '"' && !fieldStarted && field.isEmpty) {
      inQuotes = true;
      fieldStarted = true;
      i++;
    } else if (c == ',') {
      endField();
      i++;
    } else if (c == '\r') {
      endRow();
      i += (i + 1 < text.length && text[i + 1] == '\n') ? 2 : 1;
    } else if (c == '\n') {
      endRow();
      i++;
    } else {
      field.write(c);
      fieldStarted = true;
      i++;
    }
  }
  if (inQuotes) throw const ValidationException('CSV has an unclosed quote');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Reverses the formula-guard quote added by [escapeCsvText] on import.
String unguardCsvText(String v) =>
    (v.length >= 2 && v.startsWith("'") && _formulaStarts.contains(v[1])) ? v.substring(1) : v;
