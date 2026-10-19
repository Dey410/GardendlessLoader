import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

/// What the remote announcement file carries: the announcement and an
/// optional seasonal theme, each valid on its own.
class AnnouncementFeed {
  const AnnouncementFeed({this.announcement, this.theme});

  final Announcement? announcement;
  final SeasonalTheme? theme;
}

class AnnouncementService {
  static final Uri _remoteUri = Uri.parse(remoteAnnouncementUrl);

  Future<AnnouncementFeed> fetch() async {
    try {
      final response = await loadHttpText(
        _remoteUri,
        announcementTimeout,
        announcementMaxBytes,
      ).timeout(announcementTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return const AnnouncementFeed();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
        return const AnnouncementFeed();
      }
      return AnnouncementFeed(
        announcement: _parse(decoded['announcement'], Announcement.fromJson),
        theme: _parse(decoded['theme'], SeasonalTheme.fromJson),
      );
    } catch (_) {
      return const AnnouncementFeed();
    }
  }

  /// A malformed part is dropped without discarding the other.
  static T? _parse<T>(Object? value, T Function(Object?) fromJson) {
    if (value == null) return null;
    try {
      return fromJson(value);
    } on FormatException {
      return null;
    }
  }
}

const localFallbackAnnouncement = Announcement(
  id: 'local-default',
  title: '公告',
  message:
      '欢迎使用 GardendlessLoader。如果你喜欢这个项目，请给它一个⭐️！也可以前往GitHub仓库查看源代码，或者在小朱的B站主页上关注小朱，获取更多更新和教程！。',
  links: [
    AnnouncementLink(label: 'GitHub', url: appGithubUrl),
    AnnouncementLink(label: 'B站主页', url: bilibiliHomeUrl),
  ],
);
