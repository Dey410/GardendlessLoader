import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { ExportRecord, GameBridge } from '../game/GameBridge';
import { NativeGameResourceHandler } from '../game/NativeGameResourceHandler';
import { GameSession } from '../game/GameSession';
import { appLogStore, AppLogContext, AppLogEvent } from '../logging/AppLogStore';
import { withDocumentPickerOrientation } from '../picker/DocumentPickerOrientation';

let storage = LocalStorage.getShared();

/** The two tones of the game frame, derived from the launcher theme accent. */
class LetterboxTone {
  readonly outer: string;
  readonly inner: string;

  private constructor(outer: string, inner: string) {
    this.outer = outer;
    this.inner = inner;
  }

  static of(accent: number | null): LetterboxTone {
    // No accent, or a transparent one, keeps the neutral dark bezel.
    if (accent === null || Math.floor(accent / 0x1000000) % 256 === 0) {
      return new LetterboxTone('#0E0F11', '#2A2B30');
    }
    const red = Math.floor(accent / 0x10000) % 256 / 255;
    const green = Math.floor(accent / 0x100) % 256 / 255;
    const blue = accent % 256 / 255;
    const maximum = Math.max(red, green, blue);
    const minimum = Math.min(red, green, blue);
    const delta = maximum - minimum;
    let hue = 0;
    if (delta !== 0) {
      if (maximum === red) {
        hue = ((green - blue) / delta) % 6;
      } else if (maximum === green) {
        hue = (blue - red) / delta + 2;
      } else {
        hue = (red - green) / delta + 4;
      }
      hue *= 60;
      if (hue < 0) {
        hue += 360;
      }
    }
    const saturation = maximum === 0 ? 0 : delta / maximum;
    // Keep the accent's hue but cap saturation and brightness, so every theme
    // yields a deep bezel instead of a bright band around the canvas. The caps
    // are shared with the iOS and Android hosts.
    return new LetterboxTone(
      LetterboxTone.hsv(hue, Math.min(saturation, 0.40), 0.075),
      LetterboxTone.hsv(hue, Math.min(saturation, 0.55), 0.34),
    );
  }

  private static hsv(hue: number, saturation: number, value: number): string {
    const chroma = value * saturation;
    const second = chroma * (1 - Math.abs(hue / 60 % 2 - 1));
    const offset = value - chroma;
    let red = 0;
    let green = 0;
    let blue = 0;
    switch (Math.floor(hue / 60) % 6) {
      case 0:
        red = chroma;
        green = second;
        break;
      case 1:
        red = second;
        green = chroma;
        break;
      case 2:
        green = chroma;
        blue = second;
        break;
      case 3:
        green = second;
        blue = chroma;
        break;
      case 4:
        red = second;
        blue = chroma;
        break;
      default:
        red = chroma;
        blue = second;
        break;
    }
    return `#${LetterboxTone.hex(red + offset)}${LetterboxTone.hex(green + offset)}` +
      `${LetterboxTone.hex(blue + offset)}`;
  }

