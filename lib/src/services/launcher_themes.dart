import 'game_events.dart';
import 'garden_journal.dart';

/// What unlocks a launcher theme. A theme stays unlocked for good once
/// earned, even if what earned it later changes.
sealed class ThemeUnlock {
  const ThemeUnlock();
}

/// Open from the start.
class FromStart extends ThemeUnlock {
  const FromStart();
}

/// Opening the launcher on a day the game shows one of [events].
class DuringFestival extends ThemeUnlock {
  const DuringFestival(this.events);

  /// Event names from the game's `json/Features/EventList`.
  final Set<String> events;
}

/// Reaching [goal] of [measure] in the garden journal.
class JournalGoal extends ThemeUnlock {
  const JournalGoal(this.measure, this.goal);

  final JournalMeasure measure;
  final int goal;
}

enum JournalMeasure {
  /// Play time over every session, in milliseconds.
  totalPlay,

  /// The longest single session, in milliseconds.
  longestPlay,

  /// Distinct game versions among the imports.
  gameVersions;

  int of(GardenJournal journal) => switch (this) {
        totalPlay => journal.totalPlayMs,
        longestPlay => journal.longestPlayMs,
        gameVersions => journal.imports
            .map((record) => record.gameVersion)
            .nonNulls
            .toSet()
            .length,
      };
}

const _hour = 60 * 60 * 1000;

/// One look of the launcher: an accent colour for the light and the dark
/// theme, which also tints the surfaces, and a badge on the app icon.
class LauncherTheme {
  const LauncherTheme(
    this.id, {
    required this.name,
    this.accent,
    this.accentDark,
    this.badge,
    required this.unlock,
  });

  final String id;
  final GameText name;

  /// Opaque ARGB colours; null keeps the garden's own green, untinted.
  final int? accent;
  final int? accentDark;
  final String? badge;
  final ThemeUnlock unlock;

  static const garden = LauncherTheme(
    'garden',
    name: (zh: '花园', en: 'Garden'),
    unlock: FromStart(),
  );

