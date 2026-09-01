import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { PaperStore } from '../common/PaperStore';

interface EdgeCapsuleStorageData {
  paperId: string;
}

export default class EdgeCapsuleAbility extends UIAbility {
  private paperId: string = '';
  private storage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
    this.paperId = this.readPaperId(want);
    const data: EdgeCapsuleStorageData = { paperId: this.paperId };
    this.storage = new LocalStorage(data);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.readCommand(want) === 'close') {
      this.context.terminateSelf();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/EdgeCapsule', this.storage, (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load edge capsule failed: ' + error.message);
        this.context.terminateSelf();
      }
    });
  }

  private readPaperId(want: Want): string {
    if (want.parameters === undefined) {
      return '';
    }
    const value: Object | undefined = want.parameters.paperId;
    return value === undefined || value === null ? '' : String(value);
  }

  private readCommand(want: Want): string {
    if (want.parameters === undefined) {
      return 'show';
    }
    const value: Object | undefined = want.parameters.capsuleCommand;
    return value === undefined || value === null ? 'show' : String(value);
  }
}
