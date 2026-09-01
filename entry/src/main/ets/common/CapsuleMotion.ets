import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

const FRAME_MS: number = 16;

export class CapsuleMotion {
  private timer: number = -1;
  private currentX: number = 0;
  private currentY: number = 0;
  private initialized: boolean = false;
  private moveInFlight: boolean = false;
  private movePending: boolean = false;
  private pendingWindow: window.Window | null = null;

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    // An already-dispatched Window move cannot be cancelled, but stale queued frames can.
    this.movePending = false;
    this.pendingWindow = null;
  }

  reset(): void {
    this.stop();
    this.initialized = false;
  }

  setPosition(win: window.Window, x: number, y: number): void {
    this.stop();
    this.currentX = Math.round(x);
    this.currentY = Math.round(y);
    this.initialized = true;
    this.requestMove(win);
  }

  animateX(win: window.Window, targetX: number, y: number, durationMs: number): void {
    const target: number = Math.round(targetX);
    const nextY: number = Math.round(y);
    if (!this.initialized) {
      this.setPosition(win, target, nextY);
      return;
    }

    this.stop();
    const startX: number = this.currentX;
    this.currentY = nextY;
    if (startX === target || durationMs <= 0) {
      this.setPosition(win, target, nextY);
      return;
    }

    const startedAt: number = Date.now();
    this.timer = setInterval((): void => {
      const elapsed: number = Date.now() - startedAt;
      const progress: number = Math.max(0, Math.min(1, elapsed / durationMs));
      const inverse: number = 1 - progress;
      const eased: number = 1 - inverse * inverse * inverse;
      this.currentX = Math.round(startX + (target - startX) * eased);
      this.requestMove(win);
      if (progress >= 1) {
        if (this.timer >= 0) {
          clearInterval(this.timer);
          this.timer = -1;
        }
        this.currentX = target;
        this.requestMove(win);
      }
    }, FRAME_MS);
  }

  private requestMove(win: window.Window): void {
    if (this.moveInFlight) {
      // Coalesce every intermediate frame into the latest desired position.
      this.movePending = true;
      this.pendingWindow = win;
      return;
    }
    this.dispatchMove(win);
  }

  private dispatchMove(win: window.Window): void {
    const x: number = this.currentX;
    const y: number = this.currentY;
    this.moveInFlight = true;
    try {
      win.moveWindowTo(x, y).then((): void => {
        this.moveInFlight = false;
        this.dispatchPendingMove();
      }).catch((error: BusinessError): void => {
        console.error('capsule window move failed: ' + error.message);
        this.moveInFlight = false;
        this.movePending = false;
        this.pendingWindow = null;
        this.initialized = false;
        this.stop();
      });
    } catch (error) {
      console.error('capsule window move threw: ' + String(error));
      this.moveInFlight = false;
      this.movePending = false;
      this.pendingWindow = null;
      this.initialized = false;
      this.stop();
    }
  }

  private dispatchPendingMove(): void {
    if (!this.movePending || this.pendingWindow === null) {
      return;
    }
    const win: window.Window = this.pendingWindow;
    this.movePending = false;
    this.pendingWindow = null;
    this.dispatchMove(win);
  }
}
