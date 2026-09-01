import { CAPSULE_HEIGHT, CAPSULE_WIDTH } from './Models';
import { normalizeDensity, vpToPx } from './WindowGeometry';

export interface CapsuleMetrics {
  density: number;
  widthPx: number;
  heightPx: number;
  gapPx: number;
  topPx: number;
  hiddenOffsetPx: number;
  screenWidthPx: number;
  screenHeightPx: number;
}

export function createCapsuleMetrics(
  screenWidthPx: number,
  screenHeightPx: number,
  densityPixels: number,
  gapVp: number
): CapsuleMetrics {
  const density: number = normalizeDensity(densityPixels);
  const widthPx: number = Math.max(1, vpToPx(CAPSULE_WIDTH, density));
  const heightPx: number = Math.max(1, vpToPx(CAPSULE_HEIGHT, density));
  return {
    density: density,
    widthPx: widthPx,
    heightPx: heightPx,
    gapPx: Math.max(0, vpToPx(gapVp, density)),
    topPx: Math.max(0, vpToPx(20, density)),
    hiddenOffsetPx: Math.round(widthPx * 0.45),
    screenWidthPx: screenWidthPx,
    screenHeightPx: screenHeightPx
  };
}

export function edgeCapsuleFullX(metrics: CapsuleMetrics): number {
  return Math.max(0, metrics.screenWidthPx - metrics.widthPx);
}

export function edgeCapsuleHiddenX(metrics: CapsuleMetrics): number {
  return edgeCapsuleFullX(metrics) + metrics.hiddenOffsetPx;
}

export function edgeCapsuleY(index: number, metrics: CapsuleMetrics): number {
  const raw: number = metrics.topPx + Math.max(0, index) * (metrics.heightPx + metrics.gapPx);
  return clamp(raw, 0, Math.max(0, metrics.screenHeightPx - metrics.heightPx));
}

export function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.max(minValue, Math.min(value, maxValue));
}
