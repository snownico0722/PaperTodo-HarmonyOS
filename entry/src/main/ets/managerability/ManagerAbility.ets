import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  StartOptions,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { PaperStore } from '../common/PaperStore';

export default class ManagerAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private runtimeStartIssued: boolean = false;
  private showRunning: boolean = false;
  private showPending: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    // The invisible runtime host is a cold-start dependency only. Re-launching
    // it from taskbar/new-want/foreground paths can make that hidden UIAbility
    // become the newest foreground mission and steal activation from Settings.
    this.startRuntimeHostOnce();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.requestSettingsShow();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindow = windowStage.getMainWindowSync();
    this.applyWindowStyle();
    windowStage.loadContent('pages/Index', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load settings failed: ' + JSON.stringify(error));
        return;
      }
      this.configureWindowGeometry().then((): void => {
        // Drain any activation request that arrived while the page was loading.
        this.requestSettingsShow();
      }).catch((reason: Error): void => {
        console.error('configure settings window failed: ' + reason.message);
      });
    });
  }

  onForeground(): void {
    this.requestSettingsShow();
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
    this.showPending = false;
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private startRuntimeHostOnce(): void {
    if (this.runtimeStartIssued) {
      return;
    }
    this.runtimeStartIssued = true;
    const want: Want = {
      bundleName: 'com.papertodo.app',
      moduleName: 'entry',
      abilityName: 'EntryAbility'
    };
    const options: StartOptions = { hideStartWindow: true };
    this.context.startAbility(want, options).catch((error: BusinessError): void => {
      // Permit one later ManagerAbility recreation to retry a failed cold start,
      // but never retry from onNewWant/onForeground in this instance.
      this.runtimeStartIssued = false;
      console.error('start PaperTodo runtime host failed: ' + error.message);
    });
  }

  private requestSettingsShow(): void {
    this.showPending = true;
    if (this.showRunning) {
      return;
    }
    this.showRunning = true;
    this.runSettingsShowLoop().then((): void => {
      this.showRunning = false;
      if (this.showPending) {
        this.requestSettingsShow();
      }
    }).catch((error: Error): void => {
      this.showRunning = false;
      console.error('show settings loop failed: ' + error.message);
      if (this.showPending) {
        this.requestSettingsShow();
      }
    });
  }

  private async runSettingsShowLoop(): Promise<void> {
    while (this.showPending) {
      this.showPending = false;
      await this.showSettingsWindow();
    }
  }

  private async showSettingsWindow(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      await win.setWindowFocusable(true);
    } catch (error) {
      console.warn('enable settings focus failed: ' + String(error));
    }
    try {
      await win.restore();
    } catch (restoreError) {
      try {
        await win.showWindow();
      } catch (showError) {
        console.error('show settings failed after restore error: ' + String(showError));
        return;
      }
    }
    try {
      await win.showWindow();
    } catch (error) {
      console.warn('ensure settings visible failed: ' + String(error));
    }
    this.applyWindowStyle();
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
    try {
      await win.resizeAsync(widthPx, heightPx);
      await win.moveWindowToAsync(Math.max(0, Math.round((availableWidth - widthPx) / 2)),
        Math.max(0, Math.round((availableHeight - heightPx) / 2)));
    } catch (error) {
      console.warn('async settings geometry failed, falling back: ' + String(error));
      await win.resize(widthPx, heightPx);
      await win.moveWindowTo(Math.max(0, Math.round((availableWidth - widthPx) / 2)),
        Math.max(0, Math.round((availableHeight - heightPx) / 2)));
    }
    this.applyWindowStyle();
    await win.showWindow();
  }
}
