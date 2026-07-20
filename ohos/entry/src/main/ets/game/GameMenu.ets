import { webview } from '@kit.ArkWeb';

export class GameMenu {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  open(): void {
    this.controller.runJavaScript(
      'window.__gardendlessMenu && window.__gardendlessMenu.open()',
    ).catch((_error: Error): void => {});
  }
}
