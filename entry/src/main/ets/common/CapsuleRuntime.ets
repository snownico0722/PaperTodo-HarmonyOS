// Runtime-only handoff state. Never persist pending collapses as completed work.
export class CapsuleRuntime {
  private static owner: string = '';
  private static requested: number = 0;
  private static acknowledged: number = -1;
  private static failed: boolean = false;
  private static parentReady: boolean = false;
  private static collapseSequence: number = 0;
  private static pending: Map<string, number> = new Map<string, number>();

  static begin(token: string): void {
    CapsuleRuntime.owner = token;
    CapsuleRuntime.parentReady = false;
    CapsuleRuntime.acknowledged = -1;
  }

  static isOwner(token: string): boolean {
    return token.length > 0 && CapsuleRuntime.owner === token;
  }

  static request(): number {
    CapsuleRuntime.requested++;
    CapsuleRuntime.parentReady = false;
    AppStorage.setOrCreate<number>('capsuleLayoutRequest', CapsuleRuntime.requested);
    return CapsuleRuntime.requested;
  }

  static currentRequest(): number {
    return CapsuleRuntime.requested;
  }

  static parentPrepared(token: string): void {
    if (CapsuleRuntime.isOwner(token) && !CapsuleRuntime.failed) {
      CapsuleRuntime.parentReady = true;
    }
  }

  static isParentReady(token: string): boolean {
    return CapsuleRuntime.isOwner(token) && CapsuleRuntime.parentReady && !CapsuleRuntime.failed;
  }

  static isReady(): boolean {
    return CapsuleRuntime.parentReady && !CapsuleRuntime.failed && CapsuleRuntime.owner.length > 0 &&
      CapsuleRuntime.acknowledged === CapsuleRuntime.requested;
  }

  static confirm(token: string, request: number): boolean {
    if (!CapsuleRuntime.isParentReady(token) || request !== CapsuleRuntime.requested) {
      return false;
    }
    CapsuleRuntime.acknowledged = request;
    AppStorage.setOrCreate<string>('capsuleRuntimeError', '');
    return true;
  }

  static hasFailed(): boolean {
    return CapsuleRuntime.failed;
  }

  static fail(token: string, reason: string): void {
    if (CapsuleRuntime.isOwner(token)) {
      CapsuleRuntime.failRequest(CapsuleRuntime.requested, reason);
    }
  }

  static failRequest(request: number, reason: string): void {
    if (request !== CapsuleRuntime.requested) {
      return;
    }
    CapsuleRuntime.failed = true;
    CapsuleRuntime.acknowledged = -1;
    AppStorage.setOrCreate<string>('capsuleRuntimeError', reason);
  }

  static end(token: string): void {
    if (!CapsuleRuntime.isOwner(token)) {
      return;
    }
    CapsuleRuntime.owner = '';
    CapsuleRuntime.acknowledged = -1;
  }

  static retry(): void {
    CapsuleRuntime.failed = false;
    CapsuleRuntime.acknowledged = -1;
    AppStorage.setOrCreate<string>('capsuleRuntimeError', '');
  }

  static async waitFor(request: number, timeoutMs: number = 6000): Promise<boolean> {
    const deadline: number = Date.now() + Math.max(0, timeoutMs);
    while (request === CapsuleRuntime.requested && !CapsuleRuntime.failed) {
      if (CapsuleRuntime.isReady()) {
        return true;
      }
      if (Date.now() >= deadline) {
        CapsuleRuntime.failRequest(request, 'Capsule layout/mask/show readiness timed out.');
        return false;
      }
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 25); });
    }
    return false;
  }

  static stageCollapse(paperId: string): number {
    const token: number = ++CapsuleRuntime.collapseSequence;
    CapsuleRuntime.pending.set(paperId, token);
    return token;
  }

  static isPending(paperId: string): boolean {
    return CapsuleRuntime.pending.has(paperId);
  }

  static ownsCollapse(paperId: string, token: number): boolean {
    return CapsuleRuntime.pending.get(paperId) === token;
  }

  static cancelCollapse(paperId: string): void {
    CapsuleRuntime.pending.delete(paperId);
  }
}
