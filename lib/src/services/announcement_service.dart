import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

/// What the remote announcement file carries: the announcement, an optional
/// seasonal theme and links for the launcher, each valid on its own.
class AnnouncementFeed {
  const AnnouncementFeed({required this.json, this.announcement, this.theme});

  /// The file as received, saved again for a start without network.
  final Map<String, dynamic> json;
  final Announcement? announcement;
  final SeasonalTheme? theme;

  /// Read through [LauncherLinks.merge].
  Object? get urls => json['urls'];
}

class AnnouncementService {
  static final List<Uri> _remoteUris =
      remoteAnnouncementUrls.map(Uri.parse).toList(growable: false);

  /// The feed written by [save], or null without one.
  Future<AnnouncementFeed?> loadCached(File cacheFile) async {
    try {
      return _decode(await cacheFile.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  /// Tries each source in order; null when no source answers with a valid
  /// feed.
  Future<AnnouncementFeed?> fetch() async {
    for (final uri in _remoteUris) {
      final body = await _download(uri);
      final feed = body == null ? null : _decode(body);
      if (feed != null) return feed;
    }
    return null;
  }

  /// Saves [feed] with [links] as its `urls`, so the next start begins with
  /// every link fetched so far.
  Future<void> save(
    File cacheFile,
    AnnouncementFeed feed,
    LauncherLinks links,
  ) async {
    try {
      await cacheFile
          .writeAsString(jsonEncode({...feed.json, 'urls': links.toJson()}));
    } on FileSystemException {
      // The fetched feed still applies; the next start fetches again.
    }
  }

  static Future<String?> _download(Uri uri) async {
    try {
      final response = await loadHttpText(
        uri,
        announcementTimeout,
        announcementMaxBytes,
      ).timeout(announcementTimeout);
      return response.statusCode == HttpStatus.ok ? response.body : null;
    } catch (_) {
      return null;
    }
  }

  static AnnouncementFeed? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
        return null;
      }
      return AnnouncementFeed(
        json: decoded,
        announcement: _parse(decoded['announcement'], Announcement.fromJson),
        theme: _parse(decoded['theme'], SeasonalTheme.fromJson),
      );
    } catch (_) {
      return null;
    }
  }

  /// A malformed part is dropped without discarding the others.
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
