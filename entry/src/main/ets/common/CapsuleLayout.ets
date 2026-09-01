import {
  CAPSULE_EDGE_START_TOP,
  CAPSULE_GAP_DEFAULT,
  CAPSULE_HEIGHT,
  CAPSULE_SAFE_MARGIN
} from './Models';

export function normalizeCapsuleGap(gap: number): number {
  if (gap === 0 || gap === 8) {
    return gap;
  }
  return CAPSULE_GAP_DEFAULT;
}

export function normalizeCapsuleStartTopMargin(requested: number, areaHeight: number,
  memberCount: number, gap: number, includeMaster: boolean): number {
  const safeRequested: number = Number.isFinite(requested) ? requested : CAPSULE_EDGE_START_TOP;
  const safeHeight: number = Number.isFinite(areaHeight) ? Math.max(0, areaHeight) : 0;
  const safeCount: number = Number.isFinite(memberCount) ? Math.max(0, Math.floor(memberCount)) : 0;
  const safeGap: number = normalizeCapsuleGap(gap);
  const slotCount: number = safeCount > 0 ? safeCount + (includeMaster ? 1 : 0) : 0;
  if (slotCount === 0 || safeHeight <= 0) {
    return Math.max(CAPSULE_SAFE_MARGIN, safeRequested);
  }
  const stackHeight: number = slotCount * CAPSULE_HEIGHT + Math.max(0, slotCount - 1) * safeGap;
  const maxStart: number = Math.max(CAPSULE_SAFE_MARGIN,
    safeHeight - stackHeight - CAPSULE_SAFE_MARGIN);
  return Math.max(CAPSULE_SAFE_MARGIN, Math.min(safeRequested, maxStart));
}

export function capsuleSlotTop(startTop: number, memberIndex: number, gap: number,
  includeMaster: boolean): number {
  const safeIndex: number = Math.max(0, Math.floor(memberIndex));
  const slotIndex: number = safeIndex + (includeMaster ? 1 : 0);
  return startTop + slotIndex * (CAPSULE_HEIGHT + normalizeCapsuleGap(gap));
}
