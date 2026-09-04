import { CAPSULE_HEIGHT, CAPSULE_SAFE_MARGIN } from './Models';
import { normalizeCapsuleGap } from './CapsuleLayout';

export const CAPSULE_PAGER_WIDTH: number = 112;

export interface CapsuleViewport {
  page: number;
  pages: number;
  start: number;
  end: number;
  height: number;
  pager: boolean;
  fits: boolean;
}

export function capsuleViewport(areaHeight: number, memberCount: number, gap: number,
  includeMaster: boolean, retracted: boolean, requestedPage: number): CapsuleViewport {
  const count: number = Number.isFinite(memberCount) ? Math.max(0, Math.floor(memberCount)) : 0;
  const safeGap: number = normalizeCapsuleGap(gap);
  const available: number = Number.isFinite(areaHeight) ? Math.max(0, areaHeight - 2 * CAPSULE_SAFE_MARGIN) : 0;
  const slots: number = Math.max(0, Math.floor((available + safeGap) / (CAPSULE_HEIGHT + safeGap)));
  const master: number = includeMaster ? 1 : 0;
  if (retracted && includeMaster) {
    return { page: 0, pages: 1, start: 0, end: 0, height: CAPSULE_HEIGHT, pager: false, fits: slots >= 1 };
  }
  const pager: boolean = count + master > slots;
  const capacity: number = Math.max(1, slots - master - (pager ? 1 : 0));
  const pages: number = Math.max(1, Math.ceil(count / capacity));
  const requested: number = Number.isFinite(requestedPage) ? Math.floor(requestedPage) : 0;
  const page: number = Math.max(0, Math.min(pages - 1, requested));
  const start: number = page * capacity;
  const end: number = Math.min(count, start + capacity);
  const used: number = master + (pager ? 1 : 0) + end - start;
  const height: number = Math.max(CAPSULE_HEIGHT, used * CAPSULE_HEIGHT + Math.max(0, used - 1) * safeGap);
  return { page: page, pages: pages, start: start, end: end, height: height,
    pager: pager, fits: height <= available };
}

export function capsuleViewportTop(requested: number, areaHeight: number, height: number): number {
  const top: number = Number.isFinite(requested) ? requested : 48;
  return Math.max(CAPSULE_SAFE_MARGIN,
    Math.min(top, Math.max(CAPSULE_SAFE_MARGIN, areaHeight - height - CAPSULE_SAFE_MARGIN)));
}
