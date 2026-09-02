import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { normalizeCapsuleStartTopMargin } from '../common/CapsuleLayout';
import {
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  AppState,
  PaperData
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const INITIAL_MASTER_ROW_WIDTH: number = 96;
const INITIAL_INTERACTION_RESTORE_DELAY_MS: number = 16;
const CAPSULE_SUBWINDOW_NAME: string = 'PaperTodoCapsuleSubWindow';

export default class MasterCapsuleAbility extends UIAbility {
  private hostWindow: window.Window | null = null;
  private mainWindow: window.Window | null = null;
  private windowStage: window.WindowStage | null = null;
  private activeDisplay: display.Display | null = null;
  private closeRequested: boolean = false;
  private closeEventRegistered: boolean = false;
  private stageCloseEventRegistered: boolean = false;
  private initialInteractionLocked: boolean = false;
  private readonly windowWillCloseCallback: () => Promise<boolean> = (): Promise<boolean> => {
    if (this.closeRequested) {
      return Promise.resolve(false);
    }
    this.preserveCapsuleHost();
    return Promise.resolve(true);
  };
  private readonly windowStageCloseCallback: () => boolean = (): boolean => {
    if (this.closeRequested) {
      return false;
    }
    this.preserveCapsuleHost();
    return true;
  };
  private readonly instanceToken: string = 'capsule_host_' + Date.now().toString(36) + '_' +
    Math.floor(Math.random() * 0xFFFFFF).toString(36);
  private readonly availableAreaCallback: (area: display.Rect) => void = (_area: display.Rect): void => {
    this.notifyAvailableAreaChanged();
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.closeRequested = this.readCommand(want) === 'close';
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const command: string = this.readCommand(want);
    if (command === 'close' || !this.isEligible()) {
      this.closeRequested = true;
      this.terminateAbility();
      return;
    }
    this.closeRequested = false;
    this.showAndRestyle();
    this.notifyAvailableAreaChanged();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    if (this.closeRequested || !this.isEligible()) {
      this.clearHostRegistration();
      this.terminateAbility();
      return;
    }

    try {
      this.hostWindow = windowStage.getMainWindowSync();
    } catch (error) {
      console.error('get capsule ability host window failed: ' + String(error));
      this.terminateAbility();
      return;
    }
    AppStorage.setOrCreate<number>('capsuleAreaRevision',
      AppStorage.get<number>('capsuleAreaRevision') ?? 0);
    this.registerAvailableAreaListener();

    windowStage.loadContent('pages/Host', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load capsule ability host page failed: ' + error.message);
        this.terminateAbility();
        return;
      }
      this.configureHiddenHostWindow().then((): Promise<void> => {
        return this.createCapsuleSubWindow(windowStage);
      }).catch((reason: Error): void => {
        console.error('create capsule subwindow failed: ' + reason.message);
        this.terminateAbility();
      });
    });
  }

  onForeground(): void {
    this.configureHiddenHostWindow().catch((error: Error): void => {
      console.warn('re-hide capsule ability host failed: ' + error.message);
    });
    this.showAndRestyle();
    this.notifyAvailableAreaChanged();
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
    this.notifyAvailableAreaChanged();
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.unregisterCloseEvents();
    this.unregisterAvailableAreaListener();
    const capsuleWindow: window.Window | null = this.mainWindow;
    this.mainWindow = null;
    if (capsuleWindow !== null) {
      try {
        capsuleWindow.destroyWindow();
      } catch (error) {
        console.warn('destroy capsule subwindow failed: ' + String(error));
      }
    }
    this.hostWindow = null;
    this.windowStage = null;
    if (AppStorage.get<string>('masterCapsuleToken') === this.instanceToken) {
      this.clearHostRegistration();
    }
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private async configureHiddenHostWindow(): Promise<void> {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.warn('hide capsule ability host decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.warn('hide capsule ability host title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.warn('clear capsule ability host surface failed: ' + String(error));
    }
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable capsule ability host shadow failed: ' + String(error));
    }
    try {
      await win.setWindowTouchable(false);
      await win.setWindowFocusable(false);
    } catch (error) {
      console.warn('disable capsule ability host interaction failed: ' + String(error));
    }
    const screen: display.Display = display.getDefaultDisplaySync();
    try {
      await win.resizeAsync(1, 1);
    } catch (error) {
      try {
        await win.resize(1, 1);
      } catch (resizeError) {
        console.warn('shrink capsule ability host failed: ' + String(resizeError));
      }
    }
    // API 23 application subwindows still belong to the parent WindowStage.
    // Keep exactly one physical pixel of the parent window on-screen instead of
    // moving the entire parent outside the display; API 26 independent subwindows
    // are not available to this build yet. The parent remains non-touchable,
    // non-focusable, transparent, and sits in the bottom-right corner.
    const edgeX: number = Math.max(0, screen.width - 1);
    const edgeY: number = Math.max(0, screen.height - 1);
    try {
      await win.moveWindowToAsync(edgeX, edgeY);
    } catch (error) {
      try {
        await win.moveWindowTo(edgeX, edgeY);
      } catch (moveError) {
        console.warn('anchor capsule ability host at display edge failed: ' + String(moveError));
      }
    }
    try {
      await win.showWindow();
    } catch (error) {
      console.warn('ensure capsule ability host visible failed: ' + String(error));
    }
  }

  private async createCapsuleSubWindow(windowStage: window.WindowStage): Promise<void> {
    const subWindow: window.Window = await windowStage.createSubWindow(CAPSULE_SUBWINDOW_NAME);
    if (this.windowStage !== windowStage || this.closeRequested || !this.isEligible()) {
      try {
        subWindow.destroyWindow();
      } catch (_error) {
      }
      return;
    }

    this.mainWindow = subWindow;
    try {
      await subWindow.setFollowParentWindowLayoutEnabled(false);
    } catch (error) {
      console.warn('disable capsule subwindow parent-layout following failed: ' + String(error));
    }
    AppStorage.setOrCreate<window.Window>('masterCapsuleWindow', subWindow);
    AppStorage.setOrCreate<string>('masterCapsuleToken', this.instanceToken);
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', true);
    this.applyWindowStyle();
    this.registerCloseEvents(windowStage);
    await this.setInitialWindowInteraction(false);
    await this.prepareInitialGeometry();

    await new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      subWindow.setUIContent('pages/MasterCapsule', (error: BusinessError): void => {
        if (error.code !== 0) {
          reject(new Error('load capsule subwindow content failed: ' + error.message));
          return;
        }
        resolve();
      });
    });
    if (this.mainWindow !== subWindow || this.closeRequested) {
      return;
    }
    this.applyWindowStyle();
    this.applyTransparentSurfaceStyle();
    this.notifyAvailableAreaChanged();
    await subWindow.showWindow();
    setTimeout((): void => {
      this.restoreInitialWindowInteraction().catch((restoreError: Error): void => {
        console.warn('restore capsule subwindow interaction failed: ' + restoreError.message);
      });
    }, INITIAL_INTERACTION_RESTORE_DELAY_MS);
  }

  private async prepareInitialGeometry(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    const contextWindow: window.Window | null = this.hostWindow;
    if (win === null || contextWindow === null) {
      return;
    }
    // A newly created subwindow does not have page content yet at this point.
    // Huawei's official irregular-window flow sizes/moves the subwindow before
    // setUIContent(), so use the already-loaded parent UIContext for vp/px
    // conversion. After setUIContent succeeds, MasterCapsule uses the subwindow's
    // own UIContext for all subsequent geometry/mask updates.
    const uiContext: UIContext = contextWindow.getUIContext();
    const targetDisplay: display.Display = this.activeDisplay ?? display.getDefaultDisplaySync();
    const area: display.Rect = await this.getAvailableArea(targetDisplay);
    const state: AppState = PaperStore.loadState();
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    if (members.length === 0) {
      return;
    }
    const includeMaster: boolean = state.useMasterCapsule;
    const queueRetracted: boolean = includeMaster && state.capsuleCollapseAllActive;
    const areaHeightVp: number = uiContext.px2vp(area.height);
    const startTop: number = normalizeCapsuleStartTopMargin(state.capsuleStartTop, areaHeightVp,
      members.length, state.capsuleGap, includeMaster);
    const widthVp: number = this.hostWidthVp(members, includeMaster, queueRetracted);
    const visibleMemberCount: number = queueRetracted ? 0 : members.length;
    const slotCount: number = visibleMemberCount + (includeMaster ? 1 : 0);
    const heightVp: number = Math.max(CAPSULE_HEIGHT,
      slotCount * CAPSULE_HEIGHT + Math.max(0, slotCount - 1) * state.capsuleGap);
    const requestedWidthPx: number = Math.round(uiContext.vp2px(widthVp));
    const requestedHeightPx: number = Math.round(uiContext.vp2px(heightVp));

    try {
      await win.resizeAsync(requestedWidthPx, requestedHeightPx);
    } catch (error) {
      console.warn('initial async capsule subwindow resize failed, falling back: ' + String(error));
      await win.resize(requestedWidthPx, requestedHeightPx);
    }

    let actualWidthPx: number = requestedWidthPx;
    try {
      const rect = win.getWindowProperties().windowRect;
      actualWidthPx = Math.max(1, rect.width);
    } catch (error) {
      console.warn('query initial capsule subwindow width failed: ' + String(error));
    }
    const xPx: number = Math.round(targetDisplay.width - actualWidthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(startTop));
    try {
      await win.moveWindowToAsync(xPx, yPx);
    } catch (error) {
      console.warn('initial async capsule subwindow move failed, falling back: ' + String(error));
      await win.moveWindowTo(xPx, yPx);
    }
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable initial capsule subwindow shadow failed: ' + String(error));
    }
  }

  private hostWidthVp(members: PaperData[], includeMaster: boolean, queueRetracted: boolean): number {
    if (includeMaster && queueRetracted) {
      return INITIAL_MASTER_ROW_WIDTH;
    }
    let width: number = includeMaster ? INITIAL_MASTER_ROW_WIDTH : CAPSULE_MIN_WIDTH;
    for (let i: number = 0; i < members.length; i++) {
      width = Math.max(width,
        Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, members[i].capsuleWidth)));
    }
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, width));
  }

  private async getAvailableArea(targetDisplay: display.Display): Promise<display.Rect> {
    try {
      return await targetDisplay.getAvailableArea();
    } catch (error) {
      console.warn('get capsule host available area failed: ' + String(error));
      return {
        left: 0,
        top: 0,
        width: targetDisplay.availableWidth > 0 ? targetDisplay.availableWidth : targetDisplay.width,
        height: targetDisplay.availableHeight > 0 ? targetDisplay.availableHeight : targetDisplay.height
      };
    }
  }

  private async setInitialWindowInteraction(enabled: boolean): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    this.initialInteractionLocked = !enabled;
    try {
      await win.setWindowTouchable(enabled);
    } catch (error) {
      console.warn('set capsule host touchability failed: ' + String(error));
    }
    try {
      await win.setWindowFocusable(enabled);
    } catch (error) {
      console.warn('set capsule host focusability failed: ' + String(error));
    }
  }

  private async restoreInitialWindowInteraction(): Promise<void> {
    if (!this.initialInteractionLocked || this.closeRequested) {
      return;
    }
    await this.setInitialWindowInteraction(true);
  }

  private isEligible(): boolean {
    const state: AppState = PaperStore.loadState();
    return state.useCapsuleMode && state.useDeepCapsuleMode &&
      PaperStore.listEdgeCapsulePapers().length > 0;
  }

  private registerAvailableAreaListener(): void {
    try {
      const targetDisplay: display.Display = display.getDefaultDisplaySync();
      targetDisplay.on('availableAreaChange', this.availableAreaCallback);
      this.activeDisplay = targetDisplay;
    } catch (error) {
      console.warn('register capsule host available-area listener failed: ' + String(error));
    }
  }

  private unregisterAvailableAreaListener(): void {
    const targetDisplay: display.Display | null = this.activeDisplay;
    this.activeDisplay = null;
    if (targetDisplay === null) {
      return;
    }
    try {
      targetDisplay.off('availableAreaChange', this.availableAreaCallback);
    } catch (error) {
      console.warn('unregister capsule host available-area listener failed: ' + String(error));
    }
  }

  private notifyAvailableAreaChanged(): void {
    const revision: number = AppStorage.get<number>('capsuleAreaRevision') ?? 0;
    AppStorage.setOrCreate<number>('capsuleAreaRevision', revision + 1);
  }

  private preserveCapsuleHost(): void {
    PaperStore.flushNow();
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', true);
    this.applyWindowStyle();
    this.notifyAvailableAreaChanged();
  }

  private clearHostRegistration(): void {
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', false);
    AppStorage.delete('masterCapsuleWindow');
    AppStorage.delete('masterCapsuleToken');
  }

  private registerCloseEvents(windowStage: window.WindowStage): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null) {
      try {
        win.on('windowWillClose', this.windowWillCloseCallback);
        this.closeEventRegistered = true;
      } catch (error) {
        console.warn('register capsule host close event failed: ' + String(error));
      }
    }
    try {
      windowStage.on('windowStageClose', this.windowStageCloseCallback);
      this.stageCloseEventRegistered = true;
    } catch (error) {
      console.warn('register capsule host stage-close event failed: ' + String(error));
    }
  }

  private unregisterCloseEvents(): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null && this.closeEventRegistered) {
      try {
        win.off('windowWillClose', this.windowWillCloseCallback);
      } catch (error) {
        console.warn('unregister capsule host close event failed: ' + String(error));
      }
    }
    this.closeEventRegistered = false;
    const stage: window.WindowStage | null = this.windowStage;
    if (stage !== null && this.stageCloseEventRegistered) {
      try {
        stage.off('windowStageClose', this.windowStageCloseCallback);
      } catch (error) {
        console.warn('unregister capsule host stage-close event failed: ' + String(error));
      }
    }
    this.stageCloseEventRegistered = false;
  }

  private showAndRestyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    win.showWindow()
      .then((): void => {
        this.applyWindowStyle();
        this.applyTransparentSurfaceStyle();
      })
      .catch((error: BusinessError): void => {
        console.error('show capsule subwindow failed: ' + error.message);
      });
  }

  private applyTransparentSurfaceStyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.warn('clear capsule host background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.warn('clear capsule host container failed: ' + String(error));
    }
  }

  private applyWindowStyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.warn('hide capsule host decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
    } catch (error) {
      console.warn('hide capsule host title buttons failed: ' + String(error));
    }
    try {
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.warn('disable capsule host title move failed: ' + String(error));
    }
    try {
      win.setResizeByDragEnabled(false);
    } catch (error) {
      console.warn('disable capsule host resize drag failed: ' + String(error));
    }
    this.applyTransparentSurfaceStyle();
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.warn('disable capsule host shadow failed: ' + error.message);
    });
    win.setWindowTopmost(true).catch((error: BusinessError): void => {
      console.warn('set capsule host topmost failed: ' + error.message);
    });
  }

  private terminateAbility(): void {
    this.closeRequested = true;
    this.unregisterCloseEvents();
    const capsuleWindow: window.Window | null = this.mainWindow;
    this.mainWindow = null;
    this.clearHostRegistration();
    if (capsuleWindow !== null) {
      try {
        capsuleWindow.destroyWindow();
      } catch (error) {
        console.warn('destroy capsule subwindow during terminate failed: ' + String(error));
      }
    }
    this.context.terminateSelf().catch((error: BusinessError): void => {
      console.warn('terminate capsule host failed: ' + error.message);
    });
  }

  private readCommand(want: Want): string {
    if (want.parameters === undefined) {
      return 'show';
    }
    const value: Object | undefined = want.parameters.capsuleCommand;
    return value === undefined || value === null ? 'show' : String(value);
  }
}
