import { MARKDOWN_ENHANCED } from './Models';

export const MD_KIND_TEXT: string = 'text';
export const MD_KIND_HEADING: string = 'heading';
export const MD_KIND_BULLET: string = 'bullet';
export const MD_KIND_ORDERED: string = 'ordered';
export const MD_KIND_QUOTE: string = 'quote';
export const MD_KIND_CODE: string = 'code';
export const MD_KIND_RULE: string = 'rule';

export interface MarkdownInlineSpan {
  id: string;
  text: string;
  bold: boolean;
  italic: boolean;
  strike: boolean;
  underline: boolean;
  code: boolean;
  link: string;
}

export interface MarkdownLine {
  id: string;
  kind: string;
  text: string;
  level: number;
  spans: MarkdownInlineSpan[];
}

interface InlineStyle {
  bold: boolean;
  italic: boolean;
  strike: boolean;
  underline: boolean;
  code: boolean;
  link: string;
}

interface TaskListMatch {
  done: boolean;
  body: string;
}

const PLAIN_STYLE: InlineStyle = {
  bold: false,
  italic: false,
  strike: false,
  underline: false,
  code: false,
  link: ''
};

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
        result.push(createPlainLine('line_' + i, MD_KIND_CODE, source, 0));
      }
      continue;
    }

    if (inCode) {
      result.push(createPlainLine('line_' + i, MD_KIND_CODE, source, 0));
      continue;
    }

    if (isHorizontalRule(trimmed)) {
      result.push({ id: 'line_' + i, kind: MD_KIND_RULE, text: '', level: 0, spans: [] });
      continue;
    }

    const headingLevel: number = getHeadingLevel(source);
    if (headingLevel > 0) {
      if (mode === MARKDOWN_ENHANCED) {
        const headingSource: string = source.substring(headingLevel).trimStart();
        result.push(createEnhancedLine('line_' + i, MD_KIND_HEADING, headingSource, headingLevel));
      } else {
        result.push(createPlainLine('line_' + i, MD_KIND_HEADING, source, headingLevel));
      }
      continue;
    }

    if (trimmed.startsWith('> ')) {
      if (mode === MARKDOWN_ENHANCED) {
        result.push(createEnhancedLine('line_' + i, MD_KIND_QUOTE, trimmed.substring(2), 0));
      } else {
        result.push(createPlainLine('line_' + i, MD_KIND_QUOTE, source, 0));
      }
      continue;
    }

    const task: TaskListMatch | null = parseTaskList(trimmed);
    if (task !== null) {
      if (mode === MARKDOWN_ENHANCED) {
        let bodySpans: MarkdownInlineSpan[] = parseInlineMarkdown(task.body);
        if (task.done) {
          bodySpans = strikeSpans(bodySpans);
        }
        const spans: MarkdownInlineSpan[] = prependSpan(task.done ? '☑ ' : '☐ ', bodySpans);
        result.push({
          id: 'line_' + i,
          kind: MD_KIND_BULLET,
          text: inlineText(spans),
          level: 0,
          spans: rekeySpans(spans)
        });
      } else {
        result.push(createPlainLine('line_' + i, MD_KIND_BULLET, source, 0));
      }
      continue;
    }

    if (isBullet(trimmed)) {
      if (mode === MARKDOWN_ENHANCED) {
        const bodySpans: MarkdownInlineSpan[] = parseInlineMarkdown(trimmed.substring(2));
        const spans: MarkdownInlineSpan[] = prependSpan('• ', bodySpans);
        result.push({
          id: 'line_' + i,
          kind: MD_KIND_BULLET,
          text: inlineText(spans),
          level: 0,
          spans: rekeySpans(spans)
        });
      } else {
        result.push(createPlainLine('line_' + i, MD_KIND_BULLET, source, 0));
      }
      continue;
    }

    const orderedPrefixLength: number = getOrderedPrefixLength(trimmed);
    if (orderedPrefixLength > 0) {
      if (mode === MARKDOWN_ENHANCED) {
        const prefix: string = trimmed.substring(0, orderedPrefixLength);
        const bodySpans: MarkdownInlineSpan[] = parseInlineMarkdown(trimmed.substring(orderedPrefixLength));
        const spans: MarkdownInlineSpan[] = prependSpan(prefix, bodySpans);
        result.push({
          id: 'line_' + i,
          kind: MD_KIND_ORDERED,
          text: inlineText(spans),
          level: 0,
          spans: rekeySpans(spans)
        });
      } else {
        result.push(createPlainLine('line_' + i, MD_KIND_ORDERED, source, 0));
      }
      continue;
    }

    if (mode === MARKDOWN_ENHANCED) {
      result.push(createEnhancedLine('line_' + i, MD_KIND_TEXT, source, 0));
    } else {
      result.push(createPlainLine('line_' + i, MD_KIND_TEXT, source, 0));
    }
  }

  return result;
}

