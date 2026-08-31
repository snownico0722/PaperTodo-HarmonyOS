import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { statusBarManager } from '@kit.StatusBarExtensionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import {
  STATUS_EVENT_HIDE_ALL,
  STATUS_EVENT_NEW_NOTE,
  STATUS_EVENT_NEW_TODO,
  STATUS_EVENT_OPEN_MANAGER,
  STATUS_EVENT_SHOW_ALL
} from '../common/StatusBarEvents';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperTodo';

export default class EntryAbility extends UIAbility {
  private hostWindow: window.Window | null = null;
  private statusBarReady: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    this.registerStatusBarEvents();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 桌面图标只负责唤醒 PaperTodo，不再把管理中心当成主界面。
    this.showAllPapers();
    this.ensureStatusBar().catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'refresh status bar failed: %{public}s', error.message);
    });
    this.minimizeHostWindow().catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'minimize host after relaunch failed: %{public}s', error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'background host stage created');
    try {
      this.hostWindow = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'get host window failed: %{public}s', String(error));
    }

    windowStage.loadContent('pages/Host', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load host page. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.configureHostWindow().then((): void => {
        this.bootstrapDesktop().catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'desktop bootstrap failed: %{public}s', error.message);
        });
      }).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'configure host failed: %{public}s', error.message);
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.hostWindow = null;
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async configureHostWindow(): Promise<void> {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowDecorHeight(0);
      win.setWindowBackgroundColor('#00000000');
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'configure transparent host failed: %{public}s', String(error));
    }
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disable host shadow failed: %{public}s', String(error));
    }
  }

  private async bootstrapDesktop(): Promise<void> {
    this.statusBarReady = await this.ensureStatusBar();
    await this.restoreVisiblePapers();
    await this.minimizeHostWindow();

    // 仅当系统状态栏注册失败时，才退回传统管理窗口，避免应用完全不可操作。
    if (deviceInfo.deviceType === '2in1' && !this.statusBarReady) {
      this.openManager();
    }
  }

  private async ensureStatusBar(): Promise<boolean> {
    if (deviceInfo.deviceType !== '2in1') {
      return false;
    }
    try {
      const whiteData: Uint8Array = this.context.resourceManager.getRawFileContentSync('statusbar_white.svg');
      const blackData: Uint8Array = this.context.resourceManager.getRawFileContentSync('statusbar_black.svg');
      const whiteSource: image.ImageSource = image.createImageSource(whiteData.buffer);
      const blackSource: image.ImageSource = image.createImageSource(blackData.buffer);
      const whitePixelMap: image.PixelMap = await whiteSource.createPixelMap();
      const blackPixelMap: image.PixelMap = await blackSource.createPixelMap();

      const icons: statusBarManager.StatusBarIcon = {
        white: whitePixelMap,
        black: blackPixelMap
      };
      const quickOperation: statusBarManager.QuickOperation = {
        abilityName: 'PaperStatusBarAbility',
        title: 'PaperTodo',
        height: 176,
        moduleName: 'entry'
      };
      const item: statusBarManager.StatusBarItem = {
        icons: icons,
        quickOperation: quickOperation
      };
      statusBarManager.addToStatusBar(this.context, item);
      hilog.info(DOMAIN, TAG, '%{public}s', 'PaperTodo added to system status bar');
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'addToStatusBar failed: %{public}s', String(error));
      return false;
    }
  }

  private registerStatusBarEvents(): void {
    const newTodo: emitter.InnerEvent = { eventId: STATUS_EVENT_NEW_TODO };
    const newNote: emitter.InnerEvent = { eventId: STATUS_EVENT_NEW_NOTE };
    const showAll: emitter.InnerEvent = { eventId: STATUS_EVENT_SHOW_ALL };
    const hideAll: emitter.InnerEvent = { eventId: STATUS_EVENT_HIDE_ALL };
    const openManager: emitter.InnerEvent = { eventId: STATUS_EVENT_OPEN_MANAGER };

    emitter.on(newTodo, (): void => this.createPaper(PAPER_TYPE_TODO));
    emitter.on(newNote, (): void => this.createPaper(PAPER_TYPE_NOTE));
    emitter.on(showAll, (): void => this.showAllPapers());
    emitter.on(hideAll, (): void => this.hideAllPapers());
    emitter.on(openManager, (): void => this.openManager());
  }

  private createPaper(type: string): void {
    const paper: PaperData | null = PaperStore.createPaper(type);
    if (paper !== null) {
      this.startPaper(paper.id).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'status-bar create paper failed: %{public}s', error.message);
      });
    }
  }

  private showAllPapers(): void {
    const papers: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, true);
      this.startPaper(papers[i].id).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'show paper failed: %{public}s', error.message);
      });
    }
  }

  private hideAllPapers(): void {
    const papers: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, false);
      const want: Want = {
        bundleName: 'com.papertodo.app',
        moduleName: 'entry',
        abilityName: 'PaperAbility',
        parameters: {
          paperId: papers[i].id,
          paperCommand: 'hide'
        }
      };
      this.context.startAbility(want).catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'hide paper command failed: %{public}s', error.message);
      });
    }
  }

  private async restoreVisiblePapers(): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const starts: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].isVisible) {
        starts.push(this.startPaper(papers[i].id));
      }
    }
    if (starts.length > 0) {
      await Promise.all(starts);
    }
  }

  private async startPaper(paperId: string): Promise<boolean> {
    const want: Want = {
      bundleName: 'com.papertodo.app',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId,
        paperCommand: 'show'
      }
    };
    try {
      await this.context.startAbility(want);
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'start PaperAbility failed: %{public}s', String(error));
      return false;
    }
  }

  private openManager(): void {
    const want: Want = {
      bundleName: 'com.papertodo.app',
      moduleName: 'entry',
      abilityName: 'ManagerAbility'
    };
    this.context.startAbility(want).catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'open manager failed: %{public}s', error.message);
    });
  }

  private async minimizeHostWindow(): Promise<void> {
    if (this.hostWindow === null) {
      return;
    }
    try {
      await this.hostWindow.minimize();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'minimize host failed: %{public}s', String(error));
    }
  }
}
