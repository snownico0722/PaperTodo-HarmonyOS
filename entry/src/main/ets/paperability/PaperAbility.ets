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
  CAPSULE_MIN_WIDTH,
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  AppState,
  PaperData
} from '../common/Models';
import {
  DesktopShell,
  PAPER_COMMAND_SHOW
} from '../common/DesktopShell';
import { PaperStore } from '../common/PaperStore';
import { CapsuleRuntime } from '../common/CapsuleRuntime';
import { PAPER_ACTION_HIDE, resolveSystemCloseAction } from '../common/PaperInteractionPolicy';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperAbility';

interface PaperLocalStorageData {
  paperId: string;
}

interface AvailableAreaPx {
  left: number;
  top: number;
  width: number;
  height: number;
}

export default class PaperAbility extends UIAbility {
  private paperId: string = '';
  private contentLoaded: boolean = false;
  private delegatingToEdge: boolean = false;
  private storage: LocalStorage = new LocalStorage();
  private mainWindow: window.Window | null = null;
  private windowStage: window.WindowStage | null = null;
  private openToken: string = '';
  private windowEventsRegistered: boolean = false;
  private closeEventRegistered: boolean = false;
  private stageCloseEventRegistered: boolean = false;
  private rectChangeEventRegistered: boolean = false;
  private statusChangeEventRegistered: boolean = false;
  private systemCloseInProgress: boolean = false;
  private restoringFromMinimize: boolean = false;
  private initialInteractionLocked: boolean = false;
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
  private readonly windowWillCloseCallback: () => Promise<boolean> = (): Promise<boolean> => {
    this.handleSystemCloseRequest();
    return Promise.resolve(true);
  };
  private readonly windowStageCloseCallback: () => boolean = (): boolean => {
    this.handleSystemCloseRequest();
    return true;
  };
  private readonly windowRectChangeCallback: (options: window.RectChangeOptions) => void =
    (options: window.RectChangeOptions): void => {
      if (options.reason !== window.RectChangeReason.DRAG_END || this.mainWindow === null) {
        return;
      }
      const paper: PaperData | null = PaperStore.getPaper(this.paperId);
      if (paper === null || paper.isCollapsed) {
        return;
      }
      try {
        const uiContext: UIContext = this.mainWindow.getUIContext();
        paper.expandedX = uiContext.px2vp(options.rect.left);
        paper.expandedY = uiContext.px2vp(options.rect.top);
        paper.expandedWidth = uiContext.px2vp(options.rect.width);
        paper.expandedHeight = uiContext.px2vp(options.rect.height);
        PaperStore.updatePaper(paper, false);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'persist native drag failed: %{public}s', String(error));
      }
    };
  private readonly windowStatusDidChangeCallback: (status: window.WindowStatusType) => void =
    (status: window.WindowStatusType): void => {
      if (status !== window.WindowStatusType.MINIMIZE || this.restoringFromMinimize) {
        return;
      }
      const paper: PaperData | null = PaperStore.getPaper(this.paperId);
      if (paper === null || !paper.isVisible) {
        return;
      }
      this.restoringFromMinimize = true;
      setTimeout((): void => {
        this.showAndConfigure().catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'restore minimized paper failed: %{public}s', error.message);
        }).finally((): void => {
          this.restoringFromMinimize = false;
        });
      }, 0);
    };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    this.openToken = this.createOpenToken();
    this.applyFormCommand(this.readCommand(want));
    const storageData: PaperLocalStorageData = { paperId: this.paperId };
    this.storage = new LocalStorage(storageData);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleNewWant(want).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'handle paper command failed: %{public}s', error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    try {
      this.mainWindow = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'get paper main window failed: %{public}s', String(error));
      this.terminateAbility();
      return;
    }
    this.applyWindowStyle();
    this.registerWindowEvents(windowStage);

    if (this.shouldDelegateToEdge()) {
      this.delegateCollapsedPaperToEdge().catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'delegate collapsed paper failed: %{public}s', error.message);
      });
      return;
    }

    this.markWindowOpen();
    this.prepareInitialWindowAndLoadContent(windowStage).catch((error: Error): void => {
      hilog.error(DOMAIN, TAG, 'prepare initial paper window failed: %{public}s', error.message);
      this.loadPaperContent(windowStage);
    });
  }

  private async prepareInitialWindowAndLoadContent(windowStage: window.WindowStage): Promise<void> {
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      return;
    }
    await this.setInitialWindowInteraction(false);
    try {
      await mainWindow.setWindowShadowEnabled(false);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disable initial paper shadow failed: %{public}s', String(error));
    }
    await this.applyPaperGeometry(mainWindow, true);
    this.applyWindowStyle();
    if (this.windowStage !== windowStage || this.mainWindow !== mainWindow) {
      return;
    }
    this.loadPaperContent(windowStage);
  }

  private loadPaperContent(windowStage: window.WindowStage): void {
    if (this.windowStage !== windowStage || this.mainWindow === null) {
      return;
    }
    windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load Paper page: %{public}s', JSON.stringify(err));
        this.clearOpenMarkerIfOwned();
        this.terminateAbility();
        return;
      }
      this.contentLoaded = true;
      this.configureMainWindow()
        .then(async (): Promise<boolean> => {
          if (!this.shouldDelegateToEdge()) {
            await this.setInitialWindowInteraction(true);
          }
          return DesktopShell.syncCapsules(this.context);
        })
        .catch((error: Error): void => {
          hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', error.message);
          if (!this.shouldDelegateToEdge()) {
            this.setInitialWindowInteraction(true).catch((restoreError: Error): void => {
              hilog.warn(DOMAIN, TAG, 'restore paper interaction failed: %{public}s', restoreError.message);
            });
          }
        });
    });
  }

  onForeground(): void {
    this.applyWindowStyle();
    if (this.shouldDelegateToEdge()) {
      this.delegateCollapsedPaperToEdge().catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'delegate foreground paper failed: %{public}s', error.message);
      });
    }
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.unregisterWindowEvents();
    this.mainWindow = null;
    this.windowStage = null;
    this.clearOpenMarkerIfOwned();
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async configureMainWindow(): Promise<void> {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      this.clearOpenMarkerIfOwned();
      this.terminateAbility();
      return;
    }

    const state: AppState = PaperStore.loadState();
    if (paper.isCollapsed && state.useCapsuleMode && state.useDeepCapsuleMode) {
      await this.delegateCollapsedPaperToEdge();
      return;
    }

    try {
      const mainWindow: window.Window | null = this.mainWindow;
      if (mainWindow === null) {
        return;
      }
      await this.applyPaperGeometry(mainWindow, true);
      this.applyWindowStyle();
      try {
        await mainWindow.setWindowTopmost(paper.alwaysOnTop || (paper.isCollapsed && state.useCapsuleMode));
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}s', String(error));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', String(error));
    }
  }

  private async handleNewWant(want: Want): Promise<void> {
    this.systemCloseInProgress = false;
    const nextId: string = this.readPaperId(want);
    if (nextId.length > 0 && nextId !== this.paperId) {
      this.clearOpenMarkerIfOwned();
      this.paperId = nextId;
      this.openToken = this.createOpenToken();
      const storageData: PaperLocalStorageData = { paperId: this.paperId };
      this.storage = new LocalStorage(storageData);
    }

    const command: string = this.readCommand(want);
    if (command === 'hide') {
      await this.hideAndTerminate();
      return;
    }
    if (command === 'delete') {
      await this.deleteAndTerminate();
      return;
    }
    if (command === 'close') {
      PaperStore.flushNow();
      this.clearOpenMarkerIfOwned();
      this.terminateAbility();
      return;
    }

    this.applyFormCommand(command);
    PaperStore.setPaperVisible(this.paperId, true);
    if (this.shouldDelegateToEdge()) {
      await this.delegateCollapsedPaperToEdge();
      return;
    }

    this.markWindowOpen();
    await this.showAndConfigure();
    await DesktopShell.syncCapsules(this.context);
  }

  private async showAndConfigure(): Promise<void> {
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      return;
    }
    try {
      await mainWindow.restore();
    } catch (_restoreError) {
      try {
        await mainWindow.showWindow();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'show paper window failed: %{public}s', String(error));
        return;
      }
    }
    this.applyWindowStyle();
    await this.configureMainWindow();
    this.applyWindowStyle();
  }

  private shouldDelegateToEdge(): boolean {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      return false;
    }
    const state: AppState = PaperStore.loadState();
    return paper.isVisible && paper.isCollapsed && state.useCapsuleMode && state.useDeepCapsuleMode;
  }

  private async delegateCollapsedPaperToEdge(): Promise<void> {
    if (this.delegatingToEdge) {
      return;
    }
    this.delegatingToEdge = true;
    try {
      await DesktopShell.syncCapsules(this.context);
      if (CapsuleRuntime.isReady() && this.shouldDelegateToEdge()) {
        this.clearOpenMarkerIfOwned();
        this.terminateAbility();
        return;
      }
      // The host failed or eligibility changed while it was starting. Keep the
      // existing paper, or load its normal content on a cold-start delegation.
      PaperStore.setPaperCollapsed(this.paperId, false);
      const paper: PaperData | null = PaperStore.getPaper(this.paperId);
      if (paper === null || !paper.isVisible) {
        this.terminateAbility();
        return;
      }
      this.markWindowOpen();
      if (!this.contentLoaded && this.windowStage !== null) {
        this.loadPaperContent(this.windowStage);
      } else {
        await this.showAndConfigure();
        await this.setInitialWindowInteraction(true);
      }
    } finally {
      this.delegatingToEdge = false;
    }
  }

  private async hideAndTerminate(): Promise<void> {
    PaperStore.setPaperVisible(this.paperId, false);
    PaperStore.flushNow();
    this.clearOpenMarkerIfOwned();
    await DesktopShell.syncCapsules(this.context);
    this.terminateAbility();
  }

  private async deleteAndTerminate(): Promise<void> {
    const replacement: PaperData | null = PaperStore.deletePaper(this.paperId);
    PaperStore.flushNow();
    this.clearOpenMarkerIfOwned();
    if (replacement !== null) {
      await DesktopShell.startPaper(this.context, replacement.id, PAPER_COMMAND_SHOW);
    }
    await DesktopShell.syncCapsules(this.context);
    this.terminateAbility();
  }

  private handleSystemCloseRequest(): void {
    if (this.systemCloseInProgress) {
      return;
    }
    this.systemCloseInProgress = true;
    if (resolveSystemCloseAction() !== PAPER_ACTION_HIDE) {
      this.systemCloseInProgress = false;
      return;
    }
    AppStorage.setOrCreate<string>('paperSystemClosePaperId', this.paperId);
    const revision: number = AppStorage.get<number>('paperSystemCloseRevision') ?? 0;
    AppStorage.setOrCreate<number>('paperSystemCloseRevision', revision + 1);
    PaperStore.setPaperVisible(this.paperId, false);
    PaperStore.flushNow();
    this.clearOpenMarkerIfOwned();
    this.hideAndTerminate().catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'hide system-closed paper failed: %{public}s', error.message);
      this.terminateAbility();
    });
  }

  private applyWindowStyle(): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      return;
    }
    try {
      mainWindow.setWindowDecorVisible(false);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'hide paper decor failed: %{public}s', String(error));
    }
    try {
      mainWindow.setWindowTitleButtonVisible(false, false, false);
      mainWindow.setWindowTitleMoveEnabled(false);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'hide paper title controls failed: %{public}s', String(error));
    }
    try {
      mainWindow.setWindowBackgroundColor('#00000000');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'clear paper background failed: %{public}s', String(error));
    }
    try {
      mainWindow.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'clear paper container failed: %{public}s', String(error));
    }
    mainWindow.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'disable paper shadow failed: %{public}s', error.message);
    });
  }

  private registerWindowEvents(windowStage: window.WindowStage): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      return;
    }
    try {
      mainWindow.on('windowEvent', this.windowEventCallback);
      this.windowEventsRegistered = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register window event failed: %{public}s', String(error));
    }
    try {
      mainWindow.on('windowWillClose', this.windowWillCloseCallback);
      this.closeEventRegistered = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register close event failed: %{public}s', String(error));
    }
    try {
      mainWindow.on('windowRectChange', this.windowRectChangeCallback);
      this.rectChangeEventRegistered = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register window rect event failed: %{public}s', String(error));
    }
    try {
      mainWindow.on('windowStatusDidChange', this.windowStatusDidChangeCallback);
      this.statusChangeEventRegistered = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register window status event failed: %{public}s', String(error));
    }
    try {
      windowStage.on('windowStageClose', this.windowStageCloseCallback);
      this.stageCloseEventRegistered = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'register stage close event failed: %{public}s', String(error));
    }
  }

  private unregisterWindowEvents(): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow !== null && this.windowEventsRegistered) {
      try {
        mainWindow.off('windowEvent', this.windowEventCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister window event failed: %{public}s', String(error));
      }
      this.windowEventsRegistered = false;
    }
    if (mainWindow !== null && this.closeEventRegistered) {
      try {
        mainWindow.off('windowWillClose', this.windowWillCloseCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister close event failed: %{public}s', String(error));
      }
      this.closeEventRegistered = false;
    }
    if (mainWindow !== null && this.rectChangeEventRegistered) {
      try {
        mainWindow.off('windowRectChange', this.windowRectChangeCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister window rect event failed: %{public}s', String(error));
      }
      this.rectChangeEventRegistered = false;
    }
    if (mainWindow !== null && this.statusChangeEventRegistered) {
      try {
        mainWindow.off('windowStatusDidChange', this.windowStatusDidChangeCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister window status event failed: %{public}s', String(error));
      }
      this.statusChangeEventRegistered = false;
    }
    const stage: window.WindowStage | null = this.windowStage;
    if (stage !== null && this.stageCloseEventRegistered) {
      try {
        stage.off('windowStageClose', this.windowStageCloseCallback);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'unregister stage close event failed: %{public}s', String(error));
      }
      this.stageCloseEventRegistered = false;
    }
  }

  private markWindowOpen(): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (this.paperId.length === 0 || mainWindow === null) {
      return;
    }
    AppStorage.setOrCreate<string>('paperOpenToken:' + this.paperId, this.openToken);
    AppStorage.setOrCreate<window.Window>('paperWindow:' + this.paperId, mainWindow);
    AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, true);
    AppStorage.setOrCreate<boolean>('paperSystemCloseHides:' + this.paperId, true);
  }

  private clearOpenMarkerIfOwned(): void {
    if (this.paperId.length === 0 || this.openToken.length === 0) {
      return;
    }
    const activeToken: string | undefined = AppStorage.get<string>('paperOpenToken:' + this.paperId);
    if (activeToken === this.openToken) {
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, false);
    }
  }

  private createOpenToken(): string {
    return Date.now().toString(36) + '_' + Math.random().toString(36).substring(2);
  }

  private async readAvailableArea(screen: display.Display): Promise<AvailableAreaPx> {
    try {
      const area: display.Rect = await screen.getAvailableArea();
      if (area.width > 0 && area.height > 0) {
        return {
          left: area.left,
          top: area.top,
          width: area.width,
          height: area.height
        };
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'get available area failed: %{public}s', String(error));
    }
    return {
      left: 0,
      top: 0,
      width: screen.availableWidth > 0 ? screen.availableWidth : screen.width,
      height: screen.availableHeight > 0 ? screen.availableHeight : screen.height
    };
  }

  /**
   * The system creates a UIAbility window at its default size before ArkUI has
   * built the page.  Prepare the persisted paper geometry while the window is
   * transparent and non-interactive so that default window never becomes the
   * first visible frame.
   */
  private async applyPaperGeometry(mainWindow: window.Window, persistPaper: boolean): Promise<void> {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      return;
    }

    const uiContext: UIContext = mainWindow.getUIContext();
    const screen: display.Display = display.getDefaultDisplaySync();
    const area: AvailableAreaPx = await this.readAvailableArea(screen);
    if (area.width <= 0 || area.height <= 0) {
      return;
    }

    const availableWidthVp: number = uiContext.px2vp(area.width);
    const availableHeightVp: number = uiContext.px2vp(area.height);
    const state: AppState = PaperStore.loadState();
    const minExpandedWidth: number = Math.min(PAPER_MIN_WIDTH, availableWidthVp);
    const minExpandedHeight: number = Math.min(PAPER_MIN_HEIGHT, availableHeightVp);

    paper.expandedWidth = this.clamp(paper.expandedWidth, minExpandedWidth, availableWidthVp);
    paper.expandedHeight = this.clamp(paper.expandedHeight, minExpandedHeight, availableHeightVp);
    paper.expandedX = this.clamp(paper.expandedX, 0,
      Math.max(0, availableWidthVp - paper.expandedWidth));
    paper.expandedY = this.clamp(paper.expandedY, 0,
      Math.max(0, availableHeightVp - paper.expandedHeight));

    let widthVp: number = paper.expandedWidth;
    let heightVp: number = paper.expandedHeight;
    let xVp: number = paper.expandedX;
    let yVp: number = paper.expandedY;
    if (paper.isCollapsed && state.useCapsuleMode) {
      const minimumCapsuleWidth: number = Math.min(CAPSULE_MIN_WIDTH, availableWidthVp);
      paper.capsuleWidth = this.clamp(paper.capsuleWidth, minimumCapsuleWidth, availableWidthVp);
      paper.capsuleX = this.clamp(paper.capsuleX, 0,
        Math.max(0, availableWidthVp - paper.capsuleWidth));
      paper.capsuleY = this.clamp(paper.capsuleY, 0,
        Math.max(0, availableHeightVp - Math.min(CAPSULE_HEIGHT, availableHeightVp)));
      widthVp = paper.capsuleWidth;
      heightVp = Math.min(CAPSULE_HEIGHT, availableHeightVp);
      xVp = paper.capsuleX;
      yVp = paper.capsuleY;
    }

    if (persistPaper) {
      PaperStore.updatePaper(paper, false);
    }

    const minWidthPx: number = Math.min(Math.round(uiContext.vp2px(CAPSULE_MIN_WIDTH)), area.width);
    const minHeightPx: number = Math.min(Math.round(uiContext.vp2px(CAPSULE_HEIGHT)), area.height);
    const widthPx: number = Math.max(minWidthPx, Math.min(area.width, Math.round(uiContext.vp2px(widthVp))));
    const heightPx: number = Math.max(minHeightPx, Math.min(area.height, Math.round(uiContext.vp2px(heightVp))));
    try {
      await mainWindow.setWindowLimits({
        minWidth: minWidthPx,
        minHeight: minHeightPx,
        maxWidth: area.width,
        maxHeight: area.height
      }, true);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'set paper window limits failed: %{public}s', String(error));
    }
    await mainWindow.resize(widthPx, heightPx);
    await mainWindow.moveWindowTo(area.left + Math.round(uiContext.vp2px(xVp)),
      area.top + Math.round(uiContext.vp2px(yVp)));
  }

  private async setInitialWindowInteraction(enabled: boolean): Promise<void> {
    if (enabled && !this.initialInteractionLocked) {
      return;
    }
    if (!enabled && this.initialInteractionLocked) {
      return;
    }
    const mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      return;
    }
    try {
      await mainWindow.setWindowTouchable(enabled);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'set paper touchability failed: %{public}s', String(error));
    }
    try {
      await mainWindow.setWindowFocusable(enabled);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'set paper focusability failed: %{public}s', String(error));
    }
    this.initialInteractionLocked = !enabled;
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
