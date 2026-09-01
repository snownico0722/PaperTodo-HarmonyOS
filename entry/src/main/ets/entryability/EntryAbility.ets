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
import { GlobalHotkeys } from '../common/GlobalHotkeys';
import { PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperTodo';

export default class EntryAbility extends UIAbility {
  private managerMinimizeTimer: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.clearManagerMinimizeTimer();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Manager brought to foreground');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.clearManagerMinimizeTimer();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Window stage created');
    GlobalHotkeys.configure(this.context);

    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.restoreVisiblePapers(windowStage);
    });
  }

  onBackground(): void {
    PaperStore.flushNow();
  }

  onDestroy(): void {
    this.clearManagerMinimizeTimer();
    GlobalHotkeys.shutdown();
    PaperStore.flushNow();
  }

  onConfigurationUpdate(config: Configuration): void {
    PaperStore.refreshSystemLanguage();
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private restoreVisiblePapers(windowStage: window.WindowStage): void {
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
      this.managerMinimizeTimer = setTimeout((): void => {
        this.managerMinimizeTimer = -1;
        try {
          windowStage.getMainWindowSync().minimize().catch((error: BusinessError): void => {
            hilog.warn(DOMAIN, TAG, 'minimize manager failed: %{public}s', error.message);
          });
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'get manager window failed: %{public}s', String(error));
        }
      }, 300);
    }
  }

  private clearManagerMinimizeTimer(): void {
    if (this.managerMinimizeTimer >= 0) {
      clearTimeout(this.managerMinimizeTimer);
      this.managerMinimizeTimer = -1;
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
