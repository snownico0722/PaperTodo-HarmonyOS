import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { image } from '@kit.ImageKit';
import {
  PAPER_TYPE_NOTE,
  PaperData,
  UI_LANGUAGE_SYSTEM,
  UI_LANGUAGE_ZH_CN
} from './Models';
import { PaperStore } from './PaperStore';
import { effectivePaperTitle } from './PaperTitles';
import { tForSystem } from './Strings';

export const TRAY_MENU_NEW_TODO: string = 'paperTodo.newTodo';
export const TRAY_MENU_NEW_NOTE: string = 'paperTodo.newNote';
export const TRAY_MENU_TOGGLE_ALL: string = 'paperTodo.toggleAll';
export const TRAY_MENU_SETTINGS: string = 'paperTodo.settings';
export const TRAY_MENU_EXIT: string = 'paperTodo.exit';
export const TRAY_MENU_PAPER_PREFIX: string = 'paperTodo.paper.';
export const TRAY_MENU_PAPER_OVERFLOW: string = 'paperTodo.paperOverflow';

export class TrayService {
  private static installed: boolean = false;
  private static installPromise: Promise<boolean> | null = null;
  private static menuRefreshPromise: Promise<boolean> | null = null;
  private static menuRefreshQueued: boolean = false;
  private static lastMenuSignature: string = '';
  private static readonly INSTALL_ATTEMPTS: number = 4;
  private static readonly INSTALL_CALLBACK_TIMEOUT_MS: number = 9000;
  private static readonly REMOVE_CALLBACK_TIMEOUT_MS: number = 4000;
  private static readonly MENU_UPDATE_ATTEMPTS: number = 4;
  private static readonly MENU_UPDATE_CALLBACK_TIMEOUT_MS: number = 2500;
  // The status bar API rejects a submenu with more than 20 entries (1010710002).
  // When the list overflows, reserve the final entry for a stable remainder summary.
  private static readonly STATUS_BAR_SUBMENU_LIMIT: number = 20;

  static install(context: common.Context): Promise<boolean> {
    if (TrayService.installed) {
      return Promise.resolve(true);
    }
    if (TrayService.installPromise !== null) {
      return TrayService.installPromise;
    }
    const pending: Promise<boolean> = TrayService.installOnce(context);
    TrayService.installPromise = pending;
    pending.then((success: boolean): void => {
      TrayService.installed = success;
      TrayService.installPromise = null;
    }).catch((_error: Error): void => {
      TrayService.installPromise = null;
    });
    return pending;
  }

  static refreshMenu(context: common.Context): Promise<boolean> {
    TrayService.menuRefreshQueued = true;
    if (TrayService.menuRefreshPromise !== null) {
      return TrayService.menuRefreshPromise;
    }
    const pending: Promise<boolean> = TrayService.drainMenuRefreshes(context);
    TrayService.menuRefreshPromise = pending;
    pending.then((_success: boolean): void => {
      TrayService.menuRefreshPromise = null;
    }).catch((_error: Error): void => {
      TrayService.menuRefreshPromise = null;
    });
    return pending;
  }

  static async remove(context: common.Context): Promise<boolean> {
    if (!canIUse('SystemCapability.PCService.StatusBarManager')) {
      return false;
    }
    let lastResult: StatusBarInstallResult = { code: -1, message: 'not attempted' };
    for (let attempt: number = 0; attempt < 3; attempt++) {
      lastResult = await TrayService.removeOnce(context);
      console.info('PaperTodo removeFromStatusBar attempt=' + (attempt + 1).toString() + ', code=' +
        lastResult.code.toString() + ', message=' + lastResult.message);
      if (lastResult.code === 0) {
        TrayService.installed = false;
        TrayService.lastMenuSignature = '';
        AppStorage.setOrCreate<string>('statusBarStatus', 'removed');
        return true;
      }
      if (lastResult.code !== 1010710003 || attempt >= 2) {
        break;
      }
      await TrayService.delay(600 * Math.pow(2, attempt));
    }
    AppStorage.setOrCreate<string>('statusBarStatus', 'remove error: ' + lastResult.code.toString() + ': ' +
      lastResult.message);
    return false;
  }

