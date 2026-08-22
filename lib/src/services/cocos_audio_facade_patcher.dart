import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum CocosAudioFacadePatchStatus {
  notApplicable,
  applied,
  alreadyApplied,
  unsupported,
}

class CocosAudioFacadePatchResult {
  const CocosAudioFacadePatchResult(this.status, this.message);

  final CocosAudioFacadePatchStatus status;
  final String message;
}

abstract interface class CocosAudioFacadePatchApplying {
  Future<CocosAudioFacadePatchResult> apply(Directory root);
}

/// Applies the package-side half of the iOS native audio facade contract.
///
/// This patcher is intentionally version-locked. A changed Cocos bundle is
/// left untouched so a future game update cannot be silently corrupted.
class CocosAudioFacadePatcher implements CocosAudioFacadePatchApplying {
  static const _engineVersion = '3.8.4';
  static const _engineFileName = '_virtual_cc-23be142f.js';
  static const _marker = 'var __gardendlessAudioFacadePatchVersion=1;';

  @override
  Future<CocosAudioFacadePatchResult> apply(Directory root) async {
    final cocosDirectory = Directory(p.join(root.path, 'cocos-js'));
    if (!await cocosDirectory.exists()) {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.notApplicable,
        '资源包不包含 Cocos 引擎目录',
      );
    }

