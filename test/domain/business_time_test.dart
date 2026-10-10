import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kolkata = BusinessCalendar(timeZone: 'Asia/Kolkata', cutoffMinutes: 240);

  test('before the cutoff belongs to the previous business day', () {
    // 2026-10-06 02:30 IST == 2026-10-05 21:00 UTC
    expect(kolkata.businessDateOf(DateTime.utc(2026, 10, 5, 21)).key, '2026-10-05');
    // 2026-10-06 04:00 IST == 2026-10-05 22:30 UTC → new day exactly at cutoff
    expect(kolkata.businessDateOf(DateTime.utc(2026, 10, 5, 22, 30)).key, '2026-10-06');
    expect(kolkata.businessDateOf(DateTime.utc(2026, 10, 5, 22, 29)).key, '2026-10-05');
  });

  test('UTC midnight vs local midnight', () {
    final midnightCutoff = BusinessCalendar(timeZone: 'Asia/Kolkata', cutoffMinutes: 0);
    // 2026-10-05 19:00 UTC = 2026-10-06 00:30 IST
    expect(midnightCutoff.businessDateOf(DateTime.utc(2026, 10, 5, 19)).key, '2026-10-06');
    expect(midnightCutoff.localHourOf(DateTime.utc(2026, 10, 5, 19)), 0);
  });

  test('DST zone still maps correctly', () {
    final london = BusinessCalendar(timeZone: 'Europe/London', cutoffMinutes: 0);
    // BST (UTC+1): 2026-07-01 23:30 UTC = 2026-07-02 00:30 local
    expect(london.businessDateOf(DateTime.utc(2026, 7, 1, 23, 30)).key, '2026-07-02');
    // GMT: 2026-12-01 23:30 UTC = 2026-12-01 23:30 local
    expect(london.businessDateOf(DateTime.utc(2026, 12, 1, 23, 30)).key, '2026-12-01');
  });

  test('presets are start-inclusive, end-exclusive', () {
    final now = DateTime.utc(2026, 10, 6, 6); // 11:30 IST on 10-06
    final today = kolkata.preset(RangePreset.today, now);
    expect([today.start.key, today.endExclusive.key], ['2026-10-06', '2026-10-07']);
    final yesterday = kolkata.preset(RangePreset.yesterday, now);
    expect([yesterday.start.key, yesterday.endExclusive.key], ['2026-10-05', '2026-10-06']);
    final week = kolkata.preset(RangePreset.last7Days, now);
    expect([week.start.key, week.endExclusive.key, week.dayCount], ['2026-09-30', '2026-10-07', 7]);
    final month = kolkata.preset(RangePreset.thisMonth, now);
    expect([month.start.key, month.endExclusive.key], ['2026-10-01', '2026-11-01']);
    final dec = kolkata.preset(RangePreset.thisMonth, DateTime.utc(2026, 12, 15));
    expect(dec.endExclusive.key, '2027-01-01');
  });

  test('business day start instant', () {
    expect(kolkata.businessDayStartUtc(BusinessDate(2026, 10, 6)), DateTime.utc(2026, 10, 5, 22, 30));
  });

  test('invalid inputs', () {
    expect(() => BusinessDate.parse('2026-02-30'), throwsA(isA<ValidationException>()));
    expect(() => BusinessCalendar(timeZone: 'Mars/Base', cutoffMinutes: 0), throwsA(isA<ValidationException>()));
    expect(() => BusinessCalendar(timeZone: 'Asia/Kolkata', cutoffMinutes: 1440), throwsA(isA<ValidationException>()));
    expect(
      () => BusinessDateRange(BusinessDate(2026, 1, 2), BusinessDate(2026, 1, 2)),
      throwsA(isA<ValidationException>()),
    );
  });

  test('offset label', () {
    expect(kolkata.offsetLabel(DateTime.utc(2026, 1, 1)), '+05:30');
  });
}