  private static async installOnce(context: common.Context): Promise<boolean> {
    const supported: boolean = canIUse('SystemCapability.PCService.StatusBarManager');
    console.info('PaperTodo status bar probe: deviceType=' + deviceInfo.deviceType +
      ', supported=' + supported.toString());
    if (!supported) {
      AppStorage.setOrCreate<string>('statusBarStatus', 'unsupported: ' + deviceInfo.deviceType);
      return false;
    }
    try {
      const whiteData: Uint8Array = context.resourceManager.getRawFileContentSync('statusbar_white.png');
      const blackData: Uint8Array = context.resourceManager.getRawFileContentSync('statusbar_black.png');
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
        height: 272,
        moduleName: 'entry'
      };
      const menu: TrayMenuSnapshot = TrayService.buildMenuSnapshot();
      const item: statusBarManager.StatusBarItem = {
        icons: icons,
        quickOperation: quickOperation,
        statusBarGroupMenu: menu.groups,
        hoverTips: 'PaperTodo'
      };
      const installConfirmed: boolean = await TrayService.addWithRateLimitRetry(context, item);
      TrayService.lastMenuSignature = menu.signature;
      AppStorage.setOrCreate<string>('statusBarStatus', installConfirmed ? 'active' : 'uncertain: callback timeout');
      return true;
    } catch (error) {
      AppStorage.setOrCreate<string>('statusBarStatus', 'error: ' + String(error));
      console.error('install status bar item failed: ' + String(error));
      return false;
    }
  }

  private static async drainMenuRefreshes(context: common.Context): Promise<boolean> {
    let success: boolean = true;
    while (TrayService.menuRefreshQueued) {
      TrayService.menuRefreshQueued = false;
      success = await TrayService.refreshMenuOnce(context);
    }
    return success;
  }

  private static async refreshMenuOnce(context: common.Context): Promise<boolean> {
    const supported: boolean = canIUse('SystemCapability.PCService.StatusBarManager');
    if (!supported) {
      return false;
    }
    if (TrayService.installPromise !== null) {
      await TrayService.installPromise;
    }
    if (!TrayService.installed) {
      console.warn('PaperTodo skips status bar menu refresh before installation');
      return false;
    }
    const menu: TrayMenuSnapshot = TrayService.buildMenuSnapshot();
    if (menu.signature === TrayService.lastMenuSignature) {
      return true;
    }
    try {
      await TrayService.updateMenuWithRateLimitRetry(context, menu.groups);
      TrayService.lastMenuSignature = menu.signature;
      AppStorage.setOrCreate<string>('statusBarMenuStatus', 'active');
      return true;
    } catch (error) {
      AppStorage.setOrCreate<string>('statusBarMenuStatus', 'error: ' + String(error));
      console.error('refresh status bar menu failed: ' + String(error));
      return false;
    }
  }

  private static buildMenuSnapshot(): TrayMenuSnapshot {
    const uiLanguage: string = AppStorage.get<string>('uiLanguage') ?? UI_LANGUAGE_SYSTEM;
    const systemLanguage: string = AppStorage.get<string>('systemLanguage') ?? UI_LANGUAGE_ZH_CN;
    const newTodoTitle: string = tForSystem(uiLanguage, systemLanguage, 'tray.newTodo');
    const newNoteTitle: string = tForSystem(uiLanguage, systemLanguage, 'tray.newNote');
    const toggleAllTitle: string = tForSystem(uiLanguage, systemLanguage, 'tray.toggleAll');
    const settingsTitle: string = tForSystem(uiLanguage, systemLanguage, 'action.settings');
    const exitTitle: string = tForSystem(uiLanguage, systemLanguage, 'action.exit');
    const papersTitle: string = tForSystem(uiLanguage, systemLanguage, 'tab.papers');
    const mainGroup: statusBarManager.StatusBarGroupMenu = [
      { title: newTodoTitle, menuAction: TrayService.menuAction(TRAY_MENU_NEW_TODO) },
      { title: newNoteTitle, menuAction: TrayService.menuAction(TRAY_MENU_NEW_NOTE) },
      { title: toggleAllTitle, menuAction: TrayService.menuAction(TRAY_MENU_TOGGLE_ALL) }
    ];
    const settingsGroup: statusBarManager.StatusBarGroupMenu = [
      { title: settingsTitle, menuAction: TrayService.menuAction(TRAY_MENU_SETTINGS) },
      { title: exitTitle, menuAction: TrayService.menuAction(TRAY_MENU_EXIT) }
    ];
    const papers: PaperData[] = PaperStore.listPapers();
    const paperSubMenu: statusBarManager.StatusBarSubMenuItem[] = [];
    const paperSignature: string[] = [];
    const directPaperLimit: number = TrayService.STATUS_BAR_SUBMENU_LIMIT - 1;
    const directPaperCount: number = Math.min(papers.length, directPaperLimit);
    for (let i: number = 0; i < directPaperCount; i++) {
      const paper: PaperData = papers[i];
      const title: string = effectivePaperTitle(paper, papers, uiLanguage, systemLanguage);
      const visibleMark: string = paper.isVisible ? '☑' : '☐';
      const typeMark: string = paper.type === PAPER_TYPE_NOTE ? '✎' : '✓';
      const menuCode: string = TRAY_MENU_PAPER_PREFIX + encodeURIComponent(paper.id);
      const subTitle: string = visibleMark + '  ' + typeMark + '  ' + title;
      paperSubMenu.push({
        subTitle: subTitle,
        menuAction: TrayService.menuAction(menuCode)
      });
      paperSignature.push(menuCode, subTitle);
    }
    if (papers.length > directPaperCount) {
      const remaining: number = papers.length - directPaperCount;
      const overflowTitle: string = '⋯ ' + papersTitle + ' (+' + remaining.toString() + ')';
      paperSubMenu.push({
        subTitle: overflowTitle,
        menuAction: TrayService.menuAction(TRAY_MENU_PAPER_OVERFLOW)
      });
      paperSignature.push(TRAY_MENU_PAPER_OVERFLOW, overflowTitle);
    }
    const groups: statusBarManager.StatusBarGroupMenu[] = [mainGroup];
    if (paperSubMenu.length > 0) {
      groups.push([{
        title: papersTitle + ' (' + papers.length.toString() + ')',
        subMenu: paperSubMenu
      }]);
    }
    groups.push(settingsGroup);
    return {
      groups: groups,
      signature: newTodoTitle + '\u0000' + newNoteTitle + '\u0000' + toggleAllTitle + '\u0000' +
        papersTitle + '\u0000' + paperSignature.join('\u0000') + '\u0000' + settingsTitle + '\u0000' + exitTitle
    };
  }

  private static menuAction(menuCode: string): statusBarManager.StatusBarMenuAction {
    return {
      abilityName: 'EntryAbility',
      moduleName: 'entry',
      notifyOnly: true,
      menuCode: menuCode
    };
  }

  private static async addWithRateLimitRetry(context: common.Context,
    item: statusBarManager.StatusBarItem): Promise<boolean> {
    let lastCode: number = 0;
    let lastMessage: string = '';
    for (let attempt: number = 0; attempt < TrayService.INSTALL_ATTEMPTS; attempt++) {
      const result: StatusBarInstallResult = await TrayService.addOnce(context, item);
      console.info('PaperTodo addToStatusBar attempt=' + (attempt + 1).toString() + ', code=' +
        result.code.toString() + ', message=' + result.message);
      lastCode = result.code;
      lastMessage = result.message;
      if (result.code === 0) {
        return true;
      }
      // A late callback does not prove that the system rejected the item. Treat
      // the timeout as indeterminate and let the attached Resident handshake
      // decide whether the status-bar item actually exists.
      if (result.code === -1) {
        return false;
      }
      if (result.code !== 1010710003 || attempt + 1 >= TrayService.INSTALL_ATTEMPTS) {
        break;
      }
      AppStorage.setOrCreate<string>('statusBarStatus', 'retrying: ' + (attempt + 1).toString());
      await TrayService.delay(600 * Math.pow(2, attempt));
    }
    throw new Error('addToStatusBar failed (' + lastCode.toString() + '): ' + lastMessage);
  }

  private static addOnce(context: common.Context,
    item: statusBarManager.StatusBarItem): Promise<StatusBarInstallResult> {
    return new Promise<StatusBarInstallResult>((resolve: (result: StatusBarInstallResult) => void): void => {
      let settled: boolean = false;
      const finish = (result: StatusBarInstallResult): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeoutId);
        resolve(result);
      };
      const timeoutId: number = setTimeout((): void => {
        finish({ code: -1, message: 'addToStatusBar callback timed out' });
      }, TrayService.INSTALL_CALLBACK_TIMEOUT_MS);
      statusBarManager.addToStatusBar(context, item, (error: BusinessError): void => {
        if (error === undefined || error === null || error.code === 0) {
          finish({ code: 0, message: '' });
          return;
        }
        finish({ code: error.code, message: error.message });
      });
    });
  }

  private static removeOnce(context: common.Context): Promise<StatusBarInstallResult> {
    return new Promise<StatusBarInstallResult>((resolve: (result: StatusBarInstallResult) => void): void => {
      let settled: boolean = false;
      const finish = (result: StatusBarInstallResult): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeoutId);
        resolve(result);
      };
      const timeoutId: number = setTimeout((): void => {
        finish({ code: -1, message: 'removeFromStatusBar callback timed out' });
      }, TrayService.REMOVE_CALLBACK_TIMEOUT_MS);
      statusBarManager.removeFromStatusBar(context, (error: BusinessError): void => {
        if (error === undefined || error === null || error.code === 0) {
          finish({ code: 0, message: '' });
          return;
        }
        finish({ code: error.code, message: error.message });
      });
    });
  }

  private static async updateMenuWithRateLimitRetry(context: common.Context,
    groups: statusBarManager.StatusBarGroupMenu[]): Promise<void> {
    let lastCode: number = 0;
    let lastMessage: string = '';
    for (let attempt: number = 0; attempt < TrayService.MENU_UPDATE_ATTEMPTS; attempt++) {
      const result: StatusBarInstallResult = await TrayService.updateMenuOnce(context, groups);
      console.info('PaperTodo updateStatusBarMenu attempt=' + (attempt + 1).toString() + ', code=' +
        result.code.toString() + ', message=' + result.message);
      lastCode = result.code;
      lastMessage = result.message;
      if (result.code === 0) {
        return;
      }
      if (result.code !== 1010710003 || attempt + 1 >= TrayService.MENU_UPDATE_ATTEMPTS) {
        break;
      }
      await TrayService.delay(300 * Math.pow(2, attempt));
    }
    throw new Error('updateStatusBarMenu failed (' + lastCode.toString() + '): ' + lastMessage);
  }

  private static updateMenuOnce(context: common.Context,
    groups: statusBarManager.StatusBarGroupMenu[]): Promise<StatusBarInstallResult> {
    return new Promise<StatusBarInstallResult>((resolve: (result: StatusBarInstallResult) => void): void => {
      let settled: boolean = false;
      const finish = (result: StatusBarInstallResult): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeoutId);
        resolve(result);
      };
      const timeoutId: number = setTimeout((): void => {
        finish({ code: -1, message: 'updateStatusBarMenu callback timed out' });
      }, TrayService.MENU_UPDATE_CALLBACK_TIMEOUT_MS);
      statusBarManager.updateStatusBarMenu(context, groups, (error: BusinessError): void => {
        if (error === undefined || error === null || error.code === 0) {
          finish({ code: 0, message: '' });
          return;
        }
        finish({ code: error.code, message: error.message });
      });
    });
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }
}

interface StatusBarInstallResult {
  code: number;
  message: string;
}

interface TrayMenuSnapshot {
  groups: statusBarManager.StatusBarGroupMenu[];
  signature: string;
}
