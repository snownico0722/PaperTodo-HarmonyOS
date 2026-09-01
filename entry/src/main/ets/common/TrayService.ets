import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { image } from '@kit.ImageKit';

export const TRAY_MENU_NEW_TODO: string = 'paperTodo.newTodo';
export const TRAY_MENU_NEW_NOTE: string = 'paperTodo.newNote';
export const TRAY_MENU_TOGGLE_ALL: string = 'paperTodo.toggleAll';
export const TRAY_MENU_SETTINGS: string = 'paperTodo.settings';

export class TrayService {
  private static installed: boolean = false;
  private static installPromise: Promise<boolean> | null = null;

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

  private static async installOnce(context: common.Context): Promise<boolean> {
    if (deviceInfo.deviceType !== '2in1' ||
      !canIUse('SystemCapability.PCService.StatusBarManager')) {
      AppStorage.setOrCreate<string>('statusBarStatus', 'unsupported');
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
        height: 420,
        moduleName: 'entry'
      };
      const actionTodo: statusBarManager.StatusBarMenuAction = {
        abilityName: 'TrayResidentAbility',
        moduleName: 'entry',
        notifyOnly: true,
        menuCode: TRAY_MENU_NEW_TODO
      };
      const actionNote: statusBarManager.StatusBarMenuAction = {
        abilityName: 'TrayResidentAbility',
        moduleName: 'entry',
        notifyOnly: true,
        menuCode: TRAY_MENU_NEW_NOTE
      };
      const actionToggle: statusBarManager.StatusBarMenuAction = {
        abilityName: 'TrayResidentAbility',
        moduleName: 'entry',
        notifyOnly: true,
        menuCode: TRAY_MENU_TOGGLE_ALL
      };
      const actionSettings: statusBarManager.StatusBarMenuAction = {
        abilityName: 'TrayResidentAbility',
        moduleName: 'entry',
        notifyOnly: true,
        menuCode: TRAY_MENU_SETTINGS
      };
      const mainGroup: statusBarManager.StatusBarGroupMenu = [
        { title: '新建待办', menuAction: actionTodo },
        { title: '新建笔记', menuAction: actionNote },
        { title: '显示 / 隐藏全部', menuAction: actionToggle }
      ];
      const settingsGroup: statusBarManager.StatusBarGroupMenu = [
        { title: '设置', menuAction: actionSettings }
      ];
      const item: statusBarManager.StatusBarItem = {
        icons: icons,
        quickOperation: quickOperation,
        statusBarGroupMenu: [mainGroup, settingsGroup],
        hoverTips: 'PaperTodo'
      };
      await new Promise<void>((resolve: () => void, reject: (reason: BusinessError) => void): void => {
        statusBarManager.addToStatusBar(context, item, (error: BusinessError): void => {
          if (error !== undefined && error !== null && error.code !== 0 && error.code !== 1010710003) {
            reject(error);
            return;
          }
          resolve();
        });
      });
      AppStorage.setOrCreate<string>('statusBarStatus', 'active');
      return true;
    } catch (error) {
      AppStorage.setOrCreate<string>('statusBarStatus', 'error: ' + String(error));
      console.error('install status bar item failed: ' + String(error));
      return false;
    }
  }
}
