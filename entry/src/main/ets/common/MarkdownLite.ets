import { MARKDOWN_ENHANCED } from './Models';

export const MD_KIND_TEXT: string = 'text';
export const MD_KIND_HEADING: string = 'heading';
export const MD_KIND_BULLET: string = 'bullet';
export const MD_KIND_ORDERED: string = 'ordered';
export const MD_KIND_QUOTE: string = 'quote';
export const MD_KIND_CODE: string = 'code';
export const MD_KIND_RULE: string = 'rule';

export interface MarkdownLine {
  id: string;
  kind: string;
  text: string;
  level: number;
}

export function parseMarkdownLines(content: string, mode: string): MarkdownLine[] {
  const sourceLines: string[] = content.replace(/\r\n/g, '\n').split('\n');
  const result: MarkdownLine[] = [];
  let inCode: boolean = false;

  for (let i: number = 0; i < sourceLines.length; i++) {
    const source: string = sourceLines[i];
    const trimmed: string = source.trim();

    if (trimmed.startsWith('```')) {
      inCode = !inCode;
      if (mode !== MARKDOWN_ENHANCED) {
        result.push({ id: 'line_' + i, kind: MD_KIND_CODE, text: source, level: 0 });
      }
      continue;
    }

    if (inCode) {
      result.push({ id: 'line_' + i, kind: MD_KIND_CODE, text: source, level: 0 });
      continue;
    }

    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      result.push({ id: 'line_' + i, kind: MD_KIND_RULE, text: '', level: 0 });
      continue;
    }

    const headingLevel: number = getHeadingLevel(source);
    if (headingLevel > 0) {
      let headingText: string = source;
      if (mode === MARKDOWN_ENHANCED) {
        headingText = source.substring(headingLevel).trimStart();
        headingText = stripInlineMarkers(headingText);
      }
      result.push({ id: 'line_' + i, kind: MD_KIND_HEADING, text: headingText, level: headingLevel });
      continue;
    }

    if (trimmed.startsWith('> ')) {
      let quoteText: string = source;
      if (mode === MARKDOWN_ENHANCED) {
        quoteText = trimmed.substring(2);
        quoteText = stripInlineMarkers(quoteText);
      }
      result.push({ id: 'line_' + i, kind: MD_KIND_QUOTE, text: quoteText, level: 0 });
      continue;
    }

    if (isBullet(trimmed)) {
      let bulletText: string = source;
      if (mode === MARKDOWN_ENHANCED) {
        bulletText = '• ' + stripInlineMarkers(trimmed.substring(2));
      }
      result.push({ id: 'line_' + i, kind: MD_KIND_BULLET, text: bulletText, level: 0 });
      continue;
    }

    const orderedPrefixLength: number = getOrderedPrefixLength(trimmed);
    if (orderedPrefixLength > 0) {
      let orderedText: string = source;
      if (mode === MARKDOWN_ENHANCED) {
        orderedText = stripInlineMarkers(trimmed);
      }
      result.push({ id: 'line_' + i, kind: MD_KIND_ORDERED, text: orderedText, level: 0 });
      continue;
    }

    result.push({
      id: 'line_' + i,
      kind: MD_KIND_TEXT,
      text: mode === MARKDOWN_ENHANCED ? stripInlineMarkers(source) : source,
      level: 0
    });
  }

  return result;
}

export function stripInlineMarkers(text: string): string {
  let result: string = text;
  result = result.replace(/\*\*(.*?)\*\*/g, '$1');
  result = result.replace(/~~(.*?)~~/g, '$1');
  result = result.replace(/`([^`]*)`/g, '$1');
  result = result.replace(/\*([^*]+)\*/g, '$1');
  result = result.replace(/_([^_]+)_/g, '$1');
  result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)');
  return result;
}

function getHeadingLevel(line: string): number {
  let level: number = 0;
  while (level < line.length && level < 6 && line.charAt(level) === '#') {
    level += 1;
  }
  if (level === 0 || level >= line.length || line.charAt(level) !== ' ') {
    return 0;
  }
  return level;
}

function isBullet(trimmed: string): boolean {
  return trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ');
}

function getOrderedPrefixLength(trimmed: string): number {
  let i: number = 0;
  while (i < trimmed.length) {
    const code: number = trimmed.charCodeAt(i);
    if (code < 48 || code > 57) {
      break;
    }
    i += 1;
  }
  if (i === 0 || i + 1 >= trimmed.length) {
    return 0;
  }
  const marker: string = trimmed.charAt(i);
  const space: string = trimmed.charAt(i + 1);
  if ((marker === '.' || marker === '、') && space === ' ') {
    return i + 2;
  }
  return 0;
}
