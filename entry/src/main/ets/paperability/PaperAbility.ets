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
  CAPSULE_CLOSE_WIDTH,
  CAPSULE_MIN_WIDTH,
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
  private mainWindow: window.Window | null = null;
  private readonly windowEventCallback: (event: window.WindowEventType) => void =
    (event: window.WindowEventType): void => {
      const active: boolean = event === window.WindowEventType.WINDOW_ACTIVE ||
        event === window.WindowEventType.WINDOW_SHOWN;
      if (!active && event !== window.WindowEventType.WINDOW_INACTIVE &&
        event !== window.WindowEventType.WINDOW_HIDDEN) {
        return;
      }
      AppStorage.setOrCreate<string>('paperWindowEventPaperId', this.paperId);
      AppStorage.setOrCreate<boolean>('paperWindowEventActive', active);
      const revision: number = AppStorage.get<number>('paperWindowEventRevision') ?? 0;
      AppStorage.setOrCreate<number>('paperWindowEventRevision', revision + 1);
    };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    this.applyFormCommand(this.readCommand(want));
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
      this.terminateAbility();
      return;
    }
    if (command === 'delete') {
      PaperStore.deletePaper(this.paperId);
      PaperStore.flushNow();
      this.terminateAbility();
      return;
    }
    if (command === 'close') {
      PaperStore.flushNow();
      this.terminateAbility();
      return;
    }

    this.applyFormCommand(command);

    PaperStore.setPaperVisible(this.paperId, true);
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow !== null) {
      mainWindow.restore()
        .catch((_restoreError: BusinessError): Promise<void> => mainWindow.showWindow())
        .catch((error: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'restore paper window failed: %{public}s', error.message);
        });
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load Paper page: %{public}s', JSON.stringify(err));
        return;
      }
      this.configureMainWindow(windowStage).catch((error: Error): void => {
        hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', error.message);
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    if (this.mainWindow !== null) {
      try {
        this.mainWindow.off('windowEvent', this.windowEventCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister window event failed: %{public}s', String(error));
      }
      this.mainWindow = null;
    }
    if (this.paperId.length > 0) {
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, false);
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async configureMainWindow(windowStage: window.WindowStage): Promise<void> {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      this.terminateAbility();
      return;
    }

    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      try {
        mainWindow.on('windowEvent', this.windowEventCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'register window event failed: %{public}s', String(error));
      }
      const uiContext: UIContext = mainWindow.getUIContext();
      mainWindow.setWindowBackgroundColor('#00000000');
      AppStorage.setOrCreate<window.Window>('paperWindow:' + this.paperId, mainWindow);
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, true);

      const screen: display.Display = display.getDefaultDisplaySync();
      const availableWidth: number = screen.availableWidth > 0 ? screen.availableWidth : screen.width;
      const availableHeight: number = screen.availableHeight > 0 ? screen.availableHeight : screen.height;
      const screenWidth: number = uiContext.px2vp(availableWidth);
      const screenHeight: number = uiContext.px2vp(availableHeight);
      const state: AppState = PaperStore.loadState();
      paper.expandedWidth = Math.min(screenWidth, Math.max(PAPER_MIN_WIDTH, paper.expandedWidth));
      paper.expandedHeight = Math.min(screenHeight, Math.max(PAPER_MIN_HEIGHT, paper.expandedHeight));
      paper.expandedX = this.clamp(paper.expandedX, 0, Math.max(0, screenWidth - paper.expandedWidth));
      paper.expandedY = this.clamp(paper.expandedY, 0, Math.max(0, screenHeight - paper.expandedHeight));

      let width: number = paper.expandedWidth;
      let height: number = paper.expandedHeight;
      let x: number = paper.expandedX;
      let y: number = paper.expandedY;

      if (paper.isCollapsed && state.useCapsuleMode) {
        width = paper.capsuleWidth;
        height = CAPSULE_HEIGHT;
        if (state.useDeepCapsuleMode) {
          const index: number = PaperStore.getCollapsedIndex(paper.id);
          paper.capsuleX = Math.max(0, screenWidth - paper.capsuleWidth);
          paper.capsuleY = this.clamp(20 + index * (CAPSULE_HEIGHT + state.capsuleGap), 0,
            Math.max(0, screenHeight - CAPSULE_HEIGHT));
          x = Math.min(screenWidth, paper.capsuleX + Math.min(paper.capsuleWidth, CAPSULE_CLOSE_WIDTH));
          y = paper.capsuleY;
        } else {
          paper.capsuleX = this.clamp(paper.capsuleX, 0, Math.max(0, screenWidth - paper.capsuleWidth));
          paper.capsuleY = this.clamp(paper.capsuleY, 0, Math.max(0, screenHeight - CAPSULE_HEIGHT));
          x = paper.capsuleX;
          y = paper.capsuleY;
        }
      }

      PaperStore.updatePaper(paper, false);
      try {
        await mainWindow.setWindowLimits({
          minWidth: Math.round(uiContext.vp2px(CAPSULE_MIN_WIDTH)),
          minHeight: Math.round(uiContext.vp2px(CAPSULE_HEIGHT)),
          maxWidth: availableWidth,
          maxHeight: availableHeight
        }, true);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'setWindowLimits failed: %{public}s', error.message);
      }
      await mainWindow.resize(Math.round(uiContext.vp2px(width)), Math.round(uiContext.vp2px(height)));
      await mainWindow.moveWindowTo(Math.round(uiContext.vp2px(x)), Math.round(uiContext.vp2px(y)));
      mainWindow.setWindowDecorVisible(false);
      mainWindow.setWindowTitleButtonVisible(false, false, false);
      try {
        await mainWindow.setWindowTopmost(paper.alwaysOnTop || (paper.isCollapsed && state.useDeepCapsuleMode));
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}s', error.message);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', String(error));
    }
  }

  private terminateAbility(): void {
    this.context.terminateSelf().catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'terminateSelf failed: %{public}s', error.message);
    });
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(value, maxValue));
  }

  private applyFormCommand(command: string): void {
    if (this.paperId.length === 0) {
      return;
    }
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      return;
    }
    const state: AppState = PaperStore.loadState();
    if (command === 'expand') {
      PaperStore.setPaperCollapsed(this.paperId, false);
    } else if (command === 'collapse' && state.useCapsuleMode) {
      PaperStore.setPaperCollapsed(this.paperId, true);
    } else if (command === 'toggle' && state.useCapsuleMode) {
      PaperStore.setPaperCollapsed(this.paperId, !paper.isCollapsed);
    }
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
