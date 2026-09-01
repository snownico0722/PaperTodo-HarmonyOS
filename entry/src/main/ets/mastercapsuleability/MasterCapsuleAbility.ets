import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { capsuleSlotTop, normalizeCapsuleStartTopMargin } from '../common/CapsuleLayout';
import {
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  CAPSULE_PLATFORM_MIN_WIDTH,
  AppState
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const INITIAL_MASTER_WIDTH_VP: number = 176;
const INITIAL_INTERACTION_RESTORE_DELAY_MS: number = 16;

export default class MasterCapsuleAbility extends UIAbility {
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
    this.preserveMainCapsule();
    return Promise.resolve(true);
  };
  private readonly windowStageCloseCallback: () => boolean = (): boolean => {
    if (this.closeRequested) {
      return false;
    }
    this.preserveMainCapsule();
    return true;
  };
  private readonly instanceToken: string = 'master_' + Date.now().toString(36) + '_' +
    Math.floor(Math.random() * 0xFFFFFF).toString(36);
  private readonly availableAreaCallback: (area: display.Rect) => void = (_area: display.Rect): void => {
    const revision: number = AppStorage.get<number>('capsuleAreaRevision') ?? 0;
    AppStorage.setOrCreate<number>('capsuleAreaRevision', revision + 1);
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
      AppStorage.setOrCreate<boolean>('masterCapsuleOpen', false);
      AppStorage.delete('masterCapsuleWindow');
      AppStorage.delete('masterCapsuleToken');
      this.terminateAbility();
      return;
    }

    let win: window.Window;
    try {
      win = windowStage.getMainWindowSync();
    } catch (error) {
      console.error('get master capsule window failed: ' + String(error));
      this.terminateAbility();
      return;
    }
    this.mainWindow = win;
    this.applyWindowStyle();
    this.registerCloseEvents(windowStage);
    AppStorage.setOrCreate<window.Window>('masterCapsuleWindow', win);
    AppStorage.setOrCreate<string>('masterCapsuleToken', this.instanceToken);
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', true);
    AppStorage.setOrCreate<number>('capsuleAreaRevision',
      AppStorage.get<number>('capsuleAreaRevision') ?? 0);
    this.registerAvailableAreaListener();

    this.prepareInitialWindowAndLoadContent(windowStage).catch((error: Error): void => {
      console.warn('prepare initial master capsule failed: ' + error.message);
      this.loadMasterCapsuleContent(windowStage);
    });
  }

  onForeground(): void {
    this.applyWindowStyle();
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
    this.mainWindow = null;
    this.windowStage = null;
    if (AppStorage.get<string>('masterCapsuleToken') === this.instanceToken) {
      AppStorage.setOrCreate<boolean>('masterCapsuleOpen', false);
      AppStorage.delete('masterCapsuleWindow');
      AppStorage.delete('masterCapsuleToken');
    }
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  /**
   * A UIAbility window is created at a platform default size before ArkUI has
   * measured MasterCapsule.  Put that first frame at the eventual right-hand
   * queue slot, and keep it non-interactive until the page has replaced the
   * transparent native surface with its capsule content.
   */
  private async prepareInitialWindowAndLoadContent(windowStage: window.WindowStage): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    await this.setInitialWindowInteraction(false);
    await this.prepareInitialGeometry();
    this.applyWindowStyle();
    if (this.windowStage !== windowStage || this.mainWindow !== win || this.closeRequested) {
      return;
    }
    this.loadMasterCapsuleContent(windowStage);
  }

  private loadMasterCapsuleContent(windowStage: window.WindowStage): void {
    if (this.windowStage !== windowStage || this.mainWindow === null || this.closeRequested) {
      return;
    }
    windowStage.loadContent('pages/MasterCapsule', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load master capsule failed: ' + error.message);
        this.terminateAbility();
        return;
      }
      this.applyWindowStyle();
      // MasterCapsule reacts to this revision by measuring its localized label
      // and replacing the estimate above with its final width and position.
      this.notifyAvailableAreaChanged();
      setTimeout((): void => {
        this.restoreInitialWindowInteraction().catch((restoreError: Error): void => {
          console.warn('restore master capsule interaction failed: ' + restoreError.message);
        });
      }, INITIAL_INTERACTION_RESTORE_DELAY_MS);
    });
  }

  private async prepareInitialGeometry(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    const uiContext: UIContext = win.getUIContext();
    const targetDisplay: display.Display = this.activeDisplay ?? display.getDefaultDisplaySync();
    const area: display.Rect = await this.getAvailableArea(targetDisplay);
    const state: AppState = PaperStore.loadState();
    const memberCount: number = PaperStore.listEdgeCapsulePapers().length;
    const areaHeightVp: number = uiContext.px2vp(area.height);
    const startTop: number = normalizeCapsuleStartTopMargin(state.capsuleStartTop, areaHeightVp,
      memberCount, state.capsuleGap, true);
    const slotTop: number = capsuleSlotTop(startTop, 0, state.capsuleGap, false);
    const widthVp: number = Math.max(CAPSULE_MIN_WIDTH,
      Math.min(CAPSULE_MAX_WIDTH, INITIAL_MASTER_WIDTH_VP));
    const widthPx: number = Math.round(uiContext.vp2px(widthVp));
    const heightPx: number = Math.round(uiContext.vp2px(CAPSULE_HEIGHT));
    const xPx: number = Math.round(area.left + area.width - widthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(slotTop));

    try {
      await win.setWindowLimits({
        minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
        minHeight: heightPx,
        maxWidth: Math.max(widthPx, area.width),
        maxHeight: Math.max(heightPx, area.height)
      }, true);
    } catch (error) {
      console.warn('set initial master capsule limits failed: ' + String(error));
    }
    await win.resize(widthPx, heightPx);
    await win.moveWindowTo(xPx, yPx);
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable initial master capsule shadow failed: ' + String(error));
    }
    try {
      await win.setWindowTopmost(true);
    } catch (error) {
      console.warn('set initial master capsule topmost failed: ' + String(error));
    }
  }

  private async getAvailableArea(targetDisplay: display.Display): Promise<display.Rect> {
    try {
      return await targetDisplay.getAvailableArea();
    } catch (error) {
      console.warn('get master capsule available area failed: ' + String(error));
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
      console.warn('set master capsule touchability failed: ' + String(error));
    }
    try {
      await win.setWindowFocusable(enabled);
    } catch (error) {
      console.warn('set master capsule focusability failed: ' + String(error));
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
    return state.useCapsuleMode && state.useDeepCapsuleMode && state.useMasterCapsule &&
      PaperStore.listEdgeCapsulePapers().length > 0;
  }

  private registerAvailableAreaListener(): void {
    try {
      const targetDisplay: display.Display = display.getDefaultDisplaySync();
      targetDisplay.on('availableAreaChange', this.availableAreaCallback);
      this.activeDisplay = targetDisplay;
    } catch (error) {
      console.warn('register master capsule available-area listener failed: ' + String(error));
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
      console.warn('unregister master capsule available-area listener failed: ' + String(error));
    }
  }

  private notifyAvailableAreaChanged(): void {
    const revision: number = AppStorage.get<number>('capsuleAreaRevision') ?? 0;
    AppStorage.setOrCreate<number>('capsuleAreaRevision', revision + 1);
  }

  private preserveMainCapsule(): void {
    PaperStore.flushNow();
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', true);
    this.applyWindowStyle();
    this.notifyAvailableAreaChanged();
  }

  private registerCloseEvents(windowStage: window.WindowStage): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null) {
      try {
        win.on('windowWillClose', this.windowWillCloseCallback);
        this.closeEventRegistered = true;
      } catch (error) {
        console.warn('register master capsule close event failed: ' + String(error));
      }
    }
    try {
      windowStage.on('windowStageClose', this.windowStageCloseCallback);
      this.stageCloseEventRegistered = true;
    } catch (error) {
      console.warn('register master capsule stage-close event failed: ' + String(error));
    }
  }

  private unregisterCloseEvents(): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null && this.closeEventRegistered) {
      try {
        win.off('windowWillClose', this.windowWillCloseCallback);
      } catch (error) {
        console.warn('unregister master capsule close event failed: ' + String(error));
      }
    }
    this.closeEventRegistered = false;
    const stage: window.WindowStage | null = this.windowStage;
    if (stage !== null && this.stageCloseEventRegistered) {
      try {
        stage.off('windowStageClose', this.windowStageCloseCallback);
      } catch (error) {
        console.warn('unregister master capsule stage-close event failed: ' + String(error));
      }
    }
    this.stageCloseEventRegistered = false;
  }

  private showAndRestyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    win.restore().catch((_restoreError: BusinessError): Promise<void> => win.showWindow())
      .then((): void => this.applyWindowStyle())
      .catch((error: BusinessError): void => {
        console.error('show master capsule failed: ' + error.message);
      });
  }

  private applyWindowStyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.warn('hide master capsule decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.warn('hide master capsule title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.warn('clear master capsule background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.warn('clear master capsule container failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.warn('disable master capsule shadow failed: ' + error.message);
    });
    win.setWindowTopmost(true).catch((error: BusinessError): void => {
      console.warn('set master capsule topmost failed: ' + error.message);
    });
  }

  private terminateAbility(): void {
    this.context.terminateSelf().catch((error: BusinessError): void => {
      console.warn('terminate master capsule failed: ' + error.message);
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
