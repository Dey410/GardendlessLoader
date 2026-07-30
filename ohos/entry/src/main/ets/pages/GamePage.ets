import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { GameBridge } from '../game/GameBridge';
import { NativeGameResourceHandler } from '../game/NativeGameResourceHandler';
import { GameSession } from '../game/GameSession';

let storage = LocalStorage.getShared();

@Entry(storage)
@Component
struct GamePage {
  @LocalStorageLink('gameSession') sessionJson: string = '';
  private readonly context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private session: GameSession | null = null;
  private resourceHandler: NativeGameResourceHandler | null = null;
  private bridge: GameBridge | null = null;
  private documentStartScripts: Array<ScriptItem> = [];
  private exiting: boolean = false;
  @State private viewportWidth: string = '100%';
  @State private viewportHeight: string = '100%';

  aboutToAppear(): void {
    try {
      this.session = new GameSession(this.sessionJson);
      this.resourceHandler = new NativeGameResourceHandler(this.session);
      this.bridge = new GameBridge(this.controller, this.context, this.session, (): void => {
        this.returnToLauncher('userReturned', null);
      });
      this.documentStartScripts = [{
        script: this.buildDocumentStartScript(this.session),
        scriptRules: [`${GameSession.ORIGIN}/*`],
      }];
    } catch (error) {
      this.writeLaunchFailure((error as Error).message);
    }
  }

  aboutToDisappear(): void {
    this.bridge?.destroy();
    this.resourceHandler?.destroy();
    try {
      this.controller.deleteJavaScriptRegister('gardendlessNative');
    } catch (_error) {
    }
  }

  build() {
    Stack() {
      Web({ src: 'about:blank', controller: this.controller })
        .width(this.viewportWidth)
        .height(this.viewportHeight)
        .backgroundColor(Color.Black)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .javaScriptOnDocumentStart(this.documentStartScripts)
        .onControllerAttached((): void => {
          const session = this.session;
          const bridge = this.bridge;
          const resourceHandler = this.resourceHandler;
          if (session == null || bridge == null || resourceHandler == null) {
            this.returnToLauncher('launchFailed', 'Native GameHost session is unavailable');
            return;
          }
          try {
            resourceHandler.attach(this.controller);
            const permission =
              '{"javascriptProxyPermission":{"urlPermissionList":[{"scheme":"https",' +
              '"host":"gardendless.invalid","port":"","path":""}]}}';
            this.controller.registerJavaScriptProxy(
              bridge,
              'gardendlessNative',
              ['postMessage'],
              [],
              permission,
            );
            this.controller.loadUrl(session.entryUrl);
          } catch (error) {
            this.returnToLauncher('launchFailed', (error as Error).message);
          }
        })
        .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
          if (request == null) {
            return true;
          }
          const url = request.getRequestUrl();
          if (url === GameSession.ORIGIN || url.startsWith(`${GameSession.ORIGIN}/`)) {
            return false;
          }
          if (url.startsWith('https://')) {
            this.context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
              .catch((_error: Error): void => {});
          }
          return true;
        })
        .onShowFileSelector((event): boolean => {
          if (event == null) {
            return true;
          }
          const options = new picker.DocumentSelectOptions();
          new picker.DocumentViewPicker().select(options).then((uris: string[]): void => {
            event.result.handleFileList(uris);
          }).catch((_error: Error): void => {
            event.result.handleFileList([]);
          });
          return true;
        })
        .onRenderExited((event): void => {
          const message = event == null
            ? 'ArkWeb renderer exited'
            : `ArkWeb renderer exited: ${event.renderExitReason}`;
          this.returnToLauncher('rendererGone', message);
        });
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .backgroundColor(Color.Black)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewport(
        Number.parseFloat(newArea.width.toString()),
        Number.parseFloat(newArea.height.toString()),
      );
    });
  }

  onBackPress(): boolean {
    this.returnToLauncher('userReturned', null);
    return true;
  }

  private updateViewport(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }
    const minimumAspectRatio = 16 / 10;
    const maximumAspectRatio = 17 / 9;
    const aspectRatio = width / height;
    let viewportWidth = width;
    let viewportHeight = height;
    if (aspectRatio > maximumAspectRatio) {
      viewportWidth = Math.floor(height * maximumAspectRatio);
    } else if (aspectRatio < minimumAspectRatio) {
      viewportHeight = Math.floor(width / minimumAspectRatio);
    }
    this.viewportWidth = `${viewportWidth}vp`;
    this.viewportHeight = `${viewportHeight}vp`;
  }

  private buildDocumentStartScript(session: GameSession): string {
    const config = JSON.stringify({
      platform: 'ohos',
      origin: GameSession.ORIGIN,
      activationGeneration: session.activationGeneration,
      hasGpNext: session.hasGpNext,
      gpNextCompatible: session.gpNextCompatible,
      gpNextVersion: session.gpNextVersion,
      watermarkEnabled: session.watermarkEnabled,
      autoCollectSunEnabled: session.autoCollectSunEnabled,
      gpNextBaseDirectory: session.appRoot,
    });
    const names: string[] = [
      'transport.js',
      'bootstrap.js',
      'auto_sun.js',
      'touch_patch.js',
      'export_download_patch.js',
    ];
    if (session.hasGpNext && session.gpNextCompatible) {
      names.push('gp_next_core.js');
      names.push('gp_next_compat_bridge.js');
    }
    names.push('watermark.js');
    let source = `window.__gardendlessHostConfig=${config};`;
    for (const name of names) {
      const bytes = this.context.resourceManager.getRawFileContentSync(
        `flutter_assets/assets/game_bridge/${name}`,
      );
      source += `\n${util.TextDecoder.create('utf-8').decodeToString(bytes)}`;
    }
    return source;
  }

  private writeLaunchFailure(message: string): void {
    try {
      const raw = JSON.parse(this.sessionJson) as Record<string, Object>;
      const root = raw['resourceRoot'] as string;
      const sessionId = raw['sessionId'] as string;
      const slash = root.lastIndexOf('/');
      if (slash > 0) {
        this.writeExitResult(root.substring(0, slash), sessionId, 'launchFailed', message);
      }
    } catch (_error) {
    }
    this.startLauncher();
  }

  private returnToLauncher(reason: string, message: string | null): void {
    if (this.exiting) {
      return;
    }
    this.exiting = true;
    const session = this.session;
    if (session != null) {
      this.writeExitResult(session.appRoot, session.sessionId, reason, message);
    }
    this.bridge?.destroy();
    this.startLauncher();
  }

  private writeExitResult(
    appRoot: string,
    sessionId: string,
    reason: string,
    message: string | null,
  ): void {
    const output = `${appRoot}/game_exit_result.json`;
    const temporary = `${output}.tmp`;
    const value = JSON.stringify({
      schemaVersion: 1,
      sessionId: sessionId,
      reason: reason,
      finishedAt: new Date().toISOString(),
      message: message,
    }, null, 2);
    try {
      this.writeTextFile(temporary, `${value}\n`);
      fs.renameSync(temporary, output);
    } catch (_error) {
    }
  }

  private writeTextFile(path: string, value: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(
        path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
      );
      fs.writeSync(file.fd, value);
    } finally {
      if (file != null) {
        fs.closeSync(file.fd);
      }
    }
  }

  private startLauncher(): void {
    this.context.startAbility({
      bundleName: 'io.github.dey410.gardendlessloader',
      abilityName: 'EntryAbility',
    }).finally((): void => {
      this.context.terminateSelf();
    });
  }
}
