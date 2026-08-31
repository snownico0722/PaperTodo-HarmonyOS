import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class PaperStatusBarAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    session.loadContent('pages/StatusBarPage', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('PaperTodo status bar page load failed: ' + error.message);
      }
    });
  }
}
