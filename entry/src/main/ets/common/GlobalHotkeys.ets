import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from './Models';
import { PaperStore } from './PaperStore';

const ENABLED_KEY: string = 'globalHotkeysEnabled';
const STATUS_KEY: string = 'globalHotkeyStatus';

const STATUS_IDLE: string = 'idle';
const STATUS_ACTIVE: string = 'active';
const STATUS_CONFLICT: string = 'conflict';
const STATUS_UNSUPPORTED: string = 'unsupported';
const STATUS_ERROR: string = 'error';

const ERROR_UNSUPPORTED: number = 801;
const ERROR_SYSTEM_OCCUPIED: number = 4200002;
const ERROR_OTHER_OCCUPIED: number = 4200003;

class GlobalHotkeysImpl {
  private abilityContext: common.UIAbilityContext | null = null;
  private enabled: boolean = false;

  private readonly showOptions: inputConsumer.HotkeyOptions = {
    preKeys: [KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_ALT_LEFT],
    finalKey: KeyCode.KEYCODE_P,
    isRepeat: false
  };
  private readonly todoOptions: inputConsumer.HotkeyOptions = {
    preKeys: [KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_ALT_LEFT],
    finalKey: KeyCode.KEYCODE_T,
    isRepeat: false
  };
  private readonly noteOptions: inputConsumer.HotkeyOptions = {
    preKeys: [KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_ALT_LEFT],
    finalKey: KeyCode.KEYCODE_N,
    isRepeat: false
  };

  private readonly showCallback: (options: inputConsumer.HotkeyOptions) => void =
    (_options: inputConsumer.HotkeyOptions): void => this.showManager();
  private readonly todoCallback: (options: inputConsumer.HotkeyOptions) => void =
    (_options: inputConsumer.HotkeyOptions): void => this.createPaper(PAPER_TYPE_TODO);
  private readonly noteCallback: (options: inputConsumer.HotkeyOptions) => void =
    (_options: inputConsumer.HotkeyOptions): void => this.createPaper(PAPER_TYPE_NOTE);

  private showRegistered: boolean = false;
  private todoRegistered: boolean = false;
  private noteRegistered: boolean = false;

  configure(context: common.UIAbilityContext): void {
    this.abilityContext = context;
    const enabled: boolean | undefined = AppStorage.get<boolean>(ENABLED_KEY);
    if (enabled === undefined) {
      AppStorage.setOrCreate<boolean>(ENABLED_KEY, false);
    }
    if (AppStorage.get<string>(STATUS_KEY) === undefined) {
      AppStorage.setOrCreate<string>(STATUS_KEY, STATUS_IDLE);
    }
    this.enabled = enabled === true;
    if (this.enabled) {
      this.registerAll();
    } else {
      const removed: boolean = this.unregisterAll();
      this.publishStatus(removed ? STATUS_IDLE : STATUS_ERROR);
    }
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    AppStorage.setOrCreate<boolean>(ENABLED_KEY, enabled);
    if (!enabled) {
      const removed: boolean = this.unregisterAll();
      this.publishStatus(removed ? STATUS_IDLE : STATUS_ERROR);
      return;
    }
    if (this.abilityContext === null) {
      this.publishStatus(STATUS_ERROR);
      return;
    }
    this.registerAll();
  }

  shutdown(): void {
    this.enabled = false;
    this.abilityContext = null;
    const removed: boolean = this.unregisterAll();
    this.publishStatus(removed ? STATUS_IDLE : STATUS_ERROR);
  }

  private registerAll(): void {
    if (this.showRegistered && this.todoRegistered && this.noteRegistered) {
      this.publishStatus(STATUS_ACTIVE);
      return;
    }
    if (!this.unregisterAll()) {
      this.publishStatus(STATUS_ERROR);
      return;
    }

    try {
      inputConsumer.on('hotkeyChange', this.showOptions, this.showCallback);
      this.showRegistered = true;
      inputConsumer.on('hotkeyChange', this.todoOptions, this.todoCallback);
      this.todoRegistered = true;
      inputConsumer.on('hotkeyChange', this.noteOptions, this.noteCallback);
      this.noteRegistered = true;
      this.publishStatus(STATUS_ACTIVE);
    } catch (error) {
      const status: string = this.statusForError(error as BusinessError);
      const removed: boolean = this.unregisterAll();
      this.publishStatus(removed ? status : STATUS_ERROR);
    }
  }

