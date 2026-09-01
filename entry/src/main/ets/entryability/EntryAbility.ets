import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { DesktopShell } from '../common/DesktopShell';
import { PAPER_TYPE_TODO, PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import { TrayService } from '../common/TrayService';

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | null = null;
  private hostWindow: window.Window | null = null;
  private launchGeneration: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate<string>('recoveryReason', '');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const generation: number = ++this.launchGeneration;
    DesktopShell.showAll(this.context).then((): void => {
      if (generation !== this.launchGeneration) {
        return;
      }
      TrayService.install(this.context).then((installed: boolean): void => {
        if (installed) {
          DesktopShell.startResident(this.context);
        }
      });
    }).catch((error: Error): void => {
      console.error('handle launcher reactivation failed: ' + error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    this.hostWindow = windowStage.getMainWindowSync();
    this.applyHiddenHostStyle();
    windowStage.loadContent('pages/Host', (error: BusinessError): void => {
      if (error.code !== 0) {
        this.showRecovery('无法加载后台宿主页：' + error.message);
        return;
      }
      this.bootstrap().catch((reason: Error): void => {
        this.showRecovery('桌面入口启动失败：' + reason.message);
      });
    });
  }

  onForeground(): void {
    this.applyHiddenHostStyle();
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
    this.hostWindow = null;
    this.windowStage = null;
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private async bootstrap(): Promise<void> {
    this.applyHiddenHostStyle();
    const statusInstalled: boolean = await TrayService.install(this.context);
    let residentStarted: boolean = false;
    if (statusInstalled) {
      residentStarted = await DesktopShell.startResident(this.context);
    }

    let papers: PaperData[] = PaperStore.listPapers();
    if (papers.length === 0 && !PaperStore.hasStorageError()) {
      const replacement: PaperData | null = PaperStore.createPaper(PAPER_TYPE_TODO);
      papers = replacement === null ? [] : [replacement];
    }

    const starts: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].isVisible) {
        starts.push(DesktopShell.startPaper(this.context, papers[i].id));
      }
    }
    const results: boolean[] = await Promise.all(starts);
    let paperStarted: boolean = starts.length === 0;
    for (let i: number = 0; i < results.length; i++) {
      paperStarted = paperStarted || results[i];
    }

    if (!statusInstalled && !paperStarted) {
      this.showRecovery('状态栏入口和纸张窗口均未能启动。');
      return;
    }

    if (residentStarted) {
      await this.context.terminateSelf();
      return;
    }

    // If the platform accepted the status-bar item but refused the attached resident,
    // keep this tiny host alive so the item does not disappear with the process.
    this.minimizeHost();
  }

  private applyHiddenHostStyle(): void {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowDecorHeight(0);
      win.setWindowTitleMoveEnabled(false);
      win.setWindowBackgroundColor('#00000000');
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.error('style entry host failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.error('disable entry shadow failed: ' + error.message);
    });
  }

  private minimizeHost(): void {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    this.applyHiddenHostStyle();
    win.setWindowTouchable(false).catch((error: BusinessError): void => {
      console.error('disable entry host touch failed: ' + error.message);
    });
    win.setWindowFocusable(false).catch((error: BusinessError): void => {
      console.error('disable entry host focus failed: ' + error.message);
    });
    win.minimize().catch((error: BusinessError): void => {
      console.error('minimize entry host failed: ' + error.message);
    });
  }

  private showRecovery(reason: string): void {
    AppStorage.setOrCreate<string>('recoveryReason', reason);
    const stage: window.WindowStage | null = this.windowStage;
    const win: window.Window | null = this.hostWindow;
    if (stage === null || win === null) {
      return;
    }
    stage.loadContent('pages/Recovery', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load recovery page failed: ' + error.message);
        return;
      }
      this.configureRecoveryWindow();
    });
  }

  private configureRecoveryWindow(): void {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    this.applyHiddenHostStyle();
    const screen: display.Display = display.getDefaultDisplaySync();
    const uiContext: UIContext = win.getUIContext();
    const widthPx: number = Math.round(uiContext.vp2px(460));
    const heightPx: number = Math.round(uiContext.vp2px(300));
    const availableWidth: number = screen.availableWidth > 0 ? screen.availableWidth : screen.width;
    const availableHeight: number = screen.availableHeight > 0 ? screen.availableHeight : screen.height;
    win.setWindowTouchable(true).catch((error: BusinessError): void => {
      console.error('enable recovery touch failed: ' + error.message);
    });
    win.setWindowFocusable(true).catch((error: BusinessError): void => {
      console.error('enable recovery focus failed: ' + error.message);
    });
    win.resize(widthPx, heightPx)
      .then((): Promise<void> => win.moveWindowTo(Math.max(0, Math.round((availableWidth - widthPx) / 2)),
        Math.max(0, Math.round((availableHeight - heightPx) / 2))))
      .then((): Promise<void> => win.showWindow())
      .then((): void => this.applyHiddenHostStyle())
      .catch((error: BusinessError): void => {
        console.error('show recovery window failed: ' + error.message);
      });
  }
}
