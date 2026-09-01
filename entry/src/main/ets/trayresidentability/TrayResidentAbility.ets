import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { window } from '@kit.ArkUI';
import { DesktopShell } from '../common/DesktopShell';
import { GlobalHotkeys } from '../common/GlobalHotkeys';
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData, UI_LANGUAGE_SYSTEM } from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import {
  STATUS_EVENT_HIDE_ALL,
  STATUS_EVENT_NEW_NOTE,
  STATUS_EVENT_NEW_TODO,
  STATUS_EVENT_OPEN_SETTINGS,
  STATUS_EVENT_SHOW_ALL,
  STATUS_EVENT_TOGGLE_PAPER
} from '../common/StatusBarEvents';
import {
  TRAY_MENU_NEW_NOTE,
  TRAY_MENU_NEW_TODO,
  TRAY_MENU_EXIT,
  TRAY_MENU_PAPER_OVERFLOW,
  TRAY_MENU_PAPER_PREFIX,
  TRAY_MENU_SETTINGS,
  TRAY_MENU_TOGGLE_ALL,
  TrayService
} from '../common/TrayService';

export default class TrayResidentAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private menuWatchTimer: number = -1;
  private menuRefreshPending: boolean = false;
  private observedPaperMenuSignature: string = '';
  private static readonly MENU_WATCH_INTERVAL_MS: number = 1500;
  private readonly instanceToken: string = 'resident_' + Date.now().toString(36) + '_' +
    Math.floor(Math.random() * 0xFFFFFF).toString(36);
  private readonly rightMenuCallback: (eventData: emitter.EventData) => void =
    (eventData: emitter.EventData): void => this.handleRightMenu(eventData);
  private readonly newTodoCallback: () => void = (): void => {
    DesktopShell.createPaper(this.context, PAPER_TYPE_TODO);
  };
  private readonly newNoteCallback: () => void = (): void => {
    DesktopShell.createPaper(this.context, PAPER_TYPE_NOTE);
  };
  private readonly showAllCallback: () => void = (): void => {
    DesktopShell.showAll(this.context);
  };
  private readonly hideAllCallback: () => void = (): void => {
    DesktopShell.hideAll(this.context);
  };
  private readonly openSettingsCallback: () => void = (): void => {
    DesktopShell.openSettings(this.context);
  };
  private readonly togglePaperCallback: (eventData: emitter.EventData) => void =
    (eventData: emitter.EventData): void => this.handleTogglePaper(eventData);

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.observedPaperMenuSignature = this.paperMenuSignature();
    this.startMenuWatch();
    AppStorage.setOrCreate<boolean>('trayResidentReady', false);
    AppStorage.setOrCreate<string>('trayResidentToken', this.instanceToken);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    GlobalHotkeys.configure(this.context);
    try {
      statusBarManager.on('rightMenuClick', this.rightMenuCallback);
    } catch (error) {
      console.error('listen status bar menu failed: ' + String(error));
    }
    emitter.on({ eventId: STATUS_EVENT_NEW_TODO }, this.newTodoCallback);
    emitter.on({ eventId: STATUS_EVENT_NEW_NOTE }, this.newNoteCallback);
    emitter.on({ eventId: STATUS_EVENT_SHOW_ALL }, this.showAllCallback);
    emitter.on({ eventId: STATUS_EVENT_HIDE_ALL }, this.hideAllCallback);
    emitter.on({ eventId: STATUS_EVENT_OPEN_SETTINGS }, this.openSettingsCallback);
    emitter.on({ eventId: STATUS_EVENT_TOGGLE_PAPER }, this.togglePaperCallback);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindow = windowStage.getMainWindowSync();
    this.prepareHiddenHostWindow();
    windowStage.loadContent('pages/Host', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load resident host failed: ' + JSON.stringify(error));
      }
      this.hideHostWindow();
      if (AppStorage.get<string>('trayResidentToken') === this.instanceToken) {
        AppStorage.setOrCreate<boolean>('trayResidentReady', true);
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.hideHostWindow();
  }

  onForeground(): void {
    this.hideHostWindow();
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    const uiLanguage: string = AppStorage.get<string>('uiLanguage') ?? UI_LANGUAGE_SYSTEM;
    if (uiLanguage === UI_LANGUAGE_SYSTEM) {
      TrayService.refreshMenu(this.context).catch((error: Error): void => {
        console.error('refresh status bar menu system language failed: ' + error.message);
      });
    }
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    this.stopMenuWatch();
    PaperStore.flushNow();
    if (AppStorage.get<string>('trayResidentToken') === this.instanceToken) {
      AppStorage.setOrCreate<boolean>('trayResidentReady', false);
      AppStorage.delete('trayResidentToken');
    }
    GlobalHotkeys.shutdown();
    try {
      statusBarManager.off('rightMenuClick', this.rightMenuCallback);
    } catch (error) {
      console.error('remove status bar menu listener failed: ' + String(error));
    }
    emitter.off(STATUS_EVENT_NEW_TODO, this.newTodoCallback);
    emitter.off(STATUS_EVENT_NEW_NOTE, this.newNoteCallback);
    emitter.off(STATUS_EVENT_SHOW_ALL, this.showAllCallback);
    emitter.off(STATUS_EVENT_HIDE_ALL, this.hideAllCallback);
    emitter.off(STATUS_EVENT_OPEN_SETTINGS, this.openSettingsCallback);
    emitter.off(STATUS_EVENT_TOGGLE_PAPER, this.togglePaperCallback);
    this.mainWindow = null;
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    PaperStore.flushNow();
    return false;
  }

  private handleRightMenu(eventData: emitter.EventData): void {
    if (eventData.data === undefined) {
      return;
    }
    const rawCode: Object | undefined = eventData.data.menuCode;
    const menuCode: string = rawCode === undefined || rawCode === null ? '' : String(rawCode);
    if (menuCode === TRAY_MENU_NEW_TODO) {
      DesktopShell.createPaper(this.context, PAPER_TYPE_TODO);
    } else if (menuCode === TRAY_MENU_NEW_NOTE) {
      DesktopShell.createPaper(this.context, PAPER_TYPE_NOTE);
    } else if (menuCode === TRAY_MENU_TOGGLE_ALL) {
      this.toggleAll();
    } else if (menuCode === TRAY_MENU_SETTINGS) {
      DesktopShell.openSettings(this.context);
    } else if (menuCode === TRAY_MENU_EXIT) {
      DesktopShell.exitApplication(this.context);
    } else if (menuCode.startsWith(TRAY_MENU_PAPER_PREFIX)) {
      const encodedPaperId: string = menuCode.substring(TRAY_MENU_PAPER_PREFIX.length);
      try {
        this.togglePaper(decodeURIComponent(encodedPaperId));
      } catch (error) {
        console.error('decode status bar paper menu failed: ' + String(error));
      }
    } else if (menuCode === TRAY_MENU_PAPER_OVERFLOW) {
      // The final submenu row is an informational remainder summary. Keeping a
      // valid notify-only action avoids the platform rejecting the whole menu.
      return;
    }
  }

  private toggleAll(): void {
    const papers: PaperData[] = PaperStore.listPapers();
    let anyVisible: boolean = false;
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].isVisible) {
        anyVisible = true;
        break;
      }
    }
    if (anyVisible) {
      DesktopShell.hideAll(this.context);
    } else {
      DesktopShell.showAll(this.context);
    }
  }

  private handleTogglePaper(eventData: emitter.EventData): void {
    if (eventData.data === undefined) {
      return;
    }
    const rawId: Object | undefined = eventData.data.paperId;
    if (rawId === undefined || rawId === null) {
      return;
    }
    this.togglePaper(String(rawId));
  }

  private togglePaper(paperId: string): void {
    const paper: PaperData | null = PaperStore.getPaper(paperId);
    if (paper === null) {
      return;
    }
    const command: string = paper.isVisible ? 'hide' : 'show';
    if (paper.isVisible) {
      PaperStore.setPaperVisible(paper.id, false);
    } else {
      PaperStore.setPaperVisible(paper.id, true);
    }
    DesktopShell.startPaper(this.context, paper.id, command)
      .then((_started: boolean): Promise<boolean> => DesktopShell.syncCapsules(this.context))
      .then((_reachable: boolean): Promise<boolean> => TrayService.refreshMenu(this.context))
      .then((_refreshed: boolean): void => {
        this.observedPaperMenuSignature = this.paperMenuSignature();
      })
      .catch((error: Error): void => {
        console.error('toggle paper from status bar menu failed: ' + error.message);
      });
  }

  private startMenuWatch(): void {
    if (this.menuWatchTimer >= 0) {
      return;
    }
    this.menuWatchTimer = setInterval((): void => this.checkPaperMenuRevision(),
      TrayResidentAbility.MENU_WATCH_INTERVAL_MS);
  }

  private stopMenuWatch(): void {
    if (this.menuWatchTimer < 0) {
      return;
    }
    clearInterval(this.menuWatchTimer);
    this.menuWatchTimer = -1;
  }

  private checkPaperMenuRevision(): void {
    const nextSignature: string = this.paperMenuSignature();
    if (nextSignature === this.observedPaperMenuSignature || this.menuRefreshPending) {
      return;
    }
    this.menuRefreshPending = true;
    TrayService.refreshMenu(this.context).then((success: boolean): void => {
      if (success) {
        this.observedPaperMenuSignature = nextSignature;
      }
      this.menuRefreshPending = false;
    }).catch((error: Error): void => {
      this.menuRefreshPending = false;
      console.error('watch status bar paper menu failed: ' + error.message);
    });
  }

  private paperMenuSignature(): string {
    const papers: PaperData[] = PaperStore.listPapers();
    const revision: number = AppStorage.get<number>('paperRevision') ?? 0;
    const parts: string[] = [revision.toString(), papers.length.toString()];
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      parts.push(paper.id, paper.type, paper.title, paper.isVisible ? '1' : '0');
    }
    return parts.join('\u0000');
  }

  private hideHostWindow(): void {
    this.prepareHiddenHostWindow();
    this.context.hideAbility().catch((error: BusinessError): void => {
      console.error('hide resident host failed: ' + error.message);
    });
  }

  private prepareHiddenHostWindow(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.error('hide resident decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
    } catch (error) {
      console.error('hide resident title buttons failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
    } catch (error) {
      console.error('clear resident background failed: ' + String(error));
    }
    try {
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.error('clear resident container failed: ' + String(error));
    }
    win.setWindowShadowEnabled(false).catch((error: BusinessError): void => {
      console.error('disable resident shadow failed: ' + error.message);
    });
    win.setWindowTouchable(false).catch((error: BusinessError): void => {
      console.error('disable resident touch failed: ' + error.message);
    });
    win.setWindowFocusable(false).catch((error: BusinessError): void => {
      console.error('disable resident focus failed: ' + error.message);
    });
  }
}
