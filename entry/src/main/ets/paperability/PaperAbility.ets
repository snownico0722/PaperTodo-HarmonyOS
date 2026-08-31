import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import {
  CAPSULE_HEIGHT,
  CAPSULE_WIDTH,
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  AppState,
  PaperData
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperAbility';

interface PaperLocalStorageData {
  paperId: string;
}

export default class PaperAbility extends UIAbility {
  private paperId: string = '';
  private storage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    const storageData: PaperLocalStorageData = { paperId: this.paperId };
    this.storage = new LocalStorage(storageData);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const nextId: string = this.readPaperId(want);
    if (nextId.length > 0) {
      this.paperId = nextId;
    }

    const command: string = this.readCommand(want);
    if (command === 'hide') {
      PaperStore.setPaperVisible(this.paperId, false);
      PaperStore.flushNow();
      this.context.terminateSelf();
      return;
    }
    if (command === 'delete') {
      PaperStore.deletePaper(this.paperId);
      PaperStore.flushNow();
      this.context.terminateSelf();
      return;
    }
    if (command === 'close') {
      PaperStore.flushNow();
      this.context.terminateSelf();
      return;
    }

    PaperStore.setPaperVisible(this.paperId, true);
    this.context.showAbility().catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'showAbility failed: %{public}s', error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load Paper page: %{public}s', JSON.stringify(err));
        return;
      }
      this.configureMainWindow(windowStage);
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    if (this.paperId.length > 0) {
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, false);
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private configureMainWindow(windowStage: window.WindowStage): void {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      this.context.terminateSelf();
      return;
    }

    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      AppStorage.setOrCreate<window.Window>('paperWindow:' + this.paperId, mainWindow);
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, true);

      const screen: display.Display = display.getDefaultDisplaySync();
      const state: AppState = PaperStore.loadState();
      paper.expandedWidth = Math.min(screen.width, Math.max(PAPER_MIN_WIDTH, paper.expandedWidth));
      paper.expandedHeight = Math.min(screen.height, Math.max(PAPER_MIN_HEIGHT, paper.expandedHeight));
      paper.expandedX = this.clamp(paper.expandedX, 0, Math.max(0, screen.width - paper.expandedWidth));
      paper.expandedY = this.clamp(paper.expandedY, 0, Math.max(0, screen.height - paper.expandedHeight));

      let width: number = paper.expandedWidth;
      let height: number = paper.expandedHeight;
      let x: number = paper.expandedX;
      let y: number = paper.expandedY;

      if (paper.isCollapsed && state.useCapsuleMode) {
        width = CAPSULE_WIDTH;
        height = CAPSULE_HEIGHT;
        if (state.useDeepCapsuleMode) {
          const index: number = PaperStore.getCollapsedIndex(paper.id);
          paper.capsuleX = Math.max(0, screen.width - CAPSULE_WIDTH);
          paper.capsuleY = 20 + index * (CAPSULE_HEIGHT + state.capsuleGap);
          x = paper.capsuleX + Math.round(CAPSULE_WIDTH * 0.45);
          y = paper.capsuleY;
        } else {
          paper.capsuleX = this.clamp(paper.capsuleX, 0, Math.max(0, screen.width - CAPSULE_WIDTH));
          paper.capsuleY = this.clamp(paper.capsuleY, 0, Math.max(0, screen.height - CAPSULE_HEIGHT));
          x = paper.capsuleX;
          y = paper.capsuleY;
        }
      }

      PaperStore.updatePaper(paper, false);
      mainWindow.resize(Math.round(width), Math.round(height));
      mainWindow.moveWindowTo(Math.round(x), Math.round(y));
      mainWindow.setWindowDecorVisible(false);
      mainWindow.setWindowTitleButtonVisible(false, false, false);
      mainWindow.setWindowTopmost(paper.alwaysOnTop).catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', String(error));
    }
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(value, maxValue));
  }

  private readPaperId(want: Want): string {
    if (!want.parameters) {
      return '';
    }
    const raw: Object | undefined = want.parameters.paperId;
    if (raw === undefined || raw === null) {
      return '';
    }
    return String(raw);
  }

  private readCommand(want: Want): string {
    if (!want.parameters) {
      return 'show';
    }
    const raw: Object | undefined = want.parameters.paperCommand;
    if (raw === undefined || raw === null) {
      return 'show';
    }
    return String(raw);
  }
}
