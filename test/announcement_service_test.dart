import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/announcement_service.dart';

void main() {
  test('parses a valid remote announcement', () async {
    final service = AnnouncementService(
      loader: (uri, timeout, maxBytes) async {
        expect(uri.toString(), remoteAnnouncementUrl);
        expect(timeout, announcementTimeout);
        expect(maxBytes, announcementMaxBytes);
        return const AnnouncementHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "schemaVersion": 1,
  "announcement": {
    "id": "remote-1",
    "title": "远程公告",
    "message": "公告正文",
    "links": [
      {
        "label": "GitHub",
        "url": "https://github.com/Dey410/GardendlessLoader"
      }
    ]
  }
}
''',
        );
      },
    );

    final announcement = await service.fetchCurrentAnnouncement();

    expect(announcement?.id, 'remote-1');
    expect(announcement?.title, '远程公告');
    expect(announcement?.links.single.label, 'GitHub');
  });

  test('remote null announcement disables fallback announcement', () async {
    final service = AnnouncementService(
      loader: (uri, timeout, maxBytes) async => const AnnouncementHttpResponse(
        statusCode: HttpStatus.ok,
        body: '{"schemaVersion":1,"announcement":null}',
      ),
    );

    final announcement = await service.fetchCurrentAnnouncement();

    expect(announcement, isNull);
  });

  test('uses local fallback when remote request fails', () async {
    final service = AnnouncementService(
      loader: (uri, timeout, maxBytes) async =>
          throw const SocketException('offline'),
    );

    final announcement = await service.fetchCurrentAnnouncement();

    expect(announcement?.id, localFallbackAnnouncement.id);
    expect(announcement?.links.map((link) => link.url), [
      appGithubUrl,
      bilibiliHomeUrl,
    ]);
  });

  test('uses local fallback when remote request times out', () async {
    final service = AnnouncementService(
      timeout: const Duration(milliseconds: 1),
      loader: (uri, timeout, maxBytes) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const AnnouncementHttpResponse(
          statusCode: HttpStatus.ok,
          body: '{"schemaVersion":1,"announcement":null}',
        );
      },
    );

    final announcement = await service.fetchCurrentAnnouncement();

    expect(announcement?.id, localFallbackAnnouncement.id);
  });

  test('rejects non-https announcement links', () {
    expect(
      () => Announcement.fromJson({
        'id': 'bad-link',
        'title': '公告',
        'message': '正文',
        'links': [
          {'label': 'bad', 'url': 'http://example.com'},
        ],
      }),
      throwsFormatException,
    );
  });
}
