export interface DisplayGeometry {
  density: number;
  screenWidthPx: number;
  screenHeightPx: number;
  screenWidthVp: number;
  screenHeightVp: number;
}

export interface LogicalRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function normalizeDensity(densityPixels: number): number {
  return Number.isFinite(densityPixels) && densityPixels > 0 ? densityPixels : 1;
}

export function vpToPx(valueVp: number, densityPixels: number): number {
  return Math.round(valueVp * normalizeDensity(densityPixels));
}

export function pxToVp(valuePx: number, densityPixels: number): number {
  return valuePx / normalizeDensity(densityPixels);
}

export function createDisplayGeometry(
  screenWidthPx: number,
  screenHeightPx: number,
  densityPixels: number
): DisplayGeometry {
  const density: number = normalizeDensity(densityPixels);
  return {
    density: density,
    screenWidthPx: screenWidthPx,
    screenHeightPx: screenHeightPx,
    screenWidthVp: screenWidthPx / density,
    screenHeightVp: screenHeightPx / density
  };
}

export function clampLogicalRect(
  xVp: number,
  yVp: number,
  widthVp: number,
  heightVp: number,
  minWidthVp: number,
  minHeightVp: number,
  display: DisplayGeometry
): LogicalRect {
  const width: number = Math.min(display.screenWidthVp, Math.max(minWidthVp, widthVp));
  const height: number = Math.min(display.screenHeightVp, Math.max(minHeightVp, heightVp));
  return {
    x: clamp(xVp, 0, Math.max(0, display.screenWidthVp - width)),
    y: clamp(yVp, 0, Math.max(0, display.screenHeightVp - height)),
    width: width,
    height: height
  };
}

export function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.max(minValue, Math.min(value, maxValue));
}
