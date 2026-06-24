import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/game_download_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_download_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('uses a safe suggested filename before content disposition', () {
    final name = downloadFileName(
      suggestedFilename: '../save:slot?.json',
      contentDisposition: "attachment; filename*=UTF-8''fallback.json",
      mimeType: 'application/json',
    );

    expect(name, 'save_slot_.json');
  });

  test('decodes RFC 5987 content disposition filename', () {
    final name = downloadFileName(
      contentDisposition:
          "attachment; filename*=UTF-8''%E5%AD%98%E6%A1%A3.json",
      mimeType: 'application/json',
    );

    expect(name, '存档.json');
  });

  test('prepares a data URL export and writes it to a temporary file',
      () async {
    GameDownloadFile? sharedFile;
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {
        sharedFile = file;
      },
    );

    final file = await service.exportDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:application/json;base64,${base64Encode(utf8.encode('{"ok":true}'))}',
        ),
        suggestedFilename: 'save.json',
      ),
      presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );

    expect(sharedFile?.path, file.path);
    expect(file.name, 'save.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path!).readAsString(), '{"ok":true}');
  });

  test('defaults JSON exports to the game json file format', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:;base64,${base64Encode(utf8.encode('{"coins":1}'))}',
        ),
      ),
    );

    expect(file.name, 'gardendless-export.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path!).readAsString(), '{"coins":1}');
  });

  test('defaults structured JSON mime exports to json files', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:application/vnd.gardendless+json;base64,${base64Encode(utf8.encode('{"slot":3}'))}',
        ),
      ),
    );

    expect(file.name, 'gardendless-export.json');
    expect(file.mimeType, 'application/vnd.gardendless+json');
    expect(await File(file.path!).readAsString(), '{"slot":3}');
  });

  test('renames generic JSON blob exports to json files', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('blob:http://127.0.0.1:26410/export-id'),
        suggestedFilename: 'save.bin',
        mimeType: 'application/octet-stream',
      ),
      blobResolver: (_) async => GameDownloadPayload(
        bytes: utf8.encode('{"level":2}'),
        mimeType: 'application/octet-stream',
      ),
    );

    expect(file.name, 'save.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path!).readAsString(), '{"level":2}');
  });

  test('downloads allowed HTTP export content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"slot":1}');
      await request.response.close();
    });
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
      isAllowedHttpUri: (uri) => uri.port == server.port,
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('http://127.0.0.1:${server.port}/export'),
        suggestedFilename: 'slot.json',
      ),
    );

    expect(file.mimeType, 'application/json');
    expect(await File(file.path!).readAsString(), '{"slot":1}');
  });

  test('rejects non-local HTTP export content', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
      isAllowedHttpUri: (_) => false,
    );

    expect(
      service.prepareDownload(
        request: GameDownloadRequest(
          uri: Uri.parse('https://example.com/export.json'),
        ),
      ),
      throwsA(isA<GameDownloadFailure>()),
    );
  });

  test('uses the WebView blob resolver for blob exports', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileExporter: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('blob:http://127.0.0.1:26410/export-id'),
        suggestedFilename: 'blob-save.txt',
      ),
      blobResolver: (_) async => GameDownloadPayload(
        bytes: utf8.encode('blob content'),
        mimeType: 'text/plain',
      ),
    );

    expect(file.name, 'blob-save.txt');
    expect(await File(file.path!).readAsString(), 'blob content');
  });

  test('web export keeps bytes in memory instead of writing a temp file',
      () async {
    GameDownloadFile? savedFile;
    final service = GameDownloadService(
      isWeb: true,
      temporaryDirectoryProvider: () async {
        fail('web exports should not need a temporary directory');
      },
      platformNameProvider: () {
        fail('web exports should not read dart:io Platform');
      },
      saveLocationPicker: ({
        required acceptedTypeGroups,
        suggestedName,
        confirmButtonText,
      }) async {
        expect(suggestedName, 'web-save.json');
        return const file_selector.FileSaveLocation('');
      },
      fileSaver: (file, path) async {
        savedFile = file;
        expect(path, isEmpty);
      },
    );

    final file = await service.exportDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:application/json;base64,${base64Encode(utf8.encode('{"web":true}'))}',
        ),
        suggestedFilename: 'web-save.bin',
      ),
      presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );

    expect(file.path, isNull);
    expect(file.name, 'web-save.json');
    expect(utf8.decode(file.bytes), '{"web":true}');
    expect(savedFile, same(file));
  });

  test('web HTTP export uses the web-safe HTTP loader', () async {
    var loadedUri = Uri();
    GameDownloadFile? savedFile;
    final service = GameDownloadService(
      isWeb: true,
      temporaryDirectoryProvider: () async {
        fail('web HTTP exports should not need a temporary directory');
      },
      isAllowedHttpUri: (_) => true,
      webHttpDownload: (request) async {
        loadedUri = request.uri;
        return GameDownloadPayload(
          bytes: utf8.encode('{"http":true}'),
          mimeType: 'application/json',
        );
      },
      saveLocationPicker: ({
        required acceptedTypeGroups,
        suggestedName,
        confirmButtonText,
      }) async =>
          const file_selector.FileSaveLocation(''),
      fileSaver: (file, path) async {
        savedFile = file;
      },
    );

    final file = await service.exportDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('http://127.0.0.1:26410/export'),
        suggestedFilename: 'http-save.bin',
      ),
      presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );

    expect(loadedUri, Uri.parse('http://127.0.0.1:26410/export'));
    expect(file.path, isNull);
    expect(file.name, 'http-save.json');
    expect(utf8.decode(file.bytes), '{"http":true}');
    expect(savedFile, same(file));
  });

  test('web HTTP export does not forward blocked request headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final capturedUserAgent = Completer<String?>();
    addTearDown(() async => server.close(force: true));
    server.listen((request) async {
      capturedUserAgent.complete(request.headers.value('user-agent'));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"defaultWebHttp":true}');
      await request.response.close();
    });

    GameDownloadFile? savedFile;
    final service = GameDownloadService(
      isWeb: true,
      temporaryDirectoryProvider: () async {
        fail('web HTTP exports should not need a temporary directory');
      },
      isAllowedHttpUri: (uri) => uri.port == server.port,
      saveLocationPicker: ({
        required acceptedTypeGroups,
        suggestedName,
        confirmButtonText,
      }) async =>
          const file_selector.FileSaveLocation(''),
      fileSaver: (file, path) async {
        savedFile = file;
      },
    );

    final file = await service.exportDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('http://127.0.0.1:${server.port}/export'),
        suggestedFilename: 'default-web-http.bin',
        userAgent: 'GardendlessLoaderTestAgent',
      ),
      presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );

    expect(await capturedUserAgent.future, isNot('GardendlessLoaderTestAgent'));
    expect(file.path, isNull);
    expect(file.name, 'default-web-http.json');
    expect(utf8.decode(file.bytes), '{"defaultWebHttp":true}');
    expect(savedFile, same(file));
  });

  test('desktop exporter asks for a save location and writes the json file',
      () async {
    for (final platform in ['macos', 'windows', 'linux']) {
      final target = File('${temp.path}/$platform-save.json');
      String? capturedSuggestedName;
      GameDownloadFile? savedFile;
      final service = GameDownloadService(
        temporaryDirectoryProvider: () async => temp,
        platformNameProvider: () => platform,
        saveLocationPicker: ({
          required acceptedTypeGroups,
          suggestedName,
          confirmButtonText,
        }) async {
          expect(confirmButtonText, '保存');
          expect(acceptedTypeGroups.single.extensions, ['json']);
          capturedSuggestedName = suggestedName;
          return file_selector.FileSaveLocation(target.path);
        },
        fileSaver: (file, path) async {
          savedFile = file;
          await File(path).writeAsBytes(await File(file.path!).readAsBytes());
        },
      );

      final file = await service.exportDownload(
        request: GameDownloadRequest(
          uri: Uri.parse(
            'data:application/json;base64,${base64Encode(utf8.encode('{"desk":true}'))}',
          ),
          suggestedFilename: 'save.bin',
        ),
        presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );

      expect(file.name, 'save.json');
      expect(capturedSuggestedName, 'save.json');
      expect(savedFile?.path, file.path);
      expect(await target.readAsString(), '{"desk":true}');
    }
  });

  test('desktop exporter reports cancellation from the save dialog', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      platformNameProvider: () => 'linux',
      saveLocationPicker: ({
        required acceptedTypeGroups,
        suggestedName,
        confirmButtonText,
      }) async =>
          null,
      fileSaver: (file, path) async {
        fail('cancelled exports should not write a file');
      },
    );

    expect(
      service.exportDownload(
        request: GameDownloadRequest(
          uri: Uri.parse(
            'data:application/json;base64,${base64Encode(utf8.encode('{"cancel":true}'))}',
          ),
        ),
        presentationOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
      throwsA(
        isA<GameDownloadFailure>()
            .having((error) => error.message, 'message', '已取消导出'),
      ),
    );
  });

  test('mobile exporters open the native save-location channel', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final channel = const MethodChannel(
      'io.github.dey410.gardendlessloader/game_file_exporter',
    );
    final capturedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedCalls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    for (final platform in ['android', 'ios', 'ohos']) {
      final service = GameDownloadService(
        temporaryDirectoryProvider: () async => temp,
        platformNameProvider: () => platform,
      );

      final file = await service.exportDownload(
        request: GameDownloadRequest(
          uri: Uri.parse(
            'data:application/json;base64,${base64Encode(utf8.encode('{"ok":true}'))}',
          ),
          suggestedFilename: 'save.bin',
        ),
        presentationOrigin: const Rect.fromLTWH(2, 3, 4, 5),
      );

      expect(file.name, 'save.json');
    }

    expect(capturedCalls, hasLength(3));
    for (final call in capturedCalls) {
      expect(call.method, 'exportFile');
      expect(call.arguments, containsPair('name', 'save.json'));
      expect(call.arguments, containsPair('mimeType', 'application/json'));
      expect(call.arguments, containsPair('originX', 2.0));
    }
  });
}
