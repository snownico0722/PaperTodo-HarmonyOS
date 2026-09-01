import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { PaperStore } from '../common/PaperStore';

export default class MasterCapsuleAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PaperStore.initialize(this.context);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters !== undefined && String(want.parameters.capsuleCommand ?? '') === 'close') {
      this.context.terminateSelf();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/MasterCapsule', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load master capsule failed: ' + error.message);
        this.context.terminateSelf();
      }
    });
  }
}