  private static hex(channel: number): string {
    const value = Math.round(channel * 255).toString(16).toUpperCase();
    return value.length === 1 ? `0${value}` : value;
  }
}

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
  // Foreground play time; shownAt is the clock while the page shows, else 0.
  private playedMs: number = 0;
  private shownAt: number = 0;
  // Exit result writes run in order: the provisional one written while the
  // page is hidden must never land after its removal or the final result.
  private exitRecord: Promise<void> = Promise.resolve();
  @State private viewportWidth: string = '100%';
  @State private viewportHeight: string = '100%';
  @State private viewportScaleX: number = 1;
  @State private viewportScaleY: number = 1;
  private frameSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private frameContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.frameSettings);
  private frameReady: boolean = false;
  private frameWidth: number = 0;
  private frameHeight: number = 0;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private canvasStretch: boolean = false;
  private canvasFrameEnabled: boolean = true;
  private frameTone: LetterboxTone = LetterboxTone.of(null);

  aboutToAppear(): void {
    try {
      this.session = new GameSession(this.sessionJson);
      this.canvasFrameEnabled = this.session.canvasFrameEnabled;
      this.frameTone = LetterboxTone.of(this.session.frameAccent);
      const createdEvent: AppLogEvent = {
        source: 'ohos', level: 'INFO', category: 'game.host',
        event: 'game_host_created', outcome: 'succeeded',
        gameSessionId: this.session.sessionId,
      };
      appLogStore.emit(createdEvent);
      this.resourceHandler = new NativeGameResourceHandler(this.session);
      this.bridge = new GameBridge(this.controller, this.context, this.session, (): void => {
        this.returnToLauncher('userReturned', null);
      });
      this.documentStartScripts = [{
        script: this.buildDocumentStartScript(this.session),
        scriptRules: [GameSession.ORIGIN],
      }];
    } catch (error) {
      const launchError = error as Error;
      const failureContext: AppLogContext = { stage: 'game_page_about_to_appear' };
      const failureEvent: AppLogEvent = {
        source: 'ohos',
        level: 'ERROR',
        category: 'game.host',
        event: 'game_page_initialization_failed',
        outcome: 'failed',
        code: 'game_page_initialization_failed',
        message: launchError.message,
        context: failureContext,
      };
      appLogStore.emit(failureEvent);
      this.writeLaunchFailure(launchError.message);
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
      Canvas(this.frameContext)
        .width('100%')
        .height('100%')
        .onReady((): void => {
          this.frameReady = true;
          this.paintFrame();
        })
      Web({ src: '', controller: this.controller })
        .width(this.viewportWidth)
        .height(this.viewportHeight)
        .scale({ x: this.viewportScaleX, y: this.viewportScaleY })
        .backgroundColor(Color.Black)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .runJavaScriptOnDocumentStart(this.documentStartScripts)
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
            const loadStartedEvent: AppLogEvent = {
              source: 'ohos', level: 'INFO', category: 'game.webview',
              event: 'webview_page_load_started', outcome: 'started',
              gameSessionId: session.sessionId,
            };
            appLogStore.emit(loadStartedEvent);
          } catch (error) {
            const loadFailedEvent: AppLogEvent = {
              source: 'ohos', level: 'ERROR', category: 'game.webview',
              event: 'webview_page_load_finished', outcome: 'failed',
              code: 'webview_page_load_failed', message: (error as Error).message,
              gameSessionId: session.sessionId,
            };
            appLogStore.emit(loadFailedEvent);
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
          const external = request.isMainFrame() && this.session != null
            ? this.session.allowedRemoteUrl(url, ['https:'])
            : null;
          if (external != null) {
            this.context.startAbility({ action: 'ohos.want.action.viewData', uri: external })
              .catch((_error: Error): void => {});
          }
          if (this.session != null) {
            const navigationEvent: AppLogEvent = {
              source: 'ohos', level: 'WARN', category: 'game.security',
              event: 'navigation_blocked', outcome: 'observed',
              gameSessionId: this.session.sessionId,
            };
            appLogStore.emit(navigationEvent);
          }
          return true;
        })
        .onShowFileSelector((event): boolean => {
          if (event == null) {
            return true;
          }
          const options = new picker.DocumentSelectOptions();
          withDocumentPickerOrientation(
            this.context,
            (): Promise<string[]> => new picker.DocumentViewPicker().select(options),
          ).then((uris: string[]): void => {
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
          if (this.session != null) {
            const renderExitEvent: AppLogEvent = {
              source: 'ohos', level: 'ERROR', category: 'game.webview',
              event: 'webview_render_process_gone', outcome: 'failed',
              code: 'webview_render_process_gone', message: message,
              gameSessionId: this.session.sessionId,
            };
            appLogStore.emit(renderExitEvent);
          }
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

  // While hidden, a provisional exit result tells the launcher that a system
  // that ends the app ended it in the background, not during play.
  onPageShow(): void {
    this.shownAt = Date.now();
    const session = this.session;
    if (session != null && !this.exiting) {
      this.exitRecord = this.exitRecord.then((): Promise<void> =>
        fs.unlink(`${session.appRoot}/game_exit_result.json`).catch((_error: Error): void => {}));
    }
  }

  onPageHide(): void {
    if (this.shownAt !== 0) {
      this.playedMs += Date.now() - this.shownAt;
    }
    this.shownAt = 0;
    const session = this.session;
    if (session != null && !this.exiting) {
      const playedMs = this.playedMs;
      this.exitRecord = this.exitRecord.then((): Promise<void> => this.writeExitResult(
        session.appRoot, session.sessionId, 'systemTerminated', null, session.packageId, playedMs,
        this.bridge?.exports ?? []));
    }
  }

  onBackPress(): boolean {
    this.returnToLauncher('userReturned', null);
    return true;
  }

  private updateViewport(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }
    const screenFit = this.session?.screenFit ?? 'balanced';
    // Show all keeps the whole 17:9 picture; the other fits allow 16:10–17:9.
    const maximumAspectRatio = 17 / 9;
    const minimumAspectRatio = screenFit === 'showAll' ? maximumAspectRatio : 16 / 10;
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
    // The page keeps the balanced viewport; scaling around the centre
    // stretches it over the whole window.
    if (screenFit === 'stretch') {
      this.viewportScaleX = width / viewportWidth;
      this.viewportScaleY = height / viewportHeight;
    }
    this.frameWidth = width;
    this.frameHeight = height;
    this.canvasWidth = viewportWidth;
    this.canvasHeight = viewportHeight;
    this.canvasStretch = screenFit === 'stretch';
    this.paintFrame();
  }

  /// Frames the page with a graded bezel so the bars read as a finished border
  /// instead of an empty gap. Static: repainted only when the window or the
  /// page geometry changes, never per frame.
  private paintFrame(): void {
    if (!this.frameReady || this.frameWidth <= 0 || this.frameHeight <= 0) {
      return;
    }
    const context = this.frameContext;
    const width = this.frameWidth;
    const height = this.frameHeight;
    const showFrame = this.canvasFrameEnabled && !this.canvasStretch;
    context.clearRect(0, 0, width, height);
    // With the frame off the letterbox bars stay pure black.
    context.fillStyle = showFrame ? this.frameTone.outer : '#000000';
    context.fillRect(0, 0, width, height);
    if (!showFrame) {
      return;
    }
    const left = (width - this.canvasWidth) / 2;
    const top = (height - this.canvasHeight) / 2;
    const right = left + this.canvasWidth;
    const bottom = top + this.canvasHeight;
    this.paintBar(context, 0, 0, width, top, 0, 0, 0, top);
    this.paintBar(context, 0, bottom, width, height - bottom, 0, height, 0, bottom);
    this.paintBar(context, 0, 0, left, height, 0, 0, left, 0);
    this.paintBar(context, right, 0, width - right, height, width, 0, right, 0);
    const hasBars = left > 0 || top > 0 || right < width || bottom < height;
    if (hasBars) {
      context.strokeStyle = 'rgba(255, 255, 255, 0.10)';
      context.lineWidth = 1.5;
      context.strokeRect(left - 0.75, top - 0.75, this.canvasWidth + 1.5, this.canvasHeight + 1.5);
    }
  }

  /// Each bar fades from the bezel tone at the screen edge to the lifted tone
  /// against the page, matching the iOS and Android hosts.
  private paintBar(
    context: CanvasRenderingContext2D,
    x: number,
    y: number,
    barWidth: number,
    barHeight: number,
    startX: number,
    startY: number,
    endX: number,
    endY: number,
  ): void {
    if (barWidth <= 0 || barHeight <= 0) {
      return;
    }
    const gradient = context.createLinearGradient(startX, startY, endX, endY);
    gradient.addColorStop(0, this.frameTone.outer);
    gradient.addColorStop(1, this.frameTone.inner);
    context.fillStyle = gradient;
    context.fillRect(x, y, barWidth, barHeight);
  }

  private buildDocumentStartScript(session: GameSession): string {
    const config = JSON.stringify({
      hostAbi: 1,
      platform: 'ohos',
      touchWheelCssMultiplier: -4.5,
      touchGestureMode: session.gestureMode,
      touchDiagnosticsEnabled: session.touchDiagnosticsEnabled,
      origin: GameSession.ORIGIN,
      activationGeneration: session.activationGeneration,
      hasGpNext: session.hasGpNext,
      gpNextCompatible: session.gpNextCompatible,
      gpNextVersion: session.gpNextVersion,
      watermarkEnabled: session.watermarkEnabled,
      autoCollectSunEnabled: session.autoCollectSunEnabled,
      hapticEffectsEnabled: session.hapticEffectsEnabled,
      detailedAudioDiagnosticsEnabled: session.detailedAudioDiagnosticsEnabled,
      renderScale: session.renderScale,
      gestureHint: session.gestureHint,
      gpNextBaseDirectory: this.gpNextBaseDirectory(session),
    });
    const names: string[] = [
      'transport.js',
      'logging.js',
      'game_tip.js',
      'audio_diagnostic.js',
      'auto_sun.js',
      'touch_state_machine.js',
      'touch_input_adapter.js',
      'native_gestures.js',
      'gamepad.js',
      'pause_on_return.js',
      'haptic_effects.js',
      'render_scale.js',
      'export_download_patch.js',
    ];
    names.push('watermark.js');
    names.push('gesture_hint.js');
    let source = `window.__gardendlessHostConfig=${config};`;
    for (const name of names) {
      const bytes = this.context.resourceManager.getRawFileContentSync(
        `flutter_assets/assets/game_bridge/${name}`,
      );
      source += `\n${util.TextDecoder.create('utf-8').decodeToString(bytes)}`;
    }
    return source;
  }

  private gpNextBaseDirectory(session: GameSession): string {
    const separator = session.gpNextRoot.lastIndexOf('/');
    return separator > 0 ? session.gpNextRoot.substring(0, separator) : session.appRoot;
  }

  private writeLaunchFailure(message: string): void {
    let exitResult: Promise<void> = Promise.resolve();
    try {
      const raw = JSON.parse(this.sessionJson) as Record<string, Object>;
      const root = raw['resourceRoot'] as string;
      const sessionId = raw['sessionId'] as string;
      const slash = root.lastIndexOf('/');
      if (slash > 0) {
        exitResult = this.writeExitResult(root.substring(0, slash), sessionId, 'launchFailed', message);
      }
    } catch (_error) {
    }
    Promise.all([exitResult, appLogStore.flush()]).finally((): void => this.startLauncher());
  }

  private returnToLauncher(reason: string, message: string | null): void {
    if (this.exiting) {
      return;
    }
    this.exiting = true;
    let exitResult: Promise<void> = Promise.resolve();
    const session = this.session;
    if (session != null) {
      const context: AppLogContext = { reason: reason, packageId: session.packageId };
      const finishedEvent: AppLogEvent = {
        source: 'ohos',
        level: reason === 'rendererGone' || reason === 'launchFailed' ? 'ERROR' : 'INFO',
        category: 'game.host', event: 'game_host_finished',
        outcome: reason === 'rendererGone' || reason === 'launchFailed' ? 'failed' : 'succeeded',
        gameSessionId: session.sessionId,
        context: context,
      };
      if (message != null) finishedEvent.message = message;
      appLogStore.emit(finishedEvent);
      const playedMs = this.playedMs + (this.shownAt !== 0 ? Date.now() - this.shownAt : 0);
      const exports = this.bridge?.exports ?? [];
      exitResult = this.exitRecord.then((): Promise<void> => this.writeExitResult(
        session.appRoot, session.sessionId, reason, message, session.packageId, playedMs, exports));
    }
    this.bridge?.destroy();
    Promise.all([exitResult, appLogStore.flush()]).finally((): void => this.startLauncher());
  }

  private async writeExitResult(
    appRoot: string,
    sessionId: string,
    reason: string,
    message: string | null,
    packageId: string = 'unknown',
    playedMs: number = 0,
    exports: ExportRecord[] = [],
  ): Promise<void> {
    const output = `${appRoot}/game_exit_result.json`;
    const temporary = `${output}.tmp`;
    const value = JSON.stringify({
      schemaVersion: 1,
      packageId: packageId,
      sessionId: sessionId,
      reason: reason,
      finishedAt: new Date().toISOString(),
      message: message,
      playedMs: Math.round(playedMs),
      exports: exports,
    }, null, 2);
    try {
      await this.writeTextFile(temporary, `${value}\n`);
      await fs.rename(temporary, output);
    } catch (_error) {
    }
  }

  private async writeTextFile(path: string, value: string): Promise<void> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(
        path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW,
      );
      const count = await fs.write(file.fd, value);
      if (count !== new util.TextEncoder().encodeInto(value).byteLength) throw new Error('Exit record write was incomplete');
      await fs.fsync(file.fd);
    } finally {
      if (file != null) {
        await fs.close(file.fd);
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
