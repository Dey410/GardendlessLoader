import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// Text the game gives in both of its languages.
typedef GameText = ({String zh, String en});

/// The launcher's colours and badge for one of the game's events.
typedef EventLook = ({int accent, int accentDark, String badge});

/// The looks of the events the game ships; an event missing here still shows
/// on the Play page, without changing the launcher's colours.
const _eventLooks = <String, EventLook>{
  'Halloween': (accent: 0xffea580c, accentDark: 0xfffb923c, badge: '🎃'),
  'Lunar': (accent: 0xffdc2626, accentDark: 0xfff87171, badge: '🧧'),
  'Lunar_Eve': (accent: 0xffdc2626, accentDark: 0xfff87171, badge: '🧨'),
  'Feastivus_Before': (accent: 0xff15803d, accentDark: 0xff4ade80, badge: '🎄'),
  'Feastivus_Eve': (accent: 0xff15803d, accentDark: 0xff4ade80, badge: '🎄'),
  'Feastivus': (accent: 0xff15803d, accentDark: 0xff4ade80, badge: '🎄'),
  'Feastivus_After': (accent: 0xff15803d, accentDark: 0xff4ade80, badge: '🎄'),
  'Valentines': (accent: 0xffdb2777, accentDark: 0xfff472b6, badge: '💘'),
  'Birthday': (accent: 0xff7c3aed, accentDark: 0xffa78bfa, badge: '🎂'),
  'Easter': (accent: 0xff65a30d, accentDark: 0xffa3e635, badge: '🥚'),
  'AprilFools': (accent: 0xffca8a04, accentDark: 0xfffacc15, badge: '🃏'),
  'Stpatrick': (accent: 0xff16a34a, accentDark: 0xff4ade80, badge: '☘️'),
  'Summer': (accent: 0xff0284c7, accentDark: 0xff38bdf8, badge: '🌙'),
  'Harvest': (accent: 0xffb45309, accentDark: 0xfff59e0b, badge: '🌾'),
  'Foodfight': (accent: 0xffe11d48, accentDark: 0xfffb7185, badge: '🍕'),
  'Sportzball': (accent: 0xff2563eb, accentDark: 0xff60a5fa, badge: '🏈'),
};

/// One dated event of the game's own calendar.
class GameEvent {
  const GameEvent({
    required this.name,
    required this.dates,
    required this.title,
    required this.description,
    this.look,
  });

  final String name;

  /// Month and day, in the lunar calendar for a `M.D.lunar` date.
  final List<({int month, int day, bool lunar})> dates;
  final GameText title;
  final GameText description;
  final EventLook? look;

  /// The launcher theme for [day], or null for an event without a look.
  SeasonalTheme? themeOn(DateTime day) {
    final look = this.look;
    if (look == null) return null;
    final date = DateTime(day.year, day.month, day.day);
    return SeasonalTheme(
      from: date,
      to: date,
      accent: look.accent,
      accentDark: look.accentDark,
      badge: look.badge,
    );
  }
}

/// The game's event calendar (`json/Features/EventList`), the one its daily
/// piñata level follows. The events come in the game's order, and the first
/// whose dates hold today is the one the game shows.
class GameEventCalendar {
  const GameEventCalendar(this.events);

  final List<GameEvent> events;

