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
import { AppState, PAPER_TYPE_TODO, PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import { TrayService } from '../common/TrayService';

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | null = null;
  private hostWindow: window.Window | null = null;
  private recoveryVisible: boolean = false;
  private hideRunning: boolean = false;
  private hidePending: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate<string>('recoveryReason', '');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // ManagerAbility is the only launcher/taskbar mission. EntryAbility is a
    // runtime host and must immediately return to the background if the system
    // reuses this singleton instance for any later internal start.
    this.applyHiddenHostStyle();
    DesktopShell.syncCapsules(this.context).catch((error: Error): void => {
      console.warn('refresh capsules from runtime host failed: ' + error.message);
    });
    this.requestRuntimeHide();
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
    this.requestRuntimeHide();
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
    this.hidePending = false;
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
      residentStarted = await this.startResidentWithRetry();
    }

    let papers: PaperData[] = PaperStore.listPapers();
    if (papers.length === 0 && !PaperStore.hasStorageError()) {
      const replacement: PaperData | null = PaperStore.createPaper(PAPER_TYPE_TODO);
      papers = replacement === null ? [] : [replacement];
    }

    const starts: Promise<boolean>[] = [];
    const state: AppState = PaperStore.loadState();
    for (let i: number = 0; i < papers.length; i++) {
      const delegatedToEdge: boolean = papers[i].isCollapsed && state.useCapsuleMode &&
        state.useDeepCapsuleMode;
      if (papers[i].isVisible && !delegatedToEdge) {
        starts.push(DesktopShell.startPaper(this.context, papers[i].id));
      }
    }
    const results: boolean[] = await Promise.all(starts);
    let paperStarted: boolean = false;
    for (let i: number = 0; i < results.length; i++) {
      paperStarted = paperStarted || results[i];
    }
    const capsuleReachable: boolean = await DesktopShell.syncCapsules(this.context);

    if (!statusInstalled && !paperStarted && !capsuleReachable) {
      this.showRecovery('状态栏入口和纸张窗口均未能启动。');
      return;
    }

    if (statusInstalled && !residentStarted) {
      await this.cleanupFailedResident();
      if (!paperStarted && !capsuleReachable) {
        this.showRecovery('状态栏入口启动失败，且没有可用的纸片窗口。');
        return;
      }
    }

    await this.hideRuntimeHost();
  }

  private requestRuntimeHide(): void {
    if (this.recoveryVisible) {
      return;
    }
    this.hidePending = true;
    if (this.hideRunning) {
      return;
    }
    this.hideRunning = true;
    this.runRuntimeHideLoop().then((): void => {
      this.hideRunning = false;
      if (this.hidePending && !this.recoveryVisible) {
        this.requestRuntimeHide();
      }
    }).catch((error: Error): void => {
      this.hideRunning = false;
      console.warn('hide runtime host loop failed: ' + error.message);
      if (this.hidePending && !this.recoveryVisible) {
        this.requestRuntimeHide();
      }
    });
  }

  private async runRuntimeHideLoop(): Promise<void> {
    while (this.hidePending && !this.recoveryVisible) {
      this.hidePending = false;
      await this.hideRuntimeHost();
    }
  }

  private async hideRuntimeHost(): Promise<void> {
    this.applyHiddenHostStyle();
    try {
      await this.context.hideAbility();
    } catch (error) {
      console.warn('hide runtime host failed: ' + String(error));
    }
  }

  private async cleanupFailedResident(): Promise<void> {
    const removed: boolean = await TrayService.remove(this.context);
    AppStorage.setOrCreate<string>('statusBarStatus', removed ?
      'resident error: inactive item removed' : 'resident error: unable to remove inactive item');
  }

  private async startResidentWithRetry(): Promise<boolean> {
    for (let attempt: number = 0; attempt < 3; attempt++) {
      if (await DesktopShell.startResident(this.context)) {
        return true;
      }
      if (attempt < 2) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, 240 * (attempt + 1));
        });
      }
    }
    return false;
  }

  private applyHiddenHostStyle(): void {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.error('hide entry decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.error('hide entry title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.error('clear entry background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.error('clear entry container failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.error('disable entry shadow failed: ' + error.message);
    });
    if (!this.recoveryVisible) {
      win.setWindowTouchable(false).catch((error: BusinessError): void => {
        console.error('disable entry touch failed: ' + error.message);
      });
      win.setWindowFocusable(false).catch((error: BusinessError): void => {
        console.error('disable entry focus failed: ' + error.message);
      });
    }
  }

  private showRecovery(reason: string): void {
    this.recoveryVisible = true;
    this.hidePending = false;
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
