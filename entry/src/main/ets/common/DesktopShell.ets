import { common, contextConstant, StartOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from './Models';
import { PaperStore } from './PaperStore';

export const PAPER_COMMAND_SHOW: string = 'show';
export const PAPER_COMMAND_HIDE: string = 'hide';
export const PAPER_COMMAND_CLOSE: string = 'close';
export const PAPER_COMMAND_DELETE: string = 'delete';
export const PAPER_COMMAND_EXPAND: string = 'expand';
export const PAPER_COMMAND_COLLAPSE: string = 'collapse';

export class DesktopShell {
  static readonly BUNDLE_NAME: string = 'com.papertodo.app';

  static async startPaper(context: common.UIAbilityContext, paperId: string,
    command: string = PAPER_COMMAND_SHOW): Promise<boolean> {
    const want: Want = {
      bundleName: DesktopShell.BUNDLE_NAME,
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId,
        paperCommand: command
      }
    };
    try {
      const options: StartOptions = { hideStartWindow: true };
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      console.error('start paper failed: ' + String(error));
      return false;
    }
  }

  static async startEdge(context: common.UIAbilityContext, paperId: string,
    command: string = PAPER_COMMAND_SHOW): Promise<boolean> {
    const want: Want = {
      bundleName: DesktopShell.BUNDLE_NAME,
      moduleName: 'entry',
      abilityName: 'EdgeCapsuleAbility',
      parameters: {
        paperId: paperId,
        capsuleCommand: command
      }
    };
    try {
      const options: StartOptions = { hideStartWindow: true };
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      console.error('start edge capsule failed: ' + String(error));
      return false;
    }
  }

  static async startMaster(context: common.UIAbilityContext,
    command: string = PAPER_COMMAND_SHOW): Promise<boolean> {
    const want: Want = {
      bundleName: DesktopShell.BUNDLE_NAME,
      moduleName: 'entry',
      abilityName: 'MasterCapsuleAbility',
      parameters: {
        capsuleCommand: command
      }
    };
    try {
      const options: StartOptions = { hideStartWindow: true };
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      console.error('start master capsule failed: ' + String(error));
      return false;
    }
  }

  static async openSettings(context: common.UIAbilityContext): Promise<boolean> {
    const want: Want = {
      bundleName: DesktopShell.BUNDLE_NAME,
      moduleName: 'entry',
      abilityName: 'ManagerAbility'
    };
    try {
      const options: StartOptions = { hideStartWindow: true };
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      console.error('open settings failed: ' + String(error));
      return false;
    }
  }

  static async startResident(context: common.UIAbilityContext): Promise<boolean> {
    const want: Want = {
      bundleName: DesktopShell.BUNDLE_NAME,
      moduleName: 'entry',
      abilityName: 'TrayResidentAbility'
    };
    const options: StartOptions = {
      processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE,
      hideStartWindow: true
    };
    try {
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      console.error('start tray resident failed: ' + String(error));
      return false;
    }
  }

  static async createPaper(context: common.UIAbilityContext, type: string,
    sourcePaperId: string = ''): Promise<PaperData | null> {
    const normalizedType: string = type === PAPER_TYPE_NOTE ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO;
    const paper: PaperData | null = PaperStore.createPaper(normalizedType, sourcePaperId);
    if (paper === null) {
      return null;
    }
    await DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_SHOW);
    return paper;
  }

  static async showAll(context: common.UIAbilityContext): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const starts: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, true);
      starts.push(DesktopShell.startPaper(context, papers[i].id, PAPER_COMMAND_SHOW));
    }
    await Promise.all(starts);
  }

  static async hideAll(context: common.UIAbilityContext): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const hides: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, false);
      hides.push(DesktopShell.startPaper(context, papers[i].id, PAPER_COMMAND_HIDE));
    }
    await Promise.all(hides);
  }

  static terminate(context: common.UIAbilityContext): void {
    context.terminateSelf().catch((error: BusinessError): void => {
      console.error('terminate ability failed: ' + error.message);
    });
  }
}
