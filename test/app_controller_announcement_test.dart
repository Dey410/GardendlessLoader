import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/announcement_service.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';

void main() {
  test('stores the current announcement for inline display', () async {
    final root = await Directory.systemTemp.createTemp('gl_announcement_');
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
    );

    await controller.initialize();
    await controller.refreshAnnouncement();

    expect(controller.announcement?.id, 'notice-1');
    expect(controller.announcement?.title, '公告');
    expect(controller.announcement?.message, '公告正文');
  });

  test('clears the inline announcement when remote announcement is null',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_announcement_');
    var body = '''
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
        loader: (uri, timeout, maxBytes) async => AnnouncementHttpResponse(
          statusCode: HttpStatus.ok,
          body: body,
        ),
      ),
    );

    await controller.initialize();
    await controller.refreshAnnouncement();

    expect(controller.announcement?.id, 'notice-1');

    body = '{"schemaVersion":1,"announcement":null}';
    await controller.refreshAnnouncement();

    expect(controller.announcement, isNull);
  });
}
