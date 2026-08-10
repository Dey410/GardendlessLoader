import common from '@ohos.app.ability.common';
import display from '@ohos.display';
import window from '@ohos.window';

const COMPACT_BREAKPOINT_VP: number = 600;

export function isCompactDocumentPickerWindow(widthVp: number, heightVp: number): boolean {
  return widthVp < COMPACT_BREAKPOINT_VP || heightVp < COMPACT_BREAKPOINT_VP;
}

export async function withDocumentPickerOrientation<T>(
  context: common.UIAbilityContext,
  pickerAction: () => Promise<T>,
): Promise<T> {
  let hostWindow: window.Window | null = null;
  try {
    hostWindow = await window.getLastWindow(context);
    const windowRect = hostWindow.getWindowProperties().windowRect;
    const displayDensity = display.getDefaultDisplaySync().densityPixels;
    const densityPixels = displayDensity > 0 ? displayDensity : 1;
    const widthVp = windowRect.width / densityPixels;
    const heightVp = windowRect.height / densityPixels;
    const orientation = isCompactDocumentPickerWindow(widthVp, heightVp)
      ? window.Orientation.AUTO_ROTATION_PORTRAIT
      : window.Orientation.AUTO_ROTATION_UNSPECIFIED;
    await hostWindow.setPreferredOrientation(orientation);
  } catch (error) {
    console.warn(`Unable to prepare document picker orientation: ${(error as Error).message}`);
  }

  try {
    return await pickerAction();
  } finally {
    if (hostWindow != null) {
      try {
        await hostWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
      } catch (error) {
        console.warn(`Unable to restore landscape orientation: ${(error as Error).message}`);
      }
    }
  }
}
