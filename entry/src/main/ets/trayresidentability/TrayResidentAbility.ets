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
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from '../common/Models';
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
  TRAY_MENU_SETTINGS,
  TRAY_MENU_TOGGLE_ALL
} from '../common/TrayService';

export default class TrayResidentAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
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
    windowStage.loadContent('pages/Host', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load resident host failed: ' + JSON.stringify(error));
        return;
      }
      this.hideHostWindow();
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.hideHostWindow();
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
    const paper: PaperData | null = PaperStore.getPaper(String(rawId));
    if (paper === null) {
      return;
    }
    if (paper.isVisible) {
      PaperStore.setPaperVisible(paper.id, false);
      DesktopShell.startPaper(this.context, paper.id, 'hide');
    } else {
      PaperStore.setPaperVisible(paper.id, true);
      DesktopShell.startPaper(this.context, paper.id, 'show');
    }
  }

  private hideHostWindow(): void {
    const win: window.Window | null = this.mainWindow;
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
      console.error('style resident host failed: ' + String(error));
    }
    win.setWindowTouchable(false).catch((error: BusinessError): void => {
      console.error('disable resident touch failed: ' + error.message);
    });
    win.setWindowFocusable(false).catch((error: BusinessError): void => {
      console.error('disable resident focus failed: ' + error.message);
    });
    this.context.hideAbility().catch((error: BusinessError): void => {
      console.error('hide resident host failed: ' + error.message);
    });
  }
}
