import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { PaperStore } from '../common/PaperStore';

export default class ManagerAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.showAndRestyle();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindow = windowStage.getMainWindowSync();
    this.applyWindowStyle();
    windowStage.loadContent('pages/Index', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load settings failed: ' + JSON.stringify(error));
        return;
      }
      this.configureWindowGeometry().catch((reason: Error): void => {
        console.error('configure settings window failed: ' + reason.message);
      });
    });
  }

  onForeground(): void {
    this.applyWindowStyle();
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.mainWindow = null;
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private showAndRestyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    win.restore().catch((_restoreError: BusinessError): Promise<void> => win.showWindow())
      .then((): void => this.applyWindowStyle())
      .catch((error: BusinessError): void => {
        console.error('show settings failed: ' + error.message);
      });
  }

  private applyWindowStyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.error('hide settings decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.error('hide settings title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.error('clear settings background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.error('clear settings container failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.error('disable settings shadow failed: ' + error.message);
    });
  }

  private async configureWindowGeometry(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    const uiContext: UIContext = win.getUIContext();
    const screen: display.Display = display.getDefaultDisplaySync();
    const availableWidth: number = screen.availableWidth > 0 ? screen.availableWidth : screen.width;
    const availableHeight: number = screen.availableHeight > 0 ? screen.availableHeight : screen.height;
    const widthVp: number = Math.min(720, Math.max(520, uiContext.px2vp(availableWidth) - 48));
    const heightVp: number = Math.min(660, Math.max(500, uiContext.px2vp(availableHeight) - 48));
    const widthPx: number = Math.round(uiContext.vp2px(widthVp));
    const heightPx: number = Math.round(uiContext.vp2px(heightVp));
    await win.resize(widthPx, heightPx);
    await win.moveWindowTo(Math.max(0, Math.round((availableWidth - widthPx) / 2)),
      Math.max(0, Math.round((availableHeight - heightPx) / 2)));
    this.applyWindowStyle();
  }
}