export function parseInlineMarkdown(text: string): MarkdownInlineSpan[] {
  return rekeySpans(parseStyledText(text, PLAIN_STYLE));
}

export function stripInlineMarkers(text: string): string {
  return inlineText(parseInlineMarkdown(text));
}

function createPlainLine(id: string, kind: string, text: string, level: number): MarkdownLine {
  const spans: MarkdownInlineSpan[] = text.length > 0 ? [createSpan(text, PLAIN_STYLE)] : [];
  return { id: id, kind: kind, text: text, level: level, spans: rekeySpans(spans) };
}

function createEnhancedLine(id: string, kind: string, source: string, level: number): MarkdownLine {
  const spans: MarkdownInlineSpan[] = parseInlineMarkdown(source);
  return { id: id, kind: kind, text: inlineText(spans), level: level, spans: spans };
}

function parseStyledText(text: string, inherited: InlineStyle): MarkdownInlineSpan[] {
  const result: MarkdownInlineSpan[] = [];
  let plain: string = '';
  let i: number = 0;

  const flushPlain = (): void => {
    if (plain.length > 0) {
      appendSpan(result, createSpan(plain, inherited));
      plain = '';
    }
  };

  while (i < text.length) {
    if (text.charAt(i) === '\\' && i + 1 < text.length) {
      plain += text.charAt(i + 1);
      i += 2;
      continue;
    }

    if (text.startsWith('***', i)) {
      const end: number = text.indexOf('***', i + 3);
      if (end > i + 3) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 3, end), withBoldItalic(inherited)));
        i = end + 3;
        continue;
      }
    }

    if (text.startsWith('___', i)) {
      const end: number = text.indexOf('___', i + 3);
      if (end > i + 3) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 3, end), withBoldItalic(inherited)));
        i = end + 3;
        continue;
      }
    }

    if (text.startsWith('**', i)) {
      const end: number = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 2, end), withBold(inherited)));
        i = end + 2;
        continue;
      }
    }

    if (text.startsWith('__', i)) {
      const end: number = text.indexOf('__', i + 2);
      if (end > i + 2) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 2, end), withBold(inherited)));
        i = end + 2;
        continue;
      }
    }

    if (text.startsWith('~~', i)) {
      const end: number = text.indexOf('~~', i + 2);
      if (end > i + 2) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 2, end), withStrike(inherited)));
        i = end + 2;
        continue;
      }
    }

    if (text.charAt(i) === '`') {
      const end: number = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        appendSpan(result, createSpan(text.substring(i + 1, end), withCode(inherited)));
        i = end + 1;
        continue;
      }
    }

    if (text.charAt(i) === '[') {
      const closeLabel: number = text.indexOf('](', i + 1);
      if (closeLabel > i + 1) {
        const closeUrl: number = text.indexOf(')', closeLabel + 2);
        if (closeUrl > closeLabel + 2) {
          flushPlain();
          const label: string = text.substring(i + 1, closeLabel);
          const url: string = text.substring(closeLabel + 2, closeUrl).trim();
          appendSpans(result, parseStyledText(label, withLink(inherited, url)));
          i = closeUrl + 1;
          continue;
        }
      }
    }

    if (text.charAt(i) === '*' && !text.startsWith('**', i)) {
      const end: number = text.indexOf('*', i + 1);
      if (end > i + 1) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 1, end), withItalic(inherited)));
        i = end + 1;
        continue;
      }
    }

    if (text.charAt(i) === '_') {
      const end: number = text.indexOf('_', i + 1);
      if (end > i + 1) {
        flushPlain();
        appendSpans(result, parseStyledText(text.substring(i + 1, end), withItalic(inherited)));
        i = end + 1;
        continue;
      }
    }

    const htmlResult: HtmlMatch | null = matchHtmlStyle(text, i, inherited);
    if (htmlResult !== null) {
      flushPlain();
      appendSpans(result, htmlResult.spans);
      i = htmlResult.nextIndex;
      continue;
    }

    plain += text.charAt(i);
    i += 1;
  }

  flushPlain();
  return result;
}

