import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
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
  private mainWindow: window.Window | null = null;
  private statusBarReady: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    this.registerStatusBarEvents();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Explicitly launching PaperTodo from the launcher opens the full manager.
    this.showManagerWindow();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Window stage created');
    try {
      this.mainWindow = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'get manager window failed: %{public}s', String(error));
    }

    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.bootstrapDesktop().catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'desktop bootstrap failed: %{public}s', error.message);
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.mainWindow = null;
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async bootstrapDesktop(): Promise<void> {
    this.statusBarReady = await this.ensureStatusBar();
    await this.restoreVisiblePapers();

    // The manager is fallback UI, not PaperTodo's normal resident surface.
    // Once the system status-bar entry exists, keep the large manager minimized
    // even when there are currently zero visible papers.
    if (deviceInfo.deviceType === '2in1' && this.statusBarReady) {
      await this.minimizeManagerWindow();
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
      hilog.warn(DOMAIN, TAG, 'addToStatusBar failed, keep manager fallback: %{public}s', String(error));
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
    emitter.on(openManager, (): void => this.showManagerWindow());
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

  private async minimizeManagerWindow(): Promise<void> {
    if (this.mainWindow === null) {
      return;
    }
    try {
      await this.mainWindow.minimize();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'minimize manager failed: %{public}s', String(error));
    }
  }

  private showManagerWindow(): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      this.mainWindow.showWindow().catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'show manager window failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'show manager window threw: %{public}s', String(error));
    }
  }
}
