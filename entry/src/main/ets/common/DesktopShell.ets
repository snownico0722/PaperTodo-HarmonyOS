import { common, contextConstant, StartOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppState, PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from './Models';
import { PaperStore } from './PaperStore';
import { TrayService } from './TrayService';
import { CapsuleRuntime } from './CapsuleRuntime';

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
    if (command === PAPER_COMMAND_SHOW && CapsuleRuntime.hasFailed()) {
      return false;
    }
    const request: number = command === PAPER_COMMAND_SHOW ? CapsuleRuntime.request() : -1;
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
      return command !== PAPER_COMMAND_SHOW || await CapsuleRuntime.waitFor(request);
    } catch (error) {
      if (command === PAPER_COMMAND_SHOW) {
        CapsuleRuntime.failRequest(request, 'Start capsule host failed: ' + String(error));
      }
      console.error('start capsule host failed: ' + String(error));
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
    CapsuleRuntime.cancelCollapse(paperId);
    PaperStore.setPaperVisible(paperId, false);
    if (AppStorage.get<boolean>('paperOpen:' + paperId) === true) {
      await DesktopShell.startPaper(context, paperId, PAPER_COMMAND_HIDE);
    }
    await DesktopShell.syncCapsules(context);
  }

  static async setPaperCollapsed(context: common.UIAbilityContext, paperId: string,
    collapsed: boolean): Promise<void> {
    const initial: PaperData | null = PaperStore.getPaper(paperId);
    if (initial === null) {
      return;
    }
    PaperStore.setPaperVisible(paperId, true);
    const state: AppState = PaperStore.loadState();
    if (collapsed && state.useCapsuleMode && state.useDeepCapsuleMode &&
      PaperStore.canPaperDisplayAsCapsule(initial)) {
      const token: number = CapsuleRuntime.stageCollapse(paperId);
      try {
        await DesktopShell.syncCapsules(context);
        if (!CapsuleRuntime.ownsCollapse(paperId, token)) {
          return;
        }
        const latest: PaperData | null = PaperStore.getPaper(paperId);
        const current: AppState = PaperStore.loadState();
        if (latest === null || !latest.isVisible || !current.useCapsuleMode || !current.useDeepCapsuleMode) {
          return;
        }
        // Do not mutate the durable state or close the original before the host
        // has acknowledged its current layout, native mask and successful show.
        PaperStore.setPaperCollapsed(paperId, CapsuleRuntime.isReady());
      } finally {
        if (CapsuleRuntime.ownsCollapse(paperId, token)) {
          CapsuleRuntime.cancelCollapse(paperId);
        }
      }
      await DesktopShell.syncCapsules(context);
      return;
    }
    CapsuleRuntime.cancelCollapse(paperId);
    PaperStore.setPaperCollapsed(paperId, collapsed);
    const stored: PaperData | null = PaperStore.getPaper(paperId);
    const appliedCollapsed: boolean = stored !== null && stored.isCollapsed;
    await DesktopShell.startPaper(context, paperId,
      appliedCollapsed ? PAPER_COMMAND_COLLAPSE : PAPER_COMMAND_EXPAND);
    await DesktopShell.syncCapsules(context);
  }

  static async deletePaper(context: common.UIAbilityContext, paperId: string): Promise<PaperData | null> {
    CapsuleRuntime.cancelCollapse(paperId);
    const replacement: PaperData | null = PaperStore.deletePaper(paperId);
    if (AppStorage.get<boolean>('paperOpen:' + paperId) === true) {
      await DesktopShell.startPaper(context, paperId, PAPER_COMMAND_CLOSE);
    }
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
      CapsuleRuntime.cancelCollapse(papers[i].id);
      PaperStore.setPaperVisible(papers[i].id, false);
      if (AppStorage.get<boolean>('paperOpen:' + papers[i].id) === true) {
        hides.push(DesktopShell.startPaper(context, papers[i].id, PAPER_COMMAND_HIDE));
      }
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

    const hasCapsuleHost: boolean = enabled && members.length > 0;
    let capsuleReachable: boolean = false;
    if (hasCapsuleHost) {
      capsuleReachable = await DesktopShell.startMaster(context, PAPER_COMMAND_SHOW);
    }
    // A failed host is latched until an explicit retry: no create/close storm.
    // Re-expand persisted collapsed papers (including cold-start recovery).
    if (hasCapsuleHost && !capsuleReachable && CapsuleRuntime.hasFailed()) {
      const recover: PaperData[] = PaperStore.listPapers();
      for (let i: number = 0; i < recover.length; i++) {
        if (recover[i].isVisible && recover[i].isCollapsed) {
          PaperStore.setPaperCollapsed(recover[i].id, false);
        }
      }
    }
    if ((!hasCapsuleHost || CapsuleRuntime.hasFailed()) &&
      AppStorage.get<boolean>('masterCapsuleOpen') === true) {
      await DesktopShell.startMaster(context, PAPER_COMMAND_CLOSE);
    }

    const papers: PaperData[] = PaperStore.listPapers();
    const closes: Promise<boolean>[] = [];
    const starts: Promise<boolean>[] = [];
    let paperReachable: boolean = false;
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      if (AppStorage.get<boolean>('edgeCapsuleOpen:' + paper.id) === true) {
        closes.push(DesktopShell.startEdge(context, paper.id, PAPER_COMMAND_CLOSE));
      }
      const open: boolean = AppStorage.get<boolean>('paperOpen:' + paper.id) === true;
      const delegated: boolean = capsuleReachable && CapsuleRuntime.isReady() &&
        state.useCapsuleMode && state.useDeepCapsuleMode && paper.isCollapsed &&
        PaperStore.canPaperDisplayAsCapsule(paper);
      if (!paper.isVisible || delegated) {
        if (open) {
          closes.push(DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_CLOSE));
        }
      } else if (!open) {
        starts.push(DesktopShell.startPaper(context, paper.id, PAPER_COMMAND_SHOW));
      } else {
        paperReachable = true;
      }
    }
    await Promise.all(closes);
    const results: boolean[] = await Promise.all(starts);
    for (let i: number = 0; i < results.length; i++) {
      paperReachable = paperReachable || results[i];
    }
    // Successful teardown is never evidence of a reachable surface.
    return capsuleReachable || paperReachable;
  }

  static async restoreAllPapers(context: common.UIAbilityContext): Promise<void> {
    const papers: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < papers.length; i++) {
      CapsuleRuntime.cancelCollapse(papers[i].id);
      PaperStore.setPaperCollapsed(papers[i].id, false);
    }
    await DesktopShell.showAll(context);
  }

  static async retryCapsules(context: common.UIAbilityContext): Promise<boolean> {
    CapsuleRuntime.retry();
    await DesktopShell.syncCapsules(context);
    return CapsuleRuntime.isReady();
  }

  static terminate(context: common.UIAbilityContext): void {
    context.terminateSelf().catch((error: BusinessError): void => {
      console.error('terminate ability failed: ' + error.message);
    });
  }

  static async exitApplication(context: common.UIAbilityContext): Promise<void> {
    if (!PaperStore.flushNow()) {
      AppStorage.setOrCreate<boolean>('saveExitBlocked', true);
      await DesktopShell.openSettings(context);
      return;
    }
    AppStorage.setOrCreate<boolean>('applicationExitRequested', true);
    await TrayService.remove(context);
    if (!PaperStore.flushNow()) {
      AppStorage.setOrCreate<boolean>('applicationExitRequested', false);
      AppStorage.setOrCreate<boolean>('saveExitBlocked', true);
      // A second failure after removing the tray must also preserve recovery.
      if (await TrayService.install(context)) {
        await DesktopShell.startResident(context);
      }
      await DesktopShell.openSettings(context);
      return;
    }
    AppStorage.setOrCreate<boolean>('saveExitBlocked', false);
    try {
      await context.getApplicationContext().killAllProcesses(true);
    } catch (error) {
      AppStorage.setOrCreate<boolean>('applicationExitRequested', false);
      console.error('exit PaperTodo failed: ' + String(error));
    }
  }
}
