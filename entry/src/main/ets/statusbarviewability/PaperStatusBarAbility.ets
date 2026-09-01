import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';

export default class PaperStatusBarAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    try {
      session.loadContent('pages/StatusBarPage');
    } catch (error) {
      console.error('load PaperTodo status bar page failed: ' + String(error));
    }
  }
}
