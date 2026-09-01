import { StatusBarViewExtensionAbility } from '@kit.StatusBarExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';

export default class PaperStatusBarAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    try {
      session.loadContent('pages/StatusBarPage');
    } catch (error) {
      console.error('PaperTodo status bar page load failed: ' + String(error));
    }
  }
}
