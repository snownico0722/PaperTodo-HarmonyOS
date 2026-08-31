import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { CAPSULE_HEIGHT, CAPSULE_WIDTH, PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaperAbility';

export default class PaperAbility extends UIAbility {
  private paperId: string = '';
  private storage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    this.storage = new LocalStorage({ paperId: this.paperId });
    AppStorage.setOrCreate<number>('systemColorMode', this.context.config.colorMode ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const nextId: string = this.readPaperId(want);
    if (nextId.length > 0) {
      this.paperId = nextId;
    }

    const command: string = this.readCommand(want);
    if (command === 'hide') {
      PaperStore.setPaperVisible(this.paperId, false);
      this.context.terminateSelf();
      return;
    }
    if (command === 'delete') {
      PaperStore.deletePaper(this.paperId);
      this.context.terminateSelf();
      return;
    }
    if (command === 'close') {
      this.context.terminateSelf();
      return;
    }

    PaperStore.setPaperVisible(this.paperId, true);
    this.context.showAbility().catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'showAbility failed: %{public}s', error.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Paper', this.storage, (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load Paper page: %{public}s', JSON.stringify(err));
        return;
      }
      this.configureMainWindow(windowStage);
    });
  }

  onDestroy(): void {
    if (this.paperId.length > 0) {
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, false);
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode !== undefined) {
      AppStorage.setOrCreate<number>('systemColorMode', config.colorMode);
    }
  }

  private configureMainWindow(windowStage: window.WindowStage): void {
    const paper: PaperData | null = PaperStore.getPaper(this.paperId);
    if (paper === null) {
      this.context.terminateSelf();
      return;
    }

    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      AppStorage.setOrCreate<window.Window>('paperWindow:' + this.paperId, mainWindow);
      AppStorage.setOrCreate<boolean>('paperOpen:' + this.paperId, true);

      const width: number = paper.isCollapsed ? CAPSULE_WIDTH : paper.width;
      const height: number = paper.isCollapsed ? CAPSULE_HEIGHT : paper.height;
      mainWindow.resize(Math.round(width), Math.round(height));
      mainWindow.moveWindowTo(Math.round(paper.x), Math.round(paper.y));
      mainWindow.setWindowDecorVisible(false);
      mainWindow.setWindowTitleButtonVisible(false, false, false);
      mainWindow.setWindowTopmost(paper.alwaysOnTop).catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'configure window failed: %{public}s', String(error));
    }
  }

  private readPaperId(want: Want): string {
    if (!want.parameters) {
      return '';
    }
    const raw: Object | undefined = want.parameters.paperId;
    if (raw === undefined || raw === null) {
      return '';
    }
    return String(raw);
  }

  private readCommand(want: Want): string {
    if (!want.parameters) {
      return 'show';
    }
    const raw: Object | undefined = want.parameters.paperCommand;
    if (raw === undefined || raw === null) {
      return 'show';
    }
    return String(raw);
  }
}