interface HtmlMatch {
  spans: MarkdownInlineSpan[];
  nextIndex: number;
}

function matchHtmlStyle(text: string, index: number, inherited: InlineStyle): HtmlMatch | null {
  const tagMatch: HtmlMatch | null = matchSimpleTag(text, index, '<b>', '</b>', withBold(inherited));
  if (tagMatch !== null) {
    return tagMatch;
  }
  const strongMatch: HtmlMatch | null = matchSimpleTag(text, index, '<strong>', '</strong>', withBold(inherited));
  if (strongMatch !== null) {
    return strongMatch;
  }
  const italicMatch: HtmlMatch | null = matchSimpleTag(text, index, '<i>', '</i>', withItalic(inherited));
  if (italicMatch !== null) {
    return italicMatch;
  }
  const emMatch: HtmlMatch | null = matchSimpleTag(text, index, '<em>', '</em>', withItalic(inherited));
  if (emMatch !== null) {
    return emMatch;
  }
  const strikeMatch: HtmlMatch | null = matchSimpleTag(text, index, '<s>', '</s>', withStrike(inherited));
  if (strikeMatch !== null) {
    return strikeMatch;
  }
  const delMatch: HtmlMatch | null = matchSimpleTag(text, index, '<del>', '</del>', withStrike(inherited));
  if (delMatch !== null) {
    return delMatch;
  }
  const underlineMatch: HtmlMatch | null = matchSimpleTag(text, index, '<u>', '</u>', withUnderline(inherited));
  if (underlineMatch !== null) {
    return underlineMatch;
  }
  const codeMatch: HtmlMatch | null = matchSimpleTag(text, index, '<code>', '</code>', withCode(inherited));
  if (codeMatch !== null) {
    return codeMatch;
  }
  return matchAnchorTag(text, index, inherited);
}

function matchSimpleTag(
  text: string,
  index: number,
  openTag: string,
  closeTag: string,
  style: InlineStyle
): HtmlMatch | null {
  if (!text.startsWith(openTag, index)) {
    return null;
  }
  const end: number = text.indexOf(closeTag, index + openTag.length);
  if (end < 0) {
    return null;
  }
  return {
    spans: parseStyledText(text.substring(index + openTag.length, end), style),
    nextIndex: end + closeTag.length
  };
}

function matchAnchorTag(text: string, index: number, inherited: InlineStyle): HtmlMatch | null {
  if (!text.startsWith('<a ', index)) {
    return null;
  }
  const openEnd: number = text.indexOf('>', index + 3);
  if (openEnd < 0) {
    return null;
  }
  const close: number = text.indexOf('</a>', openEnd + 1);
  if (close < 0) {
    return null;
  }
  const opening: string = text.substring(index, openEnd + 1);
  const url: string = extractHref(opening);
  if (url.length === 0) {
    return null;
  }
  return {
    spans: parseStyledText(text.substring(openEnd + 1, close), withLink(inherited, url)),
    nextIndex: close + 4
  };
}

function extractHref(opening: string): string {
  const doublePrefix: string = 'href="';
  const doubleStart: number = opening.indexOf(doublePrefix);
  if (doubleStart >= 0) {
    const start: number = doubleStart + doublePrefix.length;
    const end: number = opening.indexOf('"', start);
    return end > start ? opening.substring(start, end).trim() : '';
  }
  const singlePrefix: string = "href='";
  const singleStart: number = opening.indexOf(singlePrefix);
  if (singleStart >= 0) {
    const start: number = singleStart + singlePrefix.length;
    const end: number = opening.indexOf("'", start);
    return end > start ? opening.substring(start, end).trim() : '';
  }
  return '';
}

