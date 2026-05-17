import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/announcement_service.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';

void main() {
  test('dismisses announcement by id and local date', () async {
    final root = await Directory.systemTemp.createTemp('gl_announcement_');
    var now = DateTime(2026, 5, 17, 12);
    const remoteAnnouncement = '''
{
  "schemaVersion": 1,
  "announcement": {
    "id": "notice-1",
    "title": "公告",
    "message": "公告正文"
  }
}
''';
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      announcementService: AnnouncementService(
        loader: (uri, timeout, maxBytes) async =>
            const AnnouncementHttpResponse(
          statusCode: HttpStatus.ok,
          body: remoteAnnouncement,
        ),
      ),
      now: () => now,
    );

    await controller.initialize();
    await controller.refreshAnnouncement();

    expect(controller.pendingAnnouncement?.id, 'notice-1');

    await controller.dismissAnnouncement(controller.pendingAnnouncement!);
    await controller.refreshAnnouncement();

    expect(controller.pendingAnnouncement, isNull);
    expect(controller.manifest.dismissedAnnouncementId, 'notice-1');
    expect(controller.manifest.dismissedAnnouncementLocalDate, '2026-05-17');

    now = DateTime(2026, 5, 18, 9);
    await controller.refreshAnnouncement();

    expect(controller.pendingAnnouncement?.id, 'notice-1');
  });

  test('shows a different announcement on the same day', () async {
    final root = await Directory.systemTemp.createTemp('gl_announcement_');
    var id = 'notice-1';
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      announcementService: AnnouncementService(
        loader: (uri, timeout, maxBytes) async => AnnouncementHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "schemaVersion": 1,
  "announcement": {
    "id": "$id",
    "title": "公告",
    "message": "公告正文"
  }
}
''',
        ),
      ),
      now: () => DateTime(2026, 5, 17, 12),
    );

    await controller.initialize();
    await controller.refreshAnnouncement();
    await controller.dismissAnnouncement(controller.pendingAnnouncement!);

    id = 'notice-2';
    await controller.refreshAnnouncement();

    expect(controller.pendingAnnouncement?.id, 'notice-2');
  });
}
