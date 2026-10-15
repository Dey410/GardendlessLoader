import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

typedef AnnouncementHttpLoader = HttpTextLoader;

typedef AnnouncementHttpResponse = HttpTextResponse;

class AnnouncementService {
  AnnouncementService({
    String remoteUrl = remoteAnnouncementUrl,
    Duration timeout = announcementTimeout,
    int maxBytes = announcementMaxBytes,
    AnnouncementHttpLoader? loader,
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? loadHttpText;

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AnnouncementHttpLoader _loader;

  Future<Announcement?> fetchCurrentAnnouncement() async {
    try {
      final response =
          await _loader(_remoteUri, _timeout, _maxBytes).timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['schemaVersion'] != 1) {
        return null;
      }
      if (!decoded.containsKey('announcement')) {
        return null;
      }

      final rawAnnouncement = decoded['announcement'];
      if (rawAnnouncement == null) {
        return null;
      }

      return Announcement.fromJson(rawAnnouncement);
    } catch (_) {
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
