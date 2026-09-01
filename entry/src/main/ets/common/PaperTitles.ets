import {
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  TITLE_MAX_LENGTH,
  UI_LANGUAGE_EN,
  UI_LANGUAGE_JA,
  UI_LANGUAGE_KO,
  UI_LANGUAGE_ZH_CN
} from './Models';
import { resolveLanguage } from './Strings';
import { truncateText } from './TextSafety';

export const DEFAULT_PAPER_TITLE_LIMIT: number = 6;
export const MIN_PAPER_TITLE_LIMIT: number = 2;

export function normalizePaperTitleLimit(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return DEFAULT_PAPER_TITLE_LIMIT;
  }
  return Math.max(MIN_PAPER_TITLE_LIMIT, Math.min(TITLE_MAX_LENGTH, Math.round(value)));
}

export function cleanPaperTitle(value: string, maxLength: number = TITLE_MAX_LENGTH): string {
  const limit: number = Number.isFinite(maxLength) ?
    Math.max(1, Math.min(TITLE_MAX_LENGTH, Math.round(maxLength))) : TITLE_MAX_LENGTH;
  let withoutControls: string = '';
  for (let i: number = 0; i < value.length; i++) {
    const codeUnit: number = value.charCodeAt(i);
    if (codeUnit <= 0x1F || (codeUnit >= 0x7F && codeUnit <= 0x9F)) {
      continue;
    }
    withoutControls += value.charAt(i);
  }
  return truncateText(withoutControls.trim(), limit);
}

export function cleanCommittedPaperTitle(value: string, userLimit: number): string {
  return cleanPaperTitle(value, normalizePaperTitleLimit(userLimit));
}

export function defaultPaperTitlePrefix(type: string, uiLanguage: string, systemLanguage: string): string {
  const language: string = resolveLanguage(uiLanguage, systemLanguage);
  const isNote: boolean = type === PAPER_TYPE_NOTE;
  if (language === UI_LANGUAGE_EN) {
    return isNote ? 'Note' : 'Todo';
  }
  if (language === UI_LANGUAGE_JA) {
    return isNote ? 'メモ' : 'ToDo';
  }
  if (language === UI_LANGUAGE_KO) {
    return isNote ? '메모' : '할 일';
  }
  return isNote ? '笔记' : '待办';
}

export function defaultPaperTitle(type: string, number: number, uiLanguage: string,
  systemLanguage: string): string {
  const normalizedNumber: number = Number.isFinite(number) ? Math.max(1, Math.floor(number)) : 1;
  return defaultPaperTitlePrefix(type, uiLanguage, systemLanguage) + normalizedNumber.toString();
}

export function nextPaperTitleNumber(papers: PaperData[], type: string, uiLanguage: string,
  systemLanguage: string): number {
  const normalizedType: string = type === PAPER_TYPE_NOTE ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO;
  const prefix: string = defaultPaperTitlePrefix(normalizedType, uiLanguage, systemLanguage);
  const usedNumbers: number[] = [];
  for (let i: number = 0; i < papers.length; i++) {
    if (papers[i].type !== normalizedType) {
      continue;
    }
    const title: string = cleanPaperTitle(papers[i].title);
    if (!title.startsWith(prefix)) {
      continue;
    }
    const suffix: string = title.substring(prefix.length);
    const number: number = parsePositiveInteger(suffix);
    if (number > 0 && !containsNumber(usedNumbers, number)) {
      usedNumbers.push(number);
    }
  }

  let next: number = 1;
  while (containsNumber(usedNumbers, next)) {
    next += 1;
  }
  return next;
}

export function paperTitleNumberFor(paper: PaperData, papers: PaperData[]): number {
  const normalizedType: string = paper.type === PAPER_TYPE_NOTE ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO;
  let number: number = 1;
  for (let i: number = 0; i < papers.length; i++) {
    const existingType: string = papers[i].type === PAPER_TYPE_NOTE ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO;
    if (existingType !== normalizedType) {
      continue;
    }
    if (papers[i].id === paper.id) {
      return number;
    }
    number += 1;
  }
  return Math.max(1, number);
}

// Read-only fallback for legacy data. It deliberately does not write a generated
// title back to PaperData, so an old empty title remains migration-compatible.
export function effectivePaperTitle(paper: PaperData, papers: PaperData[], uiLanguage: string,
  systemLanguage: string): string {
  const title: string = cleanPaperTitle(paper.title);
  if (title.length > 0) {
    return title;
  }
  return defaultPaperTitle(paper.type, paperTitleNumberFor(paper, papers), uiLanguage, systemLanguage);
}

function parsePositiveInteger(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  for (let i: number = 0; i < value.length; i++) {
    const codeUnit: number = value.charCodeAt(i);
    if (codeUnit < 0x30 || codeUnit > 0x39) {
      return 0;
    }
  }
  const parsed: number = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0 || Math.floor(parsed) !== parsed) {
    return 0;
  }
  return parsed;
}

function containsNumber(values: number[], target: number): boolean {
  for (let i: number = 0; i < values.length; i++) {
    if (values[i] === target) {
      return true;
    }
  }
  return false;
}
