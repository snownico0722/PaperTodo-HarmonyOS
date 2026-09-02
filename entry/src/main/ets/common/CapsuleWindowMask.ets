import { window } from '@kit.ArkUI';

export interface CapsuleWindowMaskRow {
  topPx: number;
  heightPx: number;
  visibleWidthPx: number;
  radiusPx: number;
}

function emptyMask(width: number, height: number): number[][] {
  const mask: number[][] = new Array(height).fill(null).map((): number[] => new Array(width).fill(0));
  return mask;
}

function fillRoundedLeftRow(mask: number[][], width: number, height: number,
  row: CapsuleWindowMaskRow): void {
  const top: number = Math.max(0, Math.min(height - 1, Math.round(row.topPx)));
  const bottom: number = Math.max(top, Math.min(height, top + Math.max(1, Math.round(row.heightPx))));
  const visibleWidth: number = Math.max(1, Math.min(width, Math.round(row.visibleWidthPx)));
  const left: number = Math.max(0, width - visibleWidth);
  const rowHeight: number = Math.max(1, bottom - top);
  const radius: number = Math.max(0, Math.min(Math.round(row.radiusPx), Math.floor(rowHeight / 2), visibleWidth));
  const centerX: number = left + radius;
  const centerY: number = top + (rowHeight - 1) / 2;
  const radiusSquared: number = radius * radius;

  for (let y: number = top; y < bottom; y++) {
    for (let x: number = left; x < width; x++) {
      if (radius === 0 || x >= centerX) {
        mask[y][x] = 1;
        continue;
      }
      const dx: number = x - centerX;
      const dy: number = y - centerY;
      if (dx * dx + dy * dy <= radiusSquared) {
        mask[y][x] = 1;
      }
    }
  }
}

export async function applyCapsuleWindowMask(win: window.Window, widthPx: number, heightPx: number,
  rows: CapsuleWindowMaskRow[]): Promise<boolean> {
  if (!canIUse('SystemCapability.Window.SessionManager')) {
    console.warn('capsule window mask unavailable: SystemCapability.Window.SessionManager is not supported');
    return false;
  }
  const width: number = Math.max(1, Math.round(widthPx));
  const height: number = Math.max(1, Math.round(heightPx));
  const mask: number[][] = emptyMask(width, height);
  for (let i: number = 0; i < rows.length; i++) {
    fillRoundedLeftRow(mask, width, height, rows[i]);
  }
  try {
    await win.setWindowMask(mask);
    return true;
  } catch (error) {
    console.warn('apply capsule window mask failed: ' + String(error));
    return false;
  }
}
