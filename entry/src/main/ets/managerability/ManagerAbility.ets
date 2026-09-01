import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { PaperStore } from '../common/PaperStore';

export default class ManagerAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      this.mainWindow.showWindow().catch((error: BusinessError): void => {
        console.error('show manager failed: ' + error.message);
      });
    } catch (error) {
      console.error('show manager threw: ' + String(error));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindow = windowStage.getMainWindowSync();
    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        console.error('load manager failed: ' + JSON.stringify(err));
      }
    });
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.mainWindow = null;
  }
}
