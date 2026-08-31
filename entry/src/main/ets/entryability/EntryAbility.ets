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

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.showAbility().catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'show manager failed: %{public}s', error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Window stage created');

    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.restoreVisiblePapers();
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

  private restoreVisiblePapers(): void {
    const papers: PaperData[] = PaperStore.listPapers();
    let started: number = 0;
    for (let i: number = 0; i < papers.length; i++) {
      if (!papers[i].isVisible) {
        continue;
      }
      started += 1;
      this.startPaper(papers[i].id);
    }

    if (deviceInfo.deviceType === '2in1' && started > 0) {
      setTimeout((): void => {
        this.context.hideAbility().catch((error: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'hide manager failed: %{public}s', error.message);
        });
      }, 300);
    }
  }

  private startPaper(paperId: string): void {
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId
      }
    };
    this.context.startAbility(want).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'start PaperAbility failed: %{public}s', error.message);
    });
  }
}
