import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/web/gp_next_compat_bridge.dart';

void main() {
  test('installs the Tauri surface GP-Next 1.4.2 expects', () {
    expect(
      gardendlessGpNextCompatBridgeSource,
      contains('__TAURI_INTERNALS__'),
    );
    expect(gardendlessGpNextCompatBridgeSource, contains('invoke: invoke'));
    expect(
      gardendlessGpNextCompatBridgeSource,
      contains('transformCallback: transformCallback'),
    );
    expect(
      gardendlessGpNextCompatBridgeSource,
      contains('__TAURI_EVENT_PLUGIN_INTERNALS__'),
    );
    expect(gardendlessGpNextCompatBridgeSource, contains('__gardendlessBytes'));
    expect(gardendlessGpNextCompatBridgeSource, contains('label: "main"'));
  });
}
