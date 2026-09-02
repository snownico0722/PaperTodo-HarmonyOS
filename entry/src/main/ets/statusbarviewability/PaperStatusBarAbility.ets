import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { PaperStore } from '../common/PaperStore';

export default class PaperStatusBarAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    PaperStore.initialize(this.context);
    PaperStore.refreshSystemLanguage();
    try {
      session.loadContent('pages/StatusBarPage');
    } catch (error) {
      console.error('load PaperTodo status bar page failed: ' + String(error));
    }
  }
}
