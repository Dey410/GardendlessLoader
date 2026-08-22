import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/cocos_audio_facade_patcher.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_audio_patch_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('patches the supported Cocos build and is idempotent', () async {
    final engine = await _writePackage(
      temp,
      engineName: '_virtual_cc-23be142f.js',
      engineSource: _supportedEngineSource,
    );
    final patcher = CocosAudioFacadePatcher();

    final first = await patcher.apply(temp);
    final patched = await engine.readAsString();

    expect(first.status, CocosAudioFacadePatchStatus.applied);
    expect(patched, contains('__gardendlessAudioFacadePatchVersion=1'));
    expect(patched, contains('__pvzgeNativeAudioAvailable'));
    expect(patched, contains('createNativeAudioHandle'));
    expect(patched, contains('role:"continuous"'));
    expect(
        patched, contains('role:__pvzgeUseDomAudio(e)?"continuous":"oneShot"'));
    expect(patched, contains('duration:this._duration'));
    expect(patched, contains('duration:t.getDuration()'));
    expect(patched, contains('this._domAudio.release'));
    expect(
      patched,
      contains('document.createElement("audio")'),
      reason: 'non-iOS fallback must remain available',
    );

    final second = await patcher.apply(temp);
    expect(second.status, CocosAudioFacadePatchStatus.alreadyApplied);
    expect(await engine.readAsString(), patched);
  });

  test('leaves a changed supported filename untouched and reports warning',
      () async {
    final engine = await _writePackage(
      temp,
      engineName: '_virtual_cc-23be142f.js',
      engineSource: 'changed engine source',
    );

    final result = await CocosAudioFacadePatcher().apply(temp);

    expect(result.status, CocosAudioFacadePatchStatus.unsupported);
    expect(result.message, contains('未应用'));
    expect(await engine.readAsString(), 'changed engine source');
  });

  test('does not guess how to patch a different engine bundle', () async {
    final engine = await _writePackage(
      temp,
      engineName: '_virtual_cc-different.js',
      engineSource: _supportedEngineSource,
    );

    final result = await CocosAudioFacadePatcher().apply(temp);

    expect(result.status, CocosAudioFacadePatchStatus.unsupported);
    expect(await engine.readAsString(), _supportedEngineSource);
  });

  test('ignores packages without a virtual Cocos engine bundle', () async {
    await _writePackage(temp);

    final result = await CocosAudioFacadePatcher().apply(temp);

    expect(result.status, CocosAudioFacadePatchStatus.notApplicable);
  });
}

Future<File> _writePackage(
  Directory root, {
  String? engineName,
  String engineSource = '',
}) async {
  final cocos = Directory(p.join(root.path, 'cocos-js'));
  final src = Directory(p.join(root.path, 'src'));
  await cocos.create(recursive: true);
  await src.create(recursive: true);
  await File(p.join(src.path, 'settings.json'))
      .writeAsString('{"CocosEngine":"3.8.4"}');
  final engine = File(p.join(cocos.path, engineName ?? 'cc.js'));
  await engine.writeAsString(engineSource);
  return engine;
}

const _supportedEngineSource = '''
function __pvzgeUseDomAudio(e){return!1}System.register
t.load=function(e){return new Promise((function(i,n){t.loadNative(e).then((function(e){i(new t(e))})).catch(n)}))}
t.loadNative=function(t){return new Promise((function(e,i){var n=document.createElement("audio");n.preload="none",n.__pvzgeLazySrc=t,e(n)}))}
t.loadOneShotAudio=function(e,i){return new Promise((function(n,r){t.loadNative(e).then((function(t){var e=new v9(t,i);n(e)})).catch(r)}))}
t.load=function(e,i){return new Promise((function(n,r){E9.support&&!__pvzgeUseDomAudio(e)?D9.load(e).then((function(e){n(new t(e))})).catch(r):(E9.support||tt(5201),y9.load(e).then((function(e){n(new t(e))})).catch(r))}))}
t.loadNative=function(t,e){returnE9.support&&!__pvzgeUseDomAudio(t)?D9.loadNative(t):(E9.support||tt(5201),y9.loadNative(t))}
t.loadOneShotAudio=function(t,e,i){return new Promise((function(n,r){E9.support&&!__pvzgeUseDomAudio(t)?D9.loadOneShotAudio(t,e).then((function(t){n(new B9(t))})).catch(r):(E9.support||tt(5201),y9.loadOneShotAudio(t,e).then((function(t){n(new B9(t))})).catch(r))}))}
return{uuid:this._uuid,audioLoadMode:this.loadMode,ext:this._native,__isNative__:!0}
P9.load(t,{audioLoadMode:e.audioLoadMode})
P9.loadOneShotAudio(t._nativeAsset.url,this._volume*e,{audioLoadMode:t.loadMode})
P9.loadOneShotAudio(this._nativeAsset.url,t)
e.destroy=function(){bB.off(AB.EVENT_PAUSE,this._onInterruptedBegin,this),bB.off(AB.EVENT_RESUME,this._onInterruptedEnd,this),this._domAudio.removeEventListener("ended",this._onEnded),this._domAudio=null}
''';
