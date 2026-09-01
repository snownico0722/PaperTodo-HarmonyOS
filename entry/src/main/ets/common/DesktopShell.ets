import { common, contextConstant, StartOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppState, PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from './Models';
import { PaperStore } from './PaperStore';
import { TrayService } from './TrayService';

export const PAPER_COMMAND_SHOW: string = 'show';
export const PAPER_COMMAND_HIDE: string = 'hide';
export const PAPER_COMMAND_CLOSE: string = 'close';
export const PAPER_COMMAND_DELETE: string = 'delete';
export const PAPER_COMMAND_EXPAND: string = 'expand';
export const PAPER_COMMAND_COLLAPSE: string = 'collapse';

export class DesktopShell {
  static readonly BUNDLE_NAME: string = 'com.papertodo.app';
  private static syncPromise: Promise<boolean> | null = null;
  private static syncPending: boolean = false;
  private static syncContext: common.UIAbilityContext | null = null;

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
    if (DesktopShell.isResidentReady()) {
      return true;
    }
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
      // Cold starts on 2-in-1 devices can take several seconds before the
      // hidden attached ability finishes creating its host WindowStage.
      for (let attempt: number = 0; attempt < 30; attempt++) {
        if (DesktopShell.isResidentReady()) {
          return true;
        }
        await DesktopShell.delay(120);
      }
      console.error('tray resident start was accepted but readiness was not observed');
      return false;
    } catch (error) {
      if (DesktopShell.isResidentReady()) {
        return true;
      }
      console.error('start tray resident failed: ' + String(error));
      return false;
    }
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }

  private static isResidentReady(): boolean {
    return AppStorage.get<boolean>('trayResidentReady') === true &&
      (AppStorage.get<string>('trayResidentToken') ?? '').length > 0;
  }

  static async createPaper(context: common.UIAbilityContext, type: string,
    sourcePaperId: string = ''): Promise<PaperData | null> {
    const normalizedType: string = type === PAPER_TYPE_NOTE ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO;
    const paper: PaperData | null = PaperStore.createPaper(normalizedType, sourcePaperId);
    if (paper === null) {
      return null;
    }
    await DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_SHOW);
    await DesktopShell.syncCapsules(context);
    return paper;
  }

  static async hidePaper(context: common.UIAbilityContext, paperId: string): Promise<void> {
    PaperStore.setPaperVisible(paperId, false);
    await DesktopShell.startPaper(context, paperId, PAPER_COMMAND_HIDE);
    await DesktopShell.syncCapsules(context);
  }

  static async setPaperCollapsed(context: common.UIAbilityContext, paperId: string,
    collapsed: boolean): Promise<void> {
    PaperStore.setPaperVisible(paperId, true);
    PaperStore.setPaperCollapsed(paperId, collapsed);
    const stored: PaperData | null = PaperStore.getPaper(paperId);
    const appliedCollapsed: boolean = stored !== null && stored.isCollapsed;
    await DesktopShell.startPaper(context, paperId,
      appliedCollapsed ? PAPER_COMMAND_COLLAPSE : PAPER_COMMAND_EXPAND);
    await DesktopShell.syncCapsules(context);
  }

  static async deletePaper(context: common.UIAbilityContext, paperId: string): Promise<PaperData | null> {
    const replacement: PaperData | null = PaperStore.deletePaper(paperId);
    await DesktopShell.startPaper(context, paperId, PAPER_COMMAND_CLOSE);
    if (replacement !== null) {
      await DesktopShell.startPaper(context, replacement.id, PAPER_COMMAND_SHOW);
    }
    await DesktopShell.syncCapsules(context);
    return replacement;
  }

  static async showAll(context: common.UIAbilityContext): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const starts: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, true);
      starts.push(DesktopShell.startPaper(context, papers[i].id, PAPER_COMMAND_SHOW));
    }
    await Promise.all(starts);
    await DesktopShell.syncCapsules(context);
  }

  static async hideAll(context: common.UIAbilityContext): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    const hides: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      PaperStore.setPaperVisible(papers[i].id, false);
      hides.push(DesktopShell.startPaper(context, papers[i].id, PAPER_COMMAND_HIDE));
    }
    await Promise.all(hides);
    await DesktopShell.syncCapsules(context);
  }

  static syncCapsules(context: common.UIAbilityContext): Promise<boolean> {
    DesktopShell.syncContext = context;
    if (DesktopShell.syncPromise !== null) {
      DesktopShell.syncPending = true;
      return DesktopShell.syncPromise;
    }
    const pending: Promise<boolean> = DesktopShell.runSyncLoop();
    DesktopShell.syncPromise = pending;
    pending.then((_reachable: boolean): void => {
      DesktopShell.syncPromise = null;
    }).catch((_error: Error): void => {
      DesktopShell.syncPromise = null;
    });
    return pending;
  }

  private static async runSyncLoop(): Promise<boolean> {
    let capsuleReachable: boolean = false;
    do {
      DesktopShell.syncPending = false;
      const context: common.UIAbilityContext | null = DesktopShell.syncContext;
      if (context !== null) {
        capsuleReachable = await DesktopShell.reconcileCapsules(context);
      }
    } while (DesktopShell.syncPending);
    return capsuleReachable;
  }

  private static async reconcileCapsules(context: common.UIAbilityContext): Promise<boolean> {
    const state: AppState = PaperStore.loadState();
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    if (members.length === 0 && state.capsuleCollapseAllActive) {
      PaperStore.setCapsuleCollapseAllActive(false);
    }
    const enabled: boolean = state.useCapsuleMode && state.useDeepCapsuleMode;
    const hasMaster: boolean = enabled && state.useMasterCapsule && members.length > 0;
    let capsuleReachable: boolean = false;
    if (hasMaster) {
      capsuleReachable = await DesktopShell.startMaster(context, PAPER_COMMAND_SHOW);
    } else if (AppStorage.get<boolean>('masterCapsuleOpen') === true) {
      await DesktopShell.startMaster(context, PAPER_COMMAND_CLOSE);
    }

    const papers: PaperData[] = PaperStore.listPapers();
    const operations: Promise<boolean>[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      const capsuleEligible: boolean = PaperStore.canPaperDisplayAsCapsule(paper);
      const queueMember: boolean = enabled && capsuleEligible && paper.isVisible &&
        (paper.isCollapsed || state.showDeepCapsuleWhileExpanded);
      if (queueMember) {
        operations.push(DesktopShell.startEdge(context, paper.id, PAPER_COMMAND_SHOW));
      } else if (AppStorage.get<boolean>('edgeCapsuleOpen:' + paper.id) === true) {
        operations.push(DesktopShell.startEdge(context, paper.id, PAPER_COMMAND_CLOSE));
      }

      if (!paper.isVisible) {
        if (AppStorage.get<boolean>('paperOpen:' + paper.id) === true) {
          operations.push(DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_CLOSE));
        }
      } else if (paper.isCollapsed && enabled && capsuleEligible) {
        if (AppStorage.get<boolean>('paperOpen:' + paper.id) === true) {
          operations.push(DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_CLOSE));
        }
      } else if (AppStorage.get<boolean>('paperOpen:' + paper.id) !== true) {
        operations.push(DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_SHOW));
      }
    }
    if (operations.length > 0) {
      const results: boolean[] = await Promise.all(operations);
      for (let i: number = 0; i < results.length; i++) {
        capsuleReachable = capsuleReachable || results[i];
      }
    }
    return capsuleReachable;
  }

  static terminate(context: common.UIAbilityContext): void {
    context.terminateSelf().catch((error: BusinessError): void => {
      console.error('terminate ability failed: ' + error.message);
    });
  }

  static async exitApplication(context: common.UIAbilityContext): Promise<void> {
    // HarmonyOS has no normal API that terminates every specified UIAbility in
    // one operation. An explicit user Exit therefore performs all durable and
    // system-facing cleanup first, then clears the application's process/page
    // stack as the final step.
    PaperStore.flushNow();
    AppStorage.setOrCreate<boolean>('applicationExitRequested', true);
    await TrayService.remove(context);
    PaperStore.flushNow();
    try {
      await context.getApplicationContext().killAllProcesses(true);
    } catch (error) {
      AppStorage.setOrCreate<boolean>('applicationExitRequested', false);
      console.error('exit PaperTodo failed: ' + String(error));
    }
  }
}
