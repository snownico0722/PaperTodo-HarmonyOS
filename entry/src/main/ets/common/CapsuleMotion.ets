import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

const FRAME_MS: number = 16;

export class CapsuleMotion {
  private timer: number = -1;
  private currentX: number = 0;
  private currentY: number = 0;
  private initialized: boolean = false;

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
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
    if (!this.tryMove(win)) {
      this.initialized = false;
    }
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
      if (!this.tryMove(win)) {
        this.initialized = false;
        return;
      }
      if (progress >= 1) {
        this.stop();
        this.currentX = target;
        if (!this.tryMove(win)) {
          this.initialized = false;
        }
      }
    }, FRAME_MS);
  }

  private tryMove(win: window.Window): boolean {
    try {
      win.moveWindowTo(this.currentX, this.currentY).catch((error: BusinessError): void => {
        console.error('capsule window move failed: ' + error.message);
        this.initialized = false;
        this.stop();
      });
      return true;
    } catch (error) {
      console.error('capsule window move threw: ' + String(error));
      this.initialized = false;
      this.stop();
      return false;
    }
  }
}
