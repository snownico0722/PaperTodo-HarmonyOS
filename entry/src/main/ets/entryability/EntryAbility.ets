import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperTodo';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.showManagerWindow();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Window stage created');
    try {
      this.mainWindow = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'get manager window failed: %{public}s', String(error));
    }

    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.restoreVisiblePapers().catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore visible papers failed: %{public}s', error.message);
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
    this.mainWindow = null;
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async restoreVisiblePapers(): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const starts: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      if (!papers[i].isVisible) {
        continue;
      }
      starts.push(this.startPaper(papers[i].id));
    }

    if (starts.length === 0) {
      return;
    }

    const results: boolean[] = await Promise.all(starts);
    let succeeded: number = 0;
    for (let i: number = 0; i < results.length; i++) {
      if (results[i]) {
        succeeded += 1;
      }
    }

    // showAbility/hideAbility require the special status-bar launch mode. PaperTodo
    // instead keeps a normal singleton manager window: minimize it after papers start,
    // and restore the same window via showWindow when the app icon is invoked again.
    if (deviceInfo.deviceType === '2in1' && succeeded > 0 && this.mainWindow !== null) {
      try {
        await this.mainWindow.minimize();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'minimize manager failed: %{public}s', String(error));
      }
    }
  }

  private async startPaper(paperId: string): Promise<boolean> {
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId
      }
    };
    try {
      await this.context.startAbility(want);
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'start PaperAbility failed: %{public}s', String(error));
      return false;
    }
  }

  private showManagerWindow(): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      this.mainWindow.showWindow().catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'show manager window failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'show manager window threw: %{public}s', String(error));
    }
  }
}
