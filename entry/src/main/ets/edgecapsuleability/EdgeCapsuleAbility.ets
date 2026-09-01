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
import { DesktopShell } from '../common/DesktopShell';
import {
  CAPSULE_CLOSE_WIDTH,
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  CAPSULE_PLATFORM_MIN_WIDTH,
  AppState,
  PaperData
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

interface EdgeCapsuleStorageData {
  paperId: string;
}

export default class EdgeCapsuleAbility extends UIAbility {
  private paperId: string = '';
  private storage: LocalStorage = new LocalStorage();
  private mainWindow: window.Window | null = null;
  private windowStage: window.WindowStage | null = null;
  private currentDisplay: display.Display | null = null;
  private instanceToken: string = '';
  private closeRequested: boolean = false;
  private closeEventRegistered: boolean = false;
  private stageCloseEventRegistered: boolean = false;
  private systemCloseInProgress: boolean = false;
  private readonly windowWillCloseCallback: () => Promise<boolean> = (): Promise<boolean> => {
    if (this.closeRequested) {
      return Promise.resolve(false);
    }
    this.handleSystemCloseRequest();
    return Promise.resolve(true);
  };
  private readonly windowStageCloseCallback: () => boolean = (): boolean => {
    if (this.closeRequested) {
      return false;
    }
    this.handleSystemCloseRequest();
    return true;
  };
  private readonly availableAreaCallback: (area: display.Rect) => void =
    (_area: display.Rect): void => {
      const revision: number = AppStorage.get<number>('capsuleAreaRevision') ?? 0;
      AppStorage.setOrCreate<number>('capsuleAreaRevision', revision + 1);
    };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    this.closeRequested = this.readCommand(want) === 'close';
    const data: EdgeCapsuleStorageData = { paperId: this.paperId };
    this.storage = new LocalStorage(data);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate<number>('capsuleAreaRevision',
      AppStorage.get<number>('capsuleAreaRevision') ?? 0);

    if (!this.closeRequested && this.paperId.length > 0) {
      this.instanceToken = this.makeInstanceToken();
      AppStorage.setOrCreate<string>('edgeCapsuleToken:' + this.paperId, this.instanceToken);
      AppStorage.setOrCreate<boolean>('edgeCapsuleOpen:' + this.paperId, true);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const command: string = this.readCommand(want);
    if (command === 'close') {
      this.closeRequested = true;
      this.terminateAbility();
      return;
    }
    this.closeRequested = false;
    if (this.paperId.length > 0) {
      AppStorage.setOrCreate<boolean>('edgeCapsuleOpen:' + this.paperId, true);
    }
    this.showAndRestyle();
    this.notifyAvailableAreaChanged();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    if (this.closeRequested || this.paperId.length === 0 || PaperStore.getPaper(this.paperId) === null) {
      this.terminateAbility();
      return;
    }

    try {
      this.mainWindow = windowStage.getMainWindowSync();
    } catch (error) {
      console.error('get edge capsule window failed: ' + String(error));
      this.terminateAbility();
      return;
    }
    AppStorage.setOrCreate<window.Window>('edgeWindow:' + this.paperId, this.mainWindow);
    this.applyWindowStyle();
    this.registerCloseEvents(windowStage);
    this.registerAvailableAreaListener();
    this.prepareInitialGeometry().then((): void => {
      if (this.closeRequested) {
        this.terminateAbility();
        return;
      }
      windowStage.loadContent('pages/EdgeCapsule', this.storage, (error: BusinessError): void => {
        if (error.code !== 0) {
          console.error('load edge capsule failed: ' + error.message);
          this.terminateAbility();
          return;
        }
        this.applyWindowStyle();
      });
    }).catch((error: Error): void => {
      console.error('prepare edge capsule failed: ' + error.message);
      this.terminateAbility();
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
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.unregisterCloseEvents();
    this.unregisterAvailableAreaListener();
    if (this.paperId.length > 0 &&
      AppStorage.get<string>('edgeCapsuleToken:' + this.paperId) === this.instanceToken) {
      AppStorage.setOrCreate<boolean>('edgeCapsuleOpen:' + this.paperId, false);
      AppStorage.delete('edgeWindow:' + this.paperId);
      AppStorage.delete('edgeCapsuleToken:' + this.paperId);
    }
    this.mainWindow = null;
    this.windowStage = null;
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private async prepareInitialGeometry(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (win === null || paper === null) {
      return;
    }
    const uiContext: UIContext = win.getUIContext();
    const screen: display.Display = this.currentDisplay ?? display.getDefaultDisplaySync();
    const area: display.Rect = await this.getAvailableArea(screen);
    const state: AppState = PaperStore.loadState();
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    const memberIndex: number = this.memberIndex(members);
    const includeMaster: boolean = state.useMasterCapsule && members.length > 0;
    const areaHeightVp: number = uiContext.px2vp(area.height);
    const startTop: number = normalizeCapsuleStartTopMargin(state.capsuleStartTop, areaHeightVp,
      members.length, state.capsuleGap, includeMaster);
    let slotTop: number = capsuleSlotTop(startTop, Math.max(0, memberIndex), state.capsuleGap,
      includeMaster);
    if (state.capsuleCollapseAllActive) {
      slotTop = capsuleSlotTop(startTop, 0, state.capsuleGap, false);
    }
    const widthVp: number = Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, paper.capsuleWidth));
    const widthPx: number = Math.round(uiContext.vp2px(widthVp));
    const heightPx: number = Math.round(uiContext.vp2px(CAPSULE_HEIGHT));
    let visibleWidthVp: number = paper.isCollapsed ? widthVp - CAPSULE_CLOSE_WIDTH : widthVp;
    if (state.capsuleCollapseAllActive) {
      visibleWidthVp = 0;
    }
    visibleWidthVp = Math.max(0, visibleWidthVp);
    const targetX: number = area.left + area.width - Math.round(uiContext.vp2px(visibleWidthVp));
    const targetY: number = area.top + Math.round(uiContext.vp2px(slotTop));

    try {
      await win.setWindowLimits({
        minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
        minHeight: heightPx,
        maxWidth: Math.max(widthPx, area.width),
        maxHeight: Math.max(heightPx, area.height)
      }, true);
    } catch (error) {
      console.warn('set edge capsule window limits failed: ' + String(error));
    }
    await win.resize(widthPx, heightPx);
    await win.moveWindowTo(targetX, targetY);
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable initial edge capsule shadow failed: ' + String(error));
    }
    try {
      await win.setWindowTopmost(true);
    } catch (error) {
      console.warn('set initial edge capsule topmost failed: ' + String(error));
    }
    try {
      await win.setWindowTouchable(!state.capsuleCollapseAllActive);
    } catch (error) {
      console.warn('set initial edge capsule touchability failed: ' + String(error));
    }
    this.applyWindowStyle();
  }

  private handleSystemCloseRequest(): void {
    if (this.systemCloseInProgress || this.closeRequested) {
      return;
    }
    this.systemCloseInProgress = true;
    PaperStore.setPaperVisible(this.paperId, false);
    PaperStore.flushNow();
    DesktopShell.syncCapsules(this.context).then((): void => {
      this.closeRequested = true;
      this.terminateAbility();
    }).catch((error: Error): void => {
      console.error('sync system-closed edge capsule failed: ' + error.message);
      this.closeRequested = true;
      this.terminateAbility();
    });
  }

  private registerCloseEvents(windowStage: window.WindowStage): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null) {
      try {
        win.on('windowWillClose', this.windowWillCloseCallback);
        this.closeEventRegistered = true;
      } catch (error) {
        console.warn('register edge capsule close event failed: ' + String(error));
      }
    }
    try {
      windowStage.on('windowStageClose', this.windowStageCloseCallback);
      this.stageCloseEventRegistered = true;
    } catch (error) {
      console.warn('register edge capsule stage-close event failed: ' + String(error));
    }
  }

  private unregisterCloseEvents(): void {
    const win: window.Window | null = this.mainWindow;
    if (win !== null && this.closeEventRegistered) {
      try {
        win.off('windowWillClose', this.windowWillCloseCallback);
      } catch (error) {
        console.warn('unregister edge capsule close event failed: ' + String(error));
      }
    }
    this.closeEventRegistered = false;
    const stage: window.WindowStage | null = this.windowStage;
    if (stage !== null && this.stageCloseEventRegistered) {
      try {
        stage.off('windowStageClose', this.windowStageCloseCallback);
      } catch (error) {
        console.warn('unregister edge capsule stage-close event failed: ' + String(error));
      }
    }
    this.stageCloseEventRegistered = false;
  }

  private async getAvailableArea(screen: display.Display): Promise<display.Rect> {
    try {
      return await screen.getAvailableArea();
    } catch (error) {
      console.warn('get edge capsule available area failed: ' + String(error));
      return {
        left: 0,
        top: 0,
        width: screen.availableWidth > 0 ? screen.availableWidth : screen.width,
        height: screen.availableHeight > 0 ? screen.availableHeight : screen.height
      };
    }
  }

  private memberIndex(members: PaperData[]): number {
    for (let i: number = 0; i < members.length; i++) {
      if (members[i].id === this.paperId) {
        return i;
      }
    }
    return 0;
  }

  private registerAvailableAreaListener(): void {
    try {
      this.currentDisplay = display.getDefaultDisplaySync();
      this.currentDisplay.on('availableAreaChange', this.availableAreaCallback);
    } catch (error) {
      this.currentDisplay = null;
      console.warn('listen edge capsule available area failed: ' + String(error));
    }
  }

  private unregisterAvailableAreaListener(): void {
    const screen: display.Display | null = this.currentDisplay;
    if (screen === null) {
      return;
    }
    try {
      screen.off('availableAreaChange', this.availableAreaCallback);
    } catch (error) {
      console.warn('remove edge capsule available area listener failed: ' + String(error));
    }
    this.currentDisplay = null;
  }

  private showAndRestyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    win.restore().catch((_restoreError: BusinessError): Promise<void> => win.showWindow())
      .then((): void => this.applyWindowStyle())
      .catch((error: BusinessError): void => {
        console.error('show edge capsule failed: ' + error.message);
      });
  }

  private notifyAvailableAreaChanged(): void {
    const revision: number = AppStorage.get<number>('capsuleAreaRevision') ?? 0;
    AppStorage.setOrCreate<number>('capsuleAreaRevision', revision + 1);
  }

  private applyWindowStyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.error('hide edge capsule decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.error('hide edge capsule title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.error('clear edge capsule background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.error('clear edge capsule container failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.error('disable edge capsule shadow failed: ' + error.message);
    });
    win.setWindowTopmost(true).catch((error: BusinessError): void => {
      console.error('set edge capsule topmost failed: ' + error.message);
    });
  }

  private terminateAbility(): void {
    this.context.terminateSelf().catch((error: BusinessError): void => {
      console.error('terminate edge capsule failed: ' + error.message);
    });
  }

  private makeInstanceToken(): string {
    return Date.now().toString(36) + '_' + Math.floor(Math.random() * 1000000000).toString(36);
  }

  private readPaperId(want: Want): string {
    if (want.parameters === undefined) {
      return '';
    }
    const value: Object | undefined = want.parameters.paperId;
    return value === undefined || value === null ? '' : String(value);
  }

  private readCommand(want: Want): string {
    if (want.parameters === undefined) {
      return 'show';
    }
    const value: Object | undefined = want.parameters.capsuleCommand;
    return value === undefined || value === null ? 'show' : String(value);
  }
}