    final virtualBundles = <File>[];
    await for (final entity in cocosDirectory.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).startsWith('_virtual_cc-') &&
          p.extension(entity.path) == '.js') {
        virtualBundles.add(entity);
      }
    }
    if (virtualBundles.isEmpty) {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.notApplicable,
        '资源包不需要 Cocos 音频入口补丁',
      );
    }

    final engine = virtualBundles.where(
      (file) => p.basename(file.path) == _engineFileName,
    );
    if (engine.length != 1) {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.unsupported,
        '检测到不同版本的 Cocos 引擎，iOS 原生音频补丁未应用',
      );
    }

    if (!await _hasSupportedEngineVersion(root)) {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.unsupported,
        'Cocos 引擎版本与音频补丁不匹配，iOS 原生音频补丁未应用',
      );
    }

    final file = engine.single;
    final original = await file.readAsString();
    if (original.contains(_marker)) {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.alreadyApplied,
        'iOS 原生音频入口补丁已存在',
      );
    }

    try {
      var patched = original;
      patched = _replaceExactlyOnce(
        patched,
        'function __pvzgeUseDomAudio',
        '$_marker'
            'function __pvzgeNativeAudioAvailable(){var e=window.__gardendlessNativeAudio;return!!(e&&"function"==typeof e.createNativeAudioHandle)}'
            'function __pvzgeUseDomAudio',
      );
      patched = _replaceExactlyOnce(patched, _domLoad, _patchedDomLoad);
      patched = _replaceExactlyOnce(
        patched,
        _domLoadNative,
        _patchedDomLoadNative,
      );
      patched = _replaceExactlyOnce(
        patched,
        _domLoadOneShot,
        _patchedDomLoadOneShot,
      );
      patched = _replaceExactlyOnce(patched, _routerLoad, _patchedRouterLoad);
      patched = _replaceExactlyOnce(
        patched,
        _routerLoadNative,
        _patchedRouterLoadNative,
      );
      patched = _replaceExactlyOnce(
        patched,
        _routerLoadOneShot,
        _patchedRouterLoadOneShot,
      );
      patched = _replaceExactlyOnce(
        patched,
        _nativeDependency,
        _patchedNativeDependency,
      );
      patched = _replaceExactlyOnce(
        patched,
        _downloadLoad,
        _patchedDownloadLoad,
      );
      patched = _replaceExactlyOnce(
        patched,
        _audioSourceOneShot,
        _patchedAudioSourceOneShot,
      );
      patched = _replaceExactlyOnce(
        patched,
        _clipOneShot,
        _patchedClipOneShot,
      );
      patched = _replaceExactlyOnce(
        patched,
        _domDestroy,
        _patchedDomDestroy,
      );

      await file.writeAsString(patched, flush: true);
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.applied,
        '已为当前资源包启用 iOS 原生音频入口',
      );
    } on FormatException {
      return const CocosAudioFacadePatchResult(
        CocosAudioFacadePatchStatus.unsupported,
        '资源包音频入口与已验证版本不同，iOS 原生音频补丁未应用',
      );
    }
  }

  Future<bool> _hasSupportedEngineVersion(Directory root) async {
    final settings = File(p.join(root.path, 'src', 'settings.json'));
    if (!await settings.exists()) {
      return false;
    }
    try {
      final value = jsonDecode(await settings.readAsString());
      return value is Map && value['CocosEngine'] == _engineVersion;
    } on FormatException {
      return false;
    }
  }

  String _replaceExactlyOnce(String source, String from, String to) {
    final first = source.indexOf(from);
    if (first < 0 || source.indexOf(from, first + from.length) >= 0) {
      throw const FormatException('audio patch anchor mismatch');
    }
    return source.replaceRange(first, first + from.length, to);
  }

  static const _domLoad =
      't.load=function(e){return new Promise((function(i,n){t.loadNative(e).then((function(e){i(new t(e))})).catch(n)}))}';
  static const _patchedDomLoad =
      't.load=function(e,i){return new Promise((function(n,r){t.loadNative(e,{role:"continuous",duration:i&&i.duration}).then((function(e){n(new t(e))})).catch(r)}))}';
  static const _domLoadNative =
      't.loadNative=function(t){return new Promise((function(e,i){var n=document.createElement("audio");n.preload="none",n.__pvzgeLazySrc=t,e(n)}))}';
  static const _patchedDomLoadNative =
      't.loadNative=function(t,e){return new Promise((function(i,n){var r=window.__gardendlessNativeAudio;if(__pvzgeNativeAudioAvailable())try{return void i(r.createNativeAudioHandle(t,e||{role:"continuous"}))}catch(t){return void n(t)}var o=document.createElement("audio");o.preload="none",o.__pvzgeLazySrc=t,i(o)}))}';
  static const _domLoadOneShot =
      't.loadOneShotAudio=function(e,i){return new Promise((function(n,r){t.loadNative(e).then((function(t){var e=new v9(t,i);n(e)})).catch(r)}))}';
  static const _patchedDomLoadOneShot =
      't.loadOneShotAudio=function(e,i,n){return new Promise((function(r,o){t.loadNative(e,{role:__pvzgeUseDomAudio(e)?"continuous":"oneShot",duration:n&&n.duration}).then((function(t){var e=new v9(t,i);r(e)})).catch(o)}))}';
  static const _routerLoad =
      't.load=function(e,i){return new Promise((function(n,r){E9.support&&!__pvzgeUseDomAudio(e)?D9.load(e).then((function(e){n(new t(e))})).catch(r):(E9.support||tt(5201),y9.load(e).then((function(e){n(new t(e))})).catch(r))}))}';
  static const _patchedRouterLoad =
      't.load=function(e,i){return new Promise((function(n,r){__pvzgeNativeAudioAvailable()?y9.load(e,i).then((function(e){n(new t(e))})).catch(r):E9.support&&!__pvzgeUseDomAudio(e)?D9.load(e).then((function(e){n(new t(e))})).catch(r):(E9.support||tt(5201),y9.load(e,i).then((function(e){n(new t(e))})).catch(r))}))}';
  static const _routerLoadNative =
      't.loadNative=function(t,e){returnE9.support&&!__pvzgeUseDomAudio(t)?D9.loadNative(t):(E9.support||tt(5201),y9.loadNative(t))}';
  static const _patchedRouterLoadNative =
      't.loadNative=function(t,e){return __pvzgeNativeAudioAvailable()?y9.loadNative(t,{role:"continuous",duration:e&&e.duration}):E9.support&&!__pvzgeUseDomAudio(t)?D9.loadNative(t):(E9.support||tt(5201),y9.loadNative(t,e))}';
  static const _routerLoadOneShot =
      't.loadOneShotAudio=function(t,e,i){return new Promise((function(n,r){E9.support&&!__pvzgeUseDomAudio(t)?D9.loadOneShotAudio(t,e).then((function(t){n(new B9(t))})).catch(r):(E9.support||tt(5201),y9.loadOneShotAudio(t,e).then((function(t){n(new B9(t))})).catch(r))}))}';
  static const _patchedRouterLoadOneShot =
      't.loadOneShotAudio=function(t,e,i){return new Promise((function(n,r){__pvzgeNativeAudioAvailable()?y9.loadOneShotAudio(t,e,i).then((function(t){n(new B9(t))})).catch(r):E9.support&&!__pvzgeUseDomAudio(t)?D9.loadOneShotAudio(t,e).then((function(t){n(new B9(t))})).catch(r):(E9.support||tt(5201),y9.loadOneShotAudio(t,e,i).then((function(t){n(new B9(t))})).catch(r))}))}';
  static const _nativeDependency =
      'return{uuid:this._uuid,audioLoadMode:this.loadMode,ext:this._native,__isNative__:!0}';
  static const _patchedNativeDependency =
      'return{uuid:this._uuid,audioLoadMode:this.loadMode,duration:this._duration,ext:this._native,__isNative__:!0}';
  static const _downloadLoad = 'P9.load(t,{audioLoadMode:e.audioLoadMode})';
  static const _patchedDownloadLoad =
      'P9.load(t,{audioLoadMode:e.audioLoadMode,duration:e.duration})';
  static const _audioSourceOneShot =
      'P9.loadOneShotAudio(t._nativeAsset.url,this._volume*e,{audioLoadMode:t.loadMode})';
  static const _patchedAudioSourceOneShot =
      'P9.loadOneShotAudio(t._nativeAsset.url,this._volume*e,{audioLoadMode:t.loadMode,duration:t.getDuration()})';
  static const _clipOneShot = 'P9.loadOneShotAudio(this._nativeAsset.url,t)';
  static const _patchedClipOneShot =
      'P9.loadOneShotAudio(this._nativeAsset.url,t,{duration:this.getDuration()})';
  static const _domDestroy =
      'e.destroy=function(){bB.off(AB.EVENT_PAUSE,this._onInterruptedBegin,this),bB.off(AB.EVENT_RESUME,this._onInterruptedEnd,this),this._domAudio.removeEventListener("ended",this._onEnded),this._domAudio=null}';
  static const _patchedDomDestroy =
      'e.destroy=function(){bB.off(AB.EVENT_PAUSE,this._onInterruptedBegin,this),bB.off(AB.EVENT_RESUME,this._onInterruptedEnd,this),this._domAudio.removeEventListener("ended",this._onEnded),"function"==typeof this._domAudio.release&&this._domAudio.release(),this._domAudio=null}';
}
