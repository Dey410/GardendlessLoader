import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/web/gp_next_compat_bridge.dart';

void main() {
  test('runs the Tauri surface GP-Next 1.4.3 expects', () async {
    final harness = '''
const requests = [];
global.window = {
  flutter_inappwebview: {
    callHandler: async function (handlerName, request) {
      requests.push({ handlerName, request });
      return { ok: true, value: "saved" };
    }
  }
};

$gardendlessGpNextCompatBridgeSource

(async function () {
  let callbackPayload = null;
  const callbackId = window.__TAURI_INTERNALS__.transformCallback(
    function (payload) {
      callbackPayload = payload;
    },
    true
  );
  window.__TAURI_INTERNALS__.runCallback(callbackId, { id: 7 });
  const value = await window.__TAURI_INTERNALS__.invoke(
    "plugin:fs|write_text_file",
    new Uint8Array([104, 105]),
    { headers: { path: "pack.json" } }
  );
  process.stdout.write(JSON.stringify({
    callbackPayload,
    currentWindowLabel:
      window.__TAURI_INTERNALS__.metadata.currentWindow.label,
    request: requests[0],
    value
  }));
})().catch(function (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exitCode = 1;
});
''';

    final ProcessResult result;
    try {
      result = await Process.run('node', ['-e', harness]);
    } on ProcessException {
      markTestSkipped(
          'Node.js is required for the GP-Next JavaScript contract');
      return;
    }

    expect(result.exitCode, 0, reason: result.stderr as String);
    final output = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(output, {
      'callbackPayload': {'id': 7},
      'currentWindowLabel': 'main',
      'request': {
        'handlerName': gardendlessGpNextBridgeHandlerName,
        'request': {
          'command': 'plugin:fs|write_text_file',
          'args': {
            '__gardendlessBytes': [104, 105],
          },
          'options': {
            'headers': {'path': 'pack.json'},
          },
        },
      },
      'value': 'saved',
    });
  });
}
