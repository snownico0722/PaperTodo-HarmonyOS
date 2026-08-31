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
  createCapsuleMetrics,
  CapsuleMetrics,
  edgeCapsuleHiddenX,
  edgeCapsuleY
} from '../common/CapsuleGeometry';
import {
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  AppState,
  PaperData
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import {
  clampLogicalRect,
  createDisplayGeometry,
  DisplayGeometry,
  LogicalRect,
  pxToVp,
  vpToPx
} from '../common/WindowGeometry';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperAbility';

interface PaperLocalStorageData {
  paperId: string;
  windowWidthVp: number;
  windowHeightVp: number;
}

export default class PaperAbility extends UIAbility {
  private paperId: string = '';
  private storage: LocalStorage = new LocalStorage();
  private mainWindow: window.Window | null = null;
  private rectChangeCallback: ((data: window.RectChangeOptions) => void) | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    const storageData: PaperLocalStorageData = {
      paperId: this.paperId,
      windowWidthVp: paper !== null ? paper.expandedWidth : 320,
      windowHeightVp: paper !== null ? paper.expandedHeight : 360
    };
    this.storage = new LocalStorage(storageData);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const nextId: string = this.readPaperId(want);
    if (nextId.length > 0 && nextId !== this.paperId) {
      hilog.warn(DOMAIN, TAG, 'specified instance received mismatched paperId: %{public}s', nextId);
      return;
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
    this.raisePaperWindow();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.prepareMainWindow(windowStage).then((): void => {
      windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
        if (err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'Failed to load Paper page: %{public}s', JSON.stringify(err));
        }
      });
    }).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'prepare Paper window failed: %{public}s', error.message);
      windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
        if (err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'Failed to load Paper page after fallback: %{public}s', JSON.stringify(err));
        }
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.unregisterWindowRectListener();
    if (this.paperId.length > 0) {
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, false);
      AppStorage.delete('paperWindow:' + this.paperId);
    }
    this.mainWindow = null;
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
    if (this.mainWindow !== null) {
      this.applyStoredGeometry(this.mainWindow).catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'reapply geometry failed: %{public}s', error.message);
      });
    }
  }

  private async prepareMainWindow(windowStage: window.WindowStage): Promise<void> {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      await this.context.terminateSelf();
      return;
    }

    const mainWindow: window.Window = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;
    AppStorage.setOrCreate<window.Window>('paperWindow:' + this.paperId, mainWindow);
    AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, true);

    try {
      mainWindow.setWindowDecorVisible(false);
      mainWindow.setWindowTitleButtonVisible(false, false, false);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'configure decor failed: %{public}s', String(error));
    }

    await this.applyStoredGeometry(mainWindow);
    try {
      await mainWindow.setWindowTopmost(paper.alwaysOnTop);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}s', String(error));
    }
    this.registerWindowRectListener(mainWindow);
  }

  private async applyStoredGeometry(mainWindow: window.Window): Promise<void> {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      return;
    }

    const screen: display.Display = display.getDefaultDisplaySync();
    const displayGeometry: DisplayGeometry = createDisplayGeometry(
      screen.width,
      screen.height,
      screen.densityPixels
    );
    const logicalRect: LogicalRect = clampLogicalRect(
      paper.expandedX,
      paper.expandedY,
      paper.expandedWidth,
      paper.expandedHeight,
      PAPER_MIN_WIDTH,
      PAPER_MIN_HEIGHT,
      displayGeometry
    );
    paper.expandedX = logicalRect.x;
    paper.expandedY = logicalRect.y;
    paper.expandedWidth = logicalRect.width;
    paper.expandedHeight = logicalRect.height;

    let widthPx: number = vpToPx(logicalRect.width, displayGeometry.density);
    let heightPx: number = vpToPx(logicalRect.height, displayGeometry.density);
    let xPx: number = vpToPx(logicalRect.x, displayGeometry.density);
    let yPx: number = vpToPx(logicalRect.y, displayGeometry.density);

    const state: AppState = PaperStore.loadState();
    if (paper.isCollapsed && state.useCapsuleMode) {
      const metrics: CapsuleMetrics = createCapsuleMetrics(
        screen.width,
        screen.height,
        screen.densityPixels,
        state.capsuleGap
      );
      widthPx = metrics.widthPx;
      heightPx = metrics.heightPx;
      if (state.useDeepCapsuleMode) {
        const index: number = PaperStore.getCollapsedIndex(paper.id);
        xPx = edgeCapsuleHiddenX(metrics);
        yPx = edgeCapsuleY(index, metrics);
      } else {
        paper.capsuleX = this.clamp(paper.capsuleX, 0, Math.max(0, displayGeometry.screenWidthVp - 108));
        paper.capsuleY = this.clamp(paper.capsuleY, 0, Math.max(0, displayGeometry.screenHeightVp - 46));
        xPx = vpToPx(paper.capsuleX, displayGeometry.density);
        yPx = vpToPx(paper.capsuleY, displayGeometry.density);
      }
    }

    PaperStore.updatePaper(paper, false);
    this.storage.setOrCreate<number>('windowWidthVp', logicalRect.width);
    this.storage.setOrCreate<number>('windowHeightVp', logicalRect.height);

    try {
      await mainWindow.resize(Math.max(1, Math.round(widthPx)), Math.max(1, Math.round(heightPx)));
      await mainWindow.moveWindowTo(Math.max(0, Math.round(xPx)), Math.max(0, Math.round(yPx)));
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'apply window geometry failed: %{public}s', String(error));
    }
  }

  private registerWindowRectListener(mainWindow: window.Window): void {
    this.unregisterWindowRectListener();
    this.rectChangeCallback = (data: window.RectChangeOptions): void => {
      const paper: PaperData | null = PaperStore.getPaper(this.paperId);
      if (paper === null || paper.isCollapsed) {
        return;
      }
      try {
        const screen: display.Display = display.getDefaultDisplaySync();
        const density: number = screen.densityPixels > 0 ? screen.densityPixels : 1;
        const widthVp: number = pxToVp(data.rect.width, density);
        const heightVp: number = pxToVp(data.rect.height, density);
        paper.expandedX = Math.max(0, pxToVp(data.rect.left, density));
        paper.expandedY = Math.max(0, pxToVp(data.rect.top, density));
        paper.expandedWidth = Math.max(PAPER_MIN_WIDTH, widthVp);
        paper.expandedHeight = Math.max(PAPER_MIN_HEIGHT, heightVp);
        this.storage.setOrCreate<number>('windowWidthVp', paper.expandedWidth);
        this.storage.setOrCreate<number>('windowHeightVp', paper.expandedHeight);
        PaperStore.updatePaper(paper, false);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'windowRectChange handling failed: %{public}s', String(error));
      }
    };

    try {
      mainWindow.on('windowRectChange', this.rectChangeCallback);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register windowRectChange failed: %{public}s', String(error));
      this.rectChangeCallback = null;
    }
  }

  private unregisterWindowRectListener(): void {
    if (this.mainWindow === null || this.rectChangeCallback === null) {
      return;
    }
    try {
      this.mainWindow.off('windowRectChange', this.rectChangeCallback);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'unregister windowRectChange failed: %{public}s', String(error));
    }
    this.rectChangeCallback = null;
  }

  private raisePaperWindow(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.showWindow().catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'show paper window failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'show paper window threw: %{public}s', String(error));
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
