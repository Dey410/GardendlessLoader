import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../models.dart';

typedef AnnouncementHttpLoader = Future<AnnouncementHttpResponse> Function(
  Uri uri,
  Duration timeout,
  int maxBytes,
);

class AnnouncementHttpResponse {
  const AnnouncementHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class AnnouncementService {
  AnnouncementService({
    String remoteUrl = remoteAnnouncementUrl,
    Duration timeout = announcementTimeout,
    int maxBytes = announcementMaxBytes,
    AnnouncementHttpLoader? loader,
    Announcement fallbackAnnouncement = localFallbackAnnouncement,
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _fallbackAnnouncement = fallbackAnnouncement;

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AnnouncementHttpLoader _loader;
  final Announcement _fallbackAnnouncement;

  Future<Announcement?> fetchCurrentAnnouncement() async {
    try {
      final response =
          await _loader(_remoteUri, _timeout, _maxBytes).timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        return _fallbackAnnouncement;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _fallbackAnnouncement;
      }
      if (decoded['schemaVersion'] != 1) {
        return _fallbackAnnouncement;
      }
      if (!decoded.containsKey('announcement')) {
        return _fallbackAnnouncement;
      }

      final rawAnnouncement = decoded['announcement'];
      if (rawAnnouncement == null) {
        return null;
      }

      return Announcement.fromJson(rawAnnouncement);
    } catch (_) {
      return _fallbackAnnouncement;
    }
  }

  static Future<AnnouncementHttpResponse> _loadWithHttpClient(
    Uri uri,
    Duration timeout,
    int maxBytes,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final contentLength = response.contentLength;
      if (contentLength > maxBytes) {
        throw const FormatException('announcement response is too large');
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) {
          final nextLength = buffer.length + chunk.length;
          if (nextLength > maxBytes) {
            throw const FormatException('announcement response is too large');
          }
          buffer.addAll(chunk);
          return buffer;
        },
      ).timeout(timeout);

      return AnnouncementHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } finally {
      client.close(force: true);
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
