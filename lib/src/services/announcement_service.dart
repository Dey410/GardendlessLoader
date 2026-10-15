import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

class AnnouncementService {
  static final Uri _remoteUri = Uri.parse(remoteAnnouncementUrl);

  Future<Announcement?> fetchCurrentAnnouncement() async {
    try {
      final response = await loadHttpText(
        _remoteUri,
        announcementTimeout,
        announcementMaxBytes,
      ).timeout(announcementTimeout);
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