function parseTaskList(trimmed: string): TaskListMatch | null {
  if (trimmed.length < 7) {
    return null;
  }
  const marker: string = trimmed.charAt(0);
  if (marker !== '-' && marker !== '*' && marker !== '+') {
    return null;
  }
  let i: number = 1;
  while (i < trimmed.length && trimmed.charAt(i) === ' ') {
    i += 1;
  }
  if (i + 2 >= trimmed.length || trimmed.charAt(i) !== '[' || trimmed.charAt(i + 2) !== ']') {
    return null;
  }
  const state: string = trimmed.charAt(i + 1);
  if (state !== ' ' && state !== 'x' && state !== 'X') {
    return null;
  }
  i += 3;
  if (i >= trimmed.length || trimmed.charAt(i) !== ' ') {
    return null;
  }
  while (i < trimmed.length && trimmed.charAt(i) === ' ') {
    i += 1;
  }
  const body: string = trimmed.substring(i).trim();
  if (body.length === 0) {
    return null;
  }
  return { done: state !== ' ', body: body };
}

function strikeSpans(spans: MarkdownInlineSpan[]): MarkdownInlineSpan[] {
  const result: MarkdownInlineSpan[] = [];
  for (let i: number = 0; i < spans.length; i++) {
    const span: MarkdownInlineSpan = spans[i];
    result.push({
      id: span.id,
      text: span.text,
      bold: span.bold,
      italic: span.italic,
      strike: true,
      underline: span.underline,
      code: span.code,
      link: span.link
    });
  }
  return result;
}

function prependSpan(prefix: string, spans: MarkdownInlineSpan[]): MarkdownInlineSpan[] {
  const result: MarkdownInlineSpan[] = [];
  appendSpan(result, createSpan(prefix, PLAIN_STYLE));
  appendSpans(result, spans);
  return result;
}

function appendSpans(target: MarkdownInlineSpan[], source: MarkdownInlineSpan[]): void {
  for (let i: number = 0; i < source.length; i++) {
    appendSpan(target, source[i]);
  }
}

function appendSpan(target: MarkdownInlineSpan[], span: MarkdownInlineSpan): void {
  if (span.text.length === 0) {
    return;
  }
  if (target.length > 0 && sameStyle(target[target.length - 1], span)) {
    target[target.length - 1].text += span.text;
    return;
  }
  target.push(span);
}

function createSpan(text: string, style: InlineStyle): MarkdownInlineSpan {
  return {
    id: '',
    text: text,
    bold: style.bold,
    italic: style.italic,
    strike: style.strike,
    underline: style.underline,
    code: style.code,
    link: style.link
  };
}

function rekeySpans(spans: MarkdownInlineSpan[]): MarkdownInlineSpan[] {
  const result: MarkdownInlineSpan[] = [];
  for (let i: number = 0; i < spans.length; i++) {
    const span: MarkdownInlineSpan = spans[i];
    result.push({
      id: 'span_' + i,
      text: span.text,
      bold: span.bold,
      italic: span.italic,
      strike: span.strike,
      underline: span.underline,
      code: span.code,
      link: span.link
    });
  }
  return result;
}

function inlineText(spans: MarkdownInlineSpan[]): string {
  let result: string = '';
  for (let i: number = 0; i < spans.length; i++) {
    result += spans[i].text;
  }
  return result;
}

function sameStyle(left: MarkdownInlineSpan, right: MarkdownInlineSpan): boolean {
  return left.bold === right.bold && left.italic === right.italic && left.strike === right.strike &&
    left.underline === right.underline && left.code === right.code && left.link === right.link;
}

function copyStyle(style: InlineStyle): InlineStyle {
  return {
    bold: style.bold,
    italic: style.italic,
    strike: style.strike,
    underline: style.underline,
    code: style.code,
    link: style.link
  };
}

function withBold(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.bold = true;
  return result;
}

function withItalic(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.italic = true;
  return result;
}

function withBoldItalic(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.bold = true;
  result.italic = true;
  return result;
}

function withStrike(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.strike = true;
  return result;
}

function withUnderline(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.underline = true;
  return result;
}

function withCode(style: InlineStyle): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.code = true;
  return result;
}

function withLink(style: InlineStyle, url: string): InlineStyle {
  const result: InlineStyle = copyStyle(style);
  result.link = url;
  result.underline = true;
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

function isHorizontalRule(trimmed: string): boolean {
  if (trimmed.length < 3) {
    return false;
  }
  const marker: string = trimmed.charAt(0);
  if (marker !== '-' && marker !== '*' && marker !== '_') {
    return false;
  }
  for (let i: number = 1; i < trimmed.length; i++) {
    if (trimmed.charAt(i) !== marker) {
      return false;
    }
  }
  return true;
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
  if ((marker === '.' || marker === ')' || marker === '、') && space === ' ') {
    return i + 2;
  }
  return 0;
}