  /// Every theme, in the order the picker shows them: the garden, the
  /// festivals through the year, then the journal goals.
  static const all = <LauncherTheme>[
    garden,
    LauncherTheme(
      'lunar',
      name: (zh: '春节', en: 'Lunar New Year'),
      accent: 0xffdc2626,
      accentDark: 0xfff87171,
      badge: '🧧',
      unlock: DuringFestival({'Lunar', 'Lunar_Eve'}),
    ),
    LauncherTheme(
      'valentines',
      name: (zh: '情尸节', en: "Valentine's"),
      accent: 0xffdb2777,
      accentDark: 0xfff472b6,
      badge: '💘',
      unlock: DuringFestival({'Valentines'}),
    ),
    LauncherTheme(
      'stPatrick',
      name: (zh: '圣帕特里克节', en: "St. Patrick's"),
      accent: 0xff059669,
      accentDark: 0xff34d399,
      badge: '☘️',
      unlock: DuringFestival({'Stpatrick'}),
    ),
    LauncherTheme(
      'easter',
      name: (zh: '复活节', en: 'Easter'),
      accent: 0xff65a30d,
      accentDark: 0xffa3e635,
      badge: '🥚',
      unlock: DuringFestival({'Easter'}),
    ),
    LauncherTheme(
      'aprilFools',
      name: (zh: '愚人节', en: "April Fools'"),
      accent: 0xffc026d3,
      accentDark: 0xffe879f9,
      badge: '🃏',
      unlock: DuringFestival({'AprilFools'}),
    ),
    LauncherTheme(
      'birthday',
      name: (zh: 'PvZ 生日', en: "PvZ's Birthday"),
      accent: 0xff7c3aed,
      accentDark: 0xffa78bfa,
      badge: '🎂',
      unlock: DuringFestival({'Birthday'}),
    ),
    LauncherTheme(
      'summer',
      name: (zh: '仲夏夜', en: 'Summer Nights'),
      accent: 0xff4f46e5,
      accentDark: 0xff818cf8,
      badge: '🌙',
      unlock: DuringFestival({'Summer'}),
    ),
    LauncherTheme(
      'sportzball',
      name: (zh: '前院滚球', en: 'Sportzball'),
      accent: 0xff2563eb,
      accentDark: 0xff60a5fa,
      badge: '🏈',
      unlock: DuringFestival({'Sportzball'}),
    ),
    LauncherTheme(
      'harvest',
      name: (zh: '丰收节', en: 'Harvest'),
      accent: 0xffb45309,
      accentDark: 0xfff59e0b,
      badge: '🌾',
      unlock: DuringFestival({'Harvest'}),
    ),
    LauncherTheme(
      'halloween',
      name: (zh: '万圣节', en: 'Halloween'),
      accent: 0xffea580c,
      accentDark: 0xfffb923c,
      badge: '🎃',
      unlock: DuringFestival({'Halloween'}),
    ),
    LauncherTheme(
      'foodfight',
      name: (zh: '食物大战', en: 'Food Fight'),
      accent: 0xffe11d48,
      accentDark: 0xfffb7185,
      badge: '🍕',
      unlock: DuringFestival({'Foodfight'}),
    ),
    LauncherTheme(
      'feastivus',
      name: (zh: '圣诞', en: 'Feastivus'),
      accent: 0xff0f766e,
      accentDark: 0xff2dd4bf,
      badge: '🎄',
      unlock: DuringFestival({
        'Feastivus_Before',
        'Feastivus_Eve',
        'Feastivus',
        'Feastivus_After',
      }),
    ),
    LauncherTheme(
      'sunflower',
      name: (zh: '向日葵', en: 'Sunflower'),
      accent: 0xffca8a04,
      accentDark: 0xfffacc15,
      badge: '🌻',
      unlock: JournalGoal(JournalMeasure.totalPlay, 10 * _hour),
    ),
    LauncherTheme(
      'snowPea',
      name: (zh: '寒冰射手', en: 'Snow Pea'),
      accent: 0xff0891b2,
      accentDark: 0xff22d3ee,
      badge: '❄️',
      unlock: JournalGoal(JournalMeasure.totalPlay, 50 * _hour),
    ),
    LauncherTheme(
      'crazyDave',
      name: (zh: '疯狂戴夫', en: 'Crazy Dave'),
      accent: 0xff475569,
      accentDark: 0xff94a3b8,
      badge: '🍳',
      unlock: JournalGoal(JournalMeasure.totalPlay, 100 * _hour),
    ),
    LauncherTheme(
      'coffeeBean',
      name: (zh: '咖啡豆', en: 'Coffee Bean'),
      accent: 0xff8b5a2b,
      accentDark: 0xffc99a6b,
      badge: '☕',
      unlock: JournalGoal(JournalMeasure.longestPlay, 2 * _hour),
    ),
    LauncherTheme(
      'lightningReed',
      name: (zh: '闪电芦苇', en: 'Lightning Reed'),
      accent: 0xff0284c7,
      accentDark: 0xff38bdf8,
      badge: '⚡',
      unlock: JournalGoal(JournalMeasure.gameVersions, 5),
    ),
  ];

  static LauncherTheme? byId(String? id) =>
      all.where((theme) => theme.id == id).firstOrNull;

  /// The festival theme of the game's [event], if it has one.
  static LauncherTheme? forEvent(GameEvent? event) => all
      .where((theme) => switch (theme.unlock) {
            DuringFestival(:final events) => events.contains(event?.name),
            _ => false,
          })
      .firstOrNull;

  /// The themes [journal] has earned, with today's [event], but not yet
  /// unlocked.
  static List<LauncherTheme> newlyEarned(
    GardenJournal journal,
    GameEvent? event,
  ) {
    final festival = forEvent(event);
    return [
      for (final theme in all)
        if (!theme.unlockedIn(journal) &&
            switch (theme.unlock) {
              FromStart() => false,
              DuringFestival() => theme == festival,
              JournalGoal(:final measure, :final goal) =>
                measure.of(journal) >= goal,
            })
          theme,
    ];
  }

  bool unlockedIn(GardenJournal journal) =>
      unlock is FromStart || journal.unlockedThemes.contains(id);
}
