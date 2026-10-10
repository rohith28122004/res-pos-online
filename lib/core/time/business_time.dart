/// Business-day calculations. Timestamps are stored as UTC epoch millis; each
/// financial record also stores the business-date key computed *at creation*
/// with the then-current timezone and cutoff, so changing the cutoff later
/// never silently moves history between days.
library;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../errors/app_exception.dart';

bool _tzReady = false;

/// Loads the bundled IANA database (offline). Safe to call repeatedly.
void ensureTimeZonesLoaded() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// Source of "now". Tests inject a fixed clock.
abstract class Clock {
  DateTime nowUtc();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FixedClock implements Clock {
  FixedClock(DateTime start) : _now = start.toUtc();
  DateTime _now;
  @override
  DateTime nowUtc() => _now;
  void set(DateTime value) => _now = value.toUtc();
  void advance(Duration d) => _now = _now.add(d);
}

/// A calendar date used as a business-day key, formatted `YYYY-MM-DD`
/// (lexicographic order == chronological order).
class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(this.year, this.month, this.day) {
    final check = DateTime.utc(year, month, day);
    if (check.year != year || check.month != month || check.day != day) {
      throw ValidationException('Invalid date $year-$month-$day');
    }
  }

  factory BusinessDate.parse(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
    if (m == null) throw ValidationException('Invalid date "$key"');
    return BusinessDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  factory BusinessDate.fromDateTime(DateTime d) => BusinessDate(d.year, d.month, d.day);

  final int year;
  final int month;
  final int day;

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  BusinessDate addDays(int days) => BusinessDate.fromDateTime(DateTime.utc(year, month, day).add(Duration(days: days)));

  BusinessDate get firstOfMonth => BusinessDate(year, month, 1);
  BusinessDate get firstOfNextMonth => month == 12 ? BusinessDate(year + 1, 1, 1) : BusinessDate(year, month + 1, 1);

  int daysUntil(BusinessDate other) =>
      DateTime.utc(other.year, other.month, other.day).difference(DateTime.utc(year, month, day)).inDays;

  @override
  int compareTo(BusinessDate other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is BusinessDate && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// Start-inclusive / end-exclusive range of business dates.
class BusinessDateRange {
  BusinessDateRange(this.start, this.endExclusive) {
    if (endExclusive.compareTo(start) <= 0) {
      throw const ValidationException('The end date must be after the start date');
    }
  }

  /// Inclusive on both ends, as typed by a person.
  factory BusinessDateRange.inclusive(BusinessDate from, BusinessDate to) => BusinessDateRange(from, to.addDays(1));

  final BusinessDate start;
  final BusinessDate endExclusive;

  BusinessDate get lastDay => endExclusive.addDays(-1);
  int get dayCount => start.daysUntil(endExclusive);

  Iterable<BusinessDate> get days sync* {
    for (var d = start; d.compareTo(endExclusive) < 0; d = d.addDays(1)) {
      yield d;
    }
  }

  @override
  String toString() => '[$start, $endExclusive)';
}

enum RangePreset { today, yesterday, last7Days, thisMonth, custom }

/// Timezone + cutoff for one restaurant.
class BusinessCalendar {
  BusinessCalendar({required String timeZone, required this.cutoffMinutes}) : location = _location(timeZone) {
    if (cutoffMinutes < 0 || cutoffMinutes >= 24 * 60) {
      throw const ValidationException('Business day cutoff must be between 00:00 and 23:59');
    }
  }

  static tz.Location _location(String name) {
    ensureTimeZonesLoaded();
    try {
      return tz.getLocation(name);
    } on Object {
      throw ValidationException('Unknown time zone "$name"');
    }
  }

  static bool isValidTimeZone(String name) {
    ensureTimeZonesLoaded();
    try {
      tz.getLocation(name);
      return true;
    } on Object {
      return false;
    }
  }

  final tz.Location location;

  /// Minutes after local midnight when the business day rolls over.
  /// 240 means sales until 03:59 belong to the previous day.
  final int cutoffMinutes;

  tz.TZDateTime toLocal(DateTime utc) => tz.TZDateTime.from(utc.toUtc(), location);

  BusinessDate businessDateOf(DateTime utc) {
    final local = toLocal(utc);
    final minutes = local.hour * 60 + local.minute;
    final date = BusinessDate(local.year, local.month, local.day);
    return minutes < cutoffMinutes ? date.addDays(-1) : date;
  }

  /// Local wall-clock hour (0-23) used for the hourly sales chart.
  int localHourOf(DateTime utc) => toLocal(utc).hour;

  BusinessDateRange preset(RangePreset preset, DateTime nowUtc) {
    final today = businessDateOf(nowUtc);
    return switch (preset) {
      RangePreset.today => BusinessDateRange(today, today.addDays(1)),
      RangePreset.yesterday => BusinessDateRange(today.addDays(-1), today),
      RangePreset.last7Days => BusinessDateRange(today.addDays(-6), today.addDays(1)),
      RangePreset.thisMonth => BusinessDateRange(today.firstOfMonth, today.firstOfNextMonth),
      RangePreset.custom => BusinessDateRange(today, today.addDays(1)),
    };
  }

  /// UTC instant at which [date]'s business day starts.
  DateTime businessDayStartUtc(BusinessDate date) {
    final local = tz.TZDateTime(location, date.year, date.month, date.day).add(Duration(minutes: cutoffMinutes));
    return local.toUtc();
  }

  String formatLocal(DateTime utc, {bool withSeconds = false}) {
    final l = toLocal(utc);
    String two(int v) => v.toString().padLeft(2, '0');
    final time = withSeconds ? '${two(l.hour)}:${two(l.minute)}:${two(l.second)}' : '${two(l.hour)}:${two(l.minute)}';
    return '${l.year}-${two(l.month)}-${two(l.day)} $time';
  }

  /// UTC offset like "+05:30" for export columns.
  String offsetLabel(DateTime utc) {
    final offset = toLocal(utc).timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final mins = offset.inMinutes.abs();
    return '$sign${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
  }
}

String formatCutoff(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