  /// Reads the calendar from the package at [resourceRoot]. The resources
  /// bundle's config.json names the pack that holds the asset; in the pack,
  /// the asset's name comes just before its data.
  static GameEventCalendar read(String resourceRoot) {
    final bundle = p.join(resourceRoot, 'assets', 'resources');
    final config = jsonDecode(
      File(p.join(bundle, 'config.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    final index = (config['paths'] as Map<String, dynamic>)
        .entries
        .where(
            (entry) => (entry.value as List).first == 'json/Features/EventList')
        .map((entry) => int.parse(entry.key))
        .single;
    final pack = (config['packs'] as Map<String, dynamic>)
        .entries
        .where((entry) => (entry.value as List).contains(index))
        .map((entry) => entry.key)
        .single;
    final events = _eventList(jsonDecode(File(p.join(
      bundle,
      config['importBase'] as String,
      pack.substring(0, 2),
      '$pack.json',
    )).readAsStringSync()));
    if (events == null) {
      throw const FormatException('EventList is missing from its pack');
    }
    return GameEventCalendar([
      for (final MapEntry(key: name, value: event) in events.entries)
        if (_event(name, event as Map<String, dynamic>) case final parsed?)
          parsed,
    ]);
  }

  /// The event the game shows on [now]'s day: the first with a date that
  /// matches the solar month and day, or the lunar ones for a lunar date.
  GameEvent? eventOn(DateTime now) {
    final lunar = _lunarMonthDay(now);
    for (final event in events) {
      for (final date in event.dates) {
        final matches = date.lunar
            ? lunar != null &&
                lunar.month == date.month &&
                lunar.day == date.day
            : now.month == date.month && now.day == date.day;
        if (matches) return event;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _eventList(Object? value) {
    if (value is! List) return null;
    for (var i = 0; i + 1 < value.length; i++) {
      final data = value[i + 1];
      if (value[i] == 'EventList' &&
          data is Map<String, dynamic> &&
          data['EVENTS'] is Map<String, dynamic>) {
        return data['EVENTS'] as Map<String, dynamic>;
      }
    }
    for (final item in value) {
      final events = _eventList(item);
      if (events != null) return events;
    }
    return null;
  }

  // The game reads a date as `+month`, `+day` and an optional `lunar`; one
  // that does not parse never matches. The Default event has no dates.
  static GameEvent? _event(String name, Map<String, dynamic> event) {
    final title = _text(event['DefaultTitle']);
    final description = _text(event['DefaultDescription']);
    final dates = [
      for (final date in event['Dates'] as List? ?? const [])
        if (date is String) _date(date),
    ].nonNulls.toList();
    if (title == null || description == null || dates.isEmpty) return null;
    return GameEvent(
      name: name,
      dates: dates,
      title: title,
      description: description,
      look: _eventLooks[name],
    );
  }

  static ({int month, int day, bool lunar})? _date(String value) {
    final parts = value.split('.');
    final month = int.tryParse(parts.first);
    final day = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (month == null || day == null) return null;
    return (
      month: month,
      day: day,
      lunar: parts.length > 2 && parts[2] == 'lunar'
    );
  }

  static GameText? _text(Object? value) {
    if (value is! Map || value['zh'] is! String || value['en'] is! String) {
      return null;
    }
    return (zh: value['zh'] as String, en: value['en'] as String);
  }
}

/// Lunar New Year (lunar 1.1) as a solar date, with the days of the twelfth
/// lunar month before it and of the first month. Generated with the
/// lunar-javascript library the game bundles, so the launcher's lunar days
/// are the game's; no twelfth month in these years is a leap month.
const _lunarNewYears = <(int, int, int, int, int)>[
  (2026, 2, 17, 29, 30),
  (2027, 2, 6, 29, 30),
  (2028, 1, 26, 29, 30),
  (2029, 2, 13, 29, 30),
  (2030, 2, 3, 30, 29),
  (2031, 1, 23, 29, 29),
  (2032, 2, 11, 29, 30),
  (2033, 1, 31, 30, 29),
  (2034, 2, 19, 30, 29),
  (2035, 2, 8, 30, 30),
  (2036, 1, 28, 30, 30),
  (2037, 2, 15, 30, 30),
  (2038, 2, 4, 30, 30),
  (2039, 1, 24, 29, 30),
  (2040, 2, 12, 29, 30),
  (2041, 2, 1, 29, 29),
  (2042, 1, 22, 30, 29),
  (2043, 2, 10, 30, 29),
  (2044, 1, 30, 30, 30),
  (2045, 2, 17, 30, 30),
  (2046, 2, 6, 30, 30),
  (2047, 1, 26, 30, 30),
  (2048, 2, 14, 30, 29),
  (2049, 2, 2, 29, 30),
  (2050, 1, 23, 29, 29),
];

/// The lunar month and day of [now] in the twelfth or first lunar month
/// around a Lunar New Year in the table, the only lunar months the event
/// calendar uses; null on any other day.
({int month, int day})? _lunarMonthDay(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  for (final (year, month, day, twelfth, first) in _lunarNewYears) {
    final offset = today.difference(DateTime.utc(year, month, day)).inDays;
    if (offset >= -twelfth && offset < 0) {
      return (month: 12, day: twelfth + offset + 1);
    }
    if (offset >= 0 && offset < first) return (month: 1, day: offset + 1);
  }
  return null;
}
