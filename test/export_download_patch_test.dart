import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/ui/game_page.dart';
import 'package:gardendless_loader/src/web/export_download_patch.dart';

void main() {
  test('export download patch captures game save downloads', () {
    expect(gardendlessExportDownloadHandlerName, 'gardendlessDownloadExport');
    expect(gardendlessExportDownloadPatchSource,
        contains('__gardendlessLoaderExportDownloadPatchInstalled'));
    expect(gardendlessExportDownloadPatchSource,
        contains('window.flutter_inappwebview.callHandler'));
    expect(gardendlessExportDownloadPatchSource,
        contains('flutterInAppWebViewPlatformReady'));
    expect(gardendlessExportDownloadPatchSource, contains('pendingPayloads'));

    expect(gardendlessExportDownloadPatchSource, contains('createObjectURL'));
    expect(gardendlessExportDownloadPatchSource, contains('revokeObjectURL'));
    expect(
        gardendlessExportDownloadPatchSource, contains('objectUrlBlobs.set'));
    expect(gardendlessExportDownloadPatchSource, contains('readAsDataURL'));

    expect(gardendlessExportDownloadPatchSource, contains('anchor.download'));
    expect(gardendlessExportDownloadPatchSource,
        contains('anchor.hasAttribute("download")'));
    expect(gardendlessExportDownloadPatchSource,
        contains('lowerHref.startsWith("blob:")'));
    expect(gardendlessExportDownloadPatchSource,
        contains('lowerHref.startsWith("data:")'));
    expect(gardendlessExportDownloadPatchSource,
        contains('HTMLAnchorElement.prototype.click'));
    expect(gardendlessExportDownloadPatchSource,
        contains('document.addEventListener'));
  });

  test('patched export payload prefers inline data and preserves metadata', () {
    final parsed = gameDownloadRequestFromPatchedPayload({
      'url': 'blob:http://127.0.0.1:26410/export-id',
      'dataUrl': 'data:application/json;base64,e30=',
      'suggestedFilename': 'slot.bin',
      'mimeType': 'application/json',
    });

    expect(parsed.failure, isNull);
    expect(parsed.request?.uri.toString(), 'data:application/json;base64,e30=');
    expect(parsed.request?.suggestedFilename, 'slot.bin');
    expect(parsed.request?.mimeType, 'application/json');
  });

  test('patched export payload reports script errors directly', () {
    final parsed = gameDownloadRequestFromPatchedPayload({
      'url': 'blob:http://127.0.0.1:26410/export-id',
      'error': 'Cannot read exported Blob',
      'source': 'anchor-error',
    });

    expect(parsed.request, isNull);
    expect(parsed.failure, 'Cannot read exported Blob');
  });

  test('patched export payload validates message shape and url', () {
    final malformed = gameDownloadRequestFromPatchedPayload('bad');
    final missingUrl = gameDownloadRequestFromPatchedPayload({'source': 'x'});
    final invalidUrl = gameDownloadRequestFromPatchedPayload({
      'url': 'http://[::1',
    });
    final plainUrl = gameDownloadRequestFromPatchedPayload({
      'url': 'http://127.0.0.1:26410/export.json',
    });

    expect(malformed.failure, '导出消息格式无效');
    expect(missingUrl.failure, '导出消息缺少文件地址');
    expect(invalidUrl.failure, '导出地址无效');
    expect(plainUrl.failure, isNull);
    expect(
        plainUrl.request?.uri.toString(), 'http://127.0.0.1:26410/export.json');
  });

  test('patched export payload ignores non-string optional fields', () {
    final parsed = gameDownloadRequestFromPatchedPayload({
      'url': 'http://127.0.0.1:26410/export.json',
      'dataUrl': '',
      'suggestedFilename': 1,
      'mimeType': false,
      'error': '   ',
    });

    expect(parsed.failure, isNull);
    expect(
        parsed.request?.uri.toString(), 'http://127.0.0.1:26410/export.json');
    expect(parsed.request?.suggestedFilename, isNull);
    expect(parsed.request?.mimeType, isNull);
  });
}
