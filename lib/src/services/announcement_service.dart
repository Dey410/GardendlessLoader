import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import 'app_logger.dart';

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
    AppLogger? logger,
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _fallbackAnnouncement = fallbackAnnouncement,
        _logger = logger ?? AppLogger.instance;

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AnnouncementHttpLoader _loader;
  final Announcement _fallbackAnnouncement;
  final AppLogger _logger;

  Future<Announcement?> fetchCurrentAnnouncement() async {
    final operation = _logger.beginOperation(
      'network.announcement',
      'Announcement request',
      data: <String, Object?>{
        'uri': _remoteUri,
        'timeoutMs': _timeout.inMilliseconds,
        'maxBytes': _maxBytes,
      },
    );
    try {
      final response =
          await _loader(_remoteUri, _timeout, _maxBytes).timeout(_timeout);
      operation.step(
        'Announcement response received',
        data: <String, Object?>{
          'statusCode': response.statusCode,
          'bodyBytes': utf8.encode(response.body).length,
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        operation.complete(
          message: 'Announcement fallback selected',
          data: <String, Object?>{
            'fallback': true,
            'reason': 'http_status',
            'statusCode': response.statusCode,
          },
        );
        _logger.warning(
          'network.announcement',
          'Announcement endpoint returned a non-success status',
          code: 'announcement_http_status',
          data: <String, Object?>{
            'statusCode': response.statusCode,
            'fallbackAnnouncementId': _fallbackAnnouncement.id,
          },
        );
        return _fallbackAnnouncement;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _fallback(
          operation,
          code: 'announcement_payload_not_object',
          reason: 'payload_not_object',
        );
      }
      if (decoded['schemaVersion'] != 1) {
        return _fallback(
          operation,
          code: 'announcement_schema_unsupported',
          reason: 'unsupported_schema',
          data: <String, Object?>{
            'schemaVersion': decoded['schemaVersion'],
          },
        );
      }
      if (!decoded.containsKey('announcement')) {
        return _fallback(
          operation,
          code: 'announcement_field_missing',
          reason: 'announcement_field_missing',
        );
      }

      final rawAnnouncement = decoded['announcement'];
      if (rawAnnouncement == null) {
        operation.complete(
          data: const <String, Object?>{
            'announcementAvailable': false,
            'fallback': false,
          },
        );
        return null;
      }

      final announcement = Announcement.fromJson(rawAnnouncement);
      operation.complete(
        data: <String, Object?>{
          'announcementAvailable': true,
          'announcementId': announcement.id,
          'linkCount': announcement.links.length,
          'fallback': false,
        },
      );
      return announcement;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        message: 'Announcement request failed; fallback selected',
        code: 'announcement_request_failed',
        level: AppLogLevel.warning,
        data: <String, Object?>{
          'fallbackAnnouncementId': _fallbackAnnouncement.id,
        },
      );
      return _fallbackAnnouncement;
    }
  }

  Announcement _fallback(
    AppLogOperation operation, {
    required String code,
    required String reason,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _logger.warning(
      'network.announcement',
      'Announcement payload was rejected',
      code: code,
      operationId: operation.operationId,
      data: <String, Object?>{
        ...data,
        'reason': reason,
        'fallbackAnnouncementId': _fallbackAnnouncement.id,
      },
    );
    operation.complete(
      message: 'Announcement fallback selected',
      data: <String, Object?>{
        ...data,
        'fallback': true,
        'reason': reason,
      },
    );
    return _fallbackAnnouncement;
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
      '欢迎使用 GardendlessLoader。如果你喜欢这个项目，请给它一个⭐️！也可以前往GitHub仓库查看源代码，或者在小朱的B站主页上关注小朱，获取更多更新和教程！',
  links: [
    AnnouncementLink(label: 'GitHub', url: appGithubUrl),
    AnnouncementLink(label: 'B站主页', url: bilibiliHomeUrl),
  ],
);
