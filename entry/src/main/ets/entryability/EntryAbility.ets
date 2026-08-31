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
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Window stage created');

    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.restoreVisiblePapers().catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'restore visible papers failed: %{public}s', error.message);
      });
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    PaperStore.flushNow();
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private async restoreVisiblePapers(): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const starts: Promise<void>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      if (!papers[i].isVisible) {
        continue;
      }
      starts.push(this.startPaper(papers[i].id));
    }

    if (starts.length === 0) {
      return;
    }

    await Promise.all(starts);

    // hideAbility/showAbility require the app to be attached to a system status-bar
    // item. PaperTodo does not use that launch mode. On 2in1, close only the manager
    // UIAbility after all paper abilities have started; the specified PaperAbility
    // instances continue to live independently.
    if (deviceInfo.deviceType === '2in1') {
      try {
        await this.context.terminateSelf();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'terminate manager failed: %{public}s', String(error));
      }
    }
  }

  private async startPaper(paperId: string): Promise<void> {
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
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'start PaperAbility failed: %{public}s', String(error));
    }
  }
}