  private unregisterAll(): boolean {
    let removed: boolean = true;
    if (this.noteRegistered) {
      try {
        inputConsumer.off('hotkeyChange', this.noteOptions, this.noteCallback);
        this.noteRegistered = false;
      } catch (error) {
        removed = false;
      }
    }
    if (this.todoRegistered) {
      try {
        inputConsumer.off('hotkeyChange', this.todoOptions, this.todoCallback);
        this.todoRegistered = false;
      } catch (error) {
        removed = false;
      }
    }
    if (this.showRegistered) {
      try {
        inputConsumer.off('hotkeyChange', this.showOptions, this.showCallback);
        this.showRegistered = false;
      } catch (error) {
        removed = false;
      }
    }
    return removed;
  }

  private statusForError(error: BusinessError): string {
    if (error.code === ERROR_UNSUPPORTED) {
      return STATUS_UNSUPPORTED;
    }
    if (error.code === ERROR_SYSTEM_OCCUPIED || error.code === ERROR_OTHER_OCCUPIED) {
      return STATUS_CONFLICT;
    }
    return STATUS_ERROR;
  }

  private showManager(): void {
    const context: common.UIAbilityContext | null = this.abilityContext;
    if (!this.enabled) {
      return;
    }
    if (context === null) {
      this.publishStatus(STATUS_ERROR);
      return;
    }
    this.bringManagerToFront(context)
      .then((): void => {
        if (this.isActiveContext(context)) {
          this.publishStatus(STATUS_ACTIVE);
        }
      })
      .catch((_error: BusinessError): void => {
        if (this.isActiveContext(context)) {
          this.publishStatus(STATUS_ERROR);
        }
      });
  }

  private createPaper(type: string): void {
    const context: common.UIAbilityContext | null = this.abilityContext;
    if (!this.enabled) {
      return;
    }
    if (context === null) {
      this.publishStatus(STATUS_ERROR);
      return;
    }
    this.bringManagerToFront(context)
      .then((): void => {
        if (this.isActiveContext(context)) {
          this.createAndStartPaper(context, type);
        }
      })
      .catch((_error: BusinessError): void => {
        if (this.isActiveContext(context)) {
          this.publishStatus(STATUS_ERROR);
        }
      });
  }

  private createAndStartPaper(context: common.UIAbilityContext, type: string): void {
    const paper: PaperData | null = PaperStore.createPaper(type);
    if (paper === null) {
      this.publishStatus(STATUS_ERROR);
      return;
    }
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paper.id,
        paperCommand: 'show'
      }
    };
    context.startAbility(want)
      .then((): void => {
        if (this.isActiveContext(context)) {
          this.publishStatus(STATUS_ACTIVE);
        }
      })
      .catch((_error: BusinessError): void => {
        PaperStore.deletePaper(paper.id);
        if (this.isActiveContext(context)) {
          this.publishStatus(STATUS_ERROR);
        }
      });
  }

  private bringManagerToFront(context: common.UIAbilityContext): Promise<void> {
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'EntryAbility'
    };
    try {
      const mainWindow = context.windowStage.getMainWindowSync();
      return mainWindow.restore()
        .catch((_restoreError: BusinessError): Promise<void> => mainWindow.showWindow())
        .catch((_showError: BusinessError): Promise<void> => context.startAbility(want));
    } catch (_error) {
      try {
        return context.startAbility(want);
      } catch (startError) {
        return Promise.reject<void>(startError);
      }
    }
  }

  private isActiveContext(context: common.UIAbilityContext): boolean {
    return this.enabled && this.abilityContext === context;
  }

  private publishStatus(status: string): void {
    AppStorage.setOrCreate<string>(STATUS_KEY, status);
  }
}

export const GlobalHotkeys: GlobalHotkeysImpl = new GlobalHotkeysImpl();
