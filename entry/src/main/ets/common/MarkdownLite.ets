import { MARKDOWN_ENHANCED } from './Models';

export const MD_KIND_TEXT: string = 'text';
export const MD_KIND_HEADING: string = 'heading';
export const MD_KIND_BULLET: string = 'bullet';
export const MD_KIND_ORDERED: string = 'ordered';
export const MD_KIND_QUOTE: string = 'quote';
export const MD_KIND_CODE: string = 'code';
export const MD_KIND_RULE: string = 'rule';
export const MD_KIND_IMAGE: string = 'image';

export const MD_INLINE_TEXT: string = 'text';
export const MD_INLINE_CODE: string = 'code';
export const MD_INLINE_LINK: string = 'link';

/**
 * Inline presentation flags are kept separately from `kind` so nested marks
 * such as `**bold and _italic_**` do not lose either style.
 */
export interface MarkdownInlineStyle {
  bold: boolean;
  italic: boolean;
  strike: boolean;
  code: boolean;
}

/**
 * Ranges use half-open offsets. Source offsets point into the Markdown input;
 * display offsets point into the marker-free text produced by the token list.
 */
export interface MarkdownInlineToken {
  kind: string;
  text: string;
  sourceStart: number;
  sourceEnd: number;
  displayStart: number;
  displayEnd: number;
  style: MarkdownInlineStyle;
  linkUrl?: string;
  linkSourceStart?: number;
  linkSourceEnd?: number;
  linkDisplayStart?: number;
  linkDisplayEnd?: number;
}

export interface MarkdownLine {
  id: string;
  kind: string;
  text: string;
  level: number;
  linkUrl?: string;
  imageId?: string;
  imageAlt?: string;
  imagePercent?: number;
  /**
   * Optional explicit local-image dimensions. The current note surface still
   * sizes images proportionally, but retaining these values keeps the parser
   * compatible with PaperTodo notes that carry `320x180` metadata.
   */
  imageWidth?: number;
  imageHeight?: number;
  inlineTokens?: MarkdownInlineToken[];
}

interface MarkdownInlineParseState {
  source: string;
  tokens: MarkdownInlineToken[];
  displayLength: number;
}

interface MarkdownLinkMatch {
  labelStart: number;
  labelEnd: number;
  sourceEnd: number;
  url: string;
}

interface MarkdownHtmlTagMatch {
  name: string;
  openingEnd: number;
  closingStart: number;
  sourceEnd: number;
  href?: string;
}

interface MarkdownFence {
  character: string;
  length: number;
}

interface MarkdownImageInlineSize {
  width?: number;
  height?: number;
  percent?: number;
}

const INLINE_MAX_DEPTH: number = 24;

/**
 * Parses marker-free inline runs without changing the long-standing
 * `parseMarkdownLines` output. Consumers can therefore adopt rich rendering
 * independently while existing callers keep their current plain-text API.
 */
export function parseMarkdownInlineTokens(source: string): MarkdownInlineToken[] {
  const state: MarkdownInlineParseState = {
    source: source,
    tokens: [],
    displayLength: 0
  };
  parseInlineRange(state, 0, source.length, createInlineStyle(false, false, false, false),
    undefined, undefined, undefined, 0);
  return state.tokens;
}

/** Alias with a shorter name for UI callers. */
export function parseMarkdownInline(source: string): MarkdownInlineToken[] {
  return parseMarkdownInlineTokens(source);
}

function parseInlineRange(state: MarkdownInlineParseState, start: number, end: number,
  style: MarkdownInlineStyle, linkUrl: string | undefined, linkSourceStart: number | undefined,
  linkSourceEnd: number | undefined, depth: number): void {
  if (start >= end) {
    return;
  }
  if (depth > INLINE_MAX_DEPTH) {
    appendInlineToken(state, state.source.substring(start, end), start, end, style,
      linkUrl, linkSourceStart, linkSourceEnd);
    return;
  }

  let cursor: number = start;
  while (cursor < end) {
    const current: string = state.source.charAt(cursor);

    if (current === '\\' && cursor + 1 < end && isEscapableInlineCharacter(state.source.charAt(cursor + 1))) {
      appendInlineToken(state, state.source.charAt(cursor + 1), cursor, cursor + 2, style,
        linkUrl, linkSourceStart, linkSourceEnd);
      cursor += 2;
      continue;
    }

    if (current === '`') {
      const delimiterLength: number = countCharacterRun(state.source, cursor, end, '`');
      const delimiter: string = state.source.substring(cursor, cursor + delimiterLength);
      const codeEnd: number = findClosingRun(state.source, delimiter, cursor + delimiterLength, end);
      if (codeEnd >= 0) {
        const codeStyle: MarkdownInlineStyle = createInlineStyle(false, false, false, true);
        appendInlineToken(state, state.source.substring(cursor + delimiterLength, codeEnd),
          cursor + delimiterLength, codeEnd, codeStyle, linkUrl, linkSourceStart, linkSourceEnd);
        cursor = codeEnd + delimiterLength;
        continue;
      }
    }

    if (current === '<') {
      const htmlTag: MarkdownHtmlTagMatch | null = findSupportedHtmlTagAt(state.source, cursor, end);
      if (htmlTag !== null) {
        const htmlStyle: MarkdownInlineStyle = styleForHtmlTag(style, htmlTag.name);
        const firstTokenIndex: number = state.tokens.length;
        const linkDisplayStart: number = state.displayLength;
        if (htmlTag.name === 'code') {
          appendInlineToken(state, state.source.substring(htmlTag.openingEnd, htmlTag.closingStart),
            htmlTag.openingEnd, htmlTag.closingStart, htmlStyle, linkUrl,
            linkSourceStart, linkSourceEnd);
        } else {
          parseInlineRange(state, htmlTag.openingEnd, htmlTag.closingStart, htmlStyle,
            htmlTag.href === undefined ? linkUrl : htmlTag.href,
            htmlTag.href === undefined ? linkSourceStart : cursor,
            htmlTag.href === undefined ? linkSourceEnd : htmlTag.sourceEnd, depth + 1);
        }
        if (htmlTag.href !== undefined) {
          applyLinkDisplayRange(state.tokens, firstTokenIndex, htmlTag.href, cursor,
            linkDisplayStart, state.displayLength);
        }
        cursor = htmlTag.sourceEnd;
        continue;
      }
    }

    if (current === '[' && linkUrl === undefined) {
      const markdownLink: MarkdownLinkMatch | null = findMarkdownLinkAt(state.source, cursor, end);
      if (markdownLink !== null) {
        const firstTokenIndex: number = state.tokens.length;
        const linkDisplayStart: number = state.displayLength;
        parseInlineRange(state, markdownLink.labelStart, markdownLink.labelEnd, style,
          markdownLink.url, cursor, markdownLink.sourceEnd, depth + 1);
        applyLinkDisplayRange(state.tokens, firstTokenIndex, markdownLink.url, cursor,
          linkDisplayStart, state.displayLength);
        cursor = markdownLink.sourceEnd;
        continue;
      }
    }

    const styleMarker: string = findOpeningStyleMarker(state.source, cursor, end);
    if (styleMarker.length > 0) {
      const styleEnd: number = findClosingStyleMarker(state.source, styleMarker,
        cursor + styleMarker.length, end);
      if (styleEnd > cursor + styleMarker.length) {
        const nestedStyle: MarkdownInlineStyle = styleForMarker(style, styleMarker);
        parseInlineRange(state, cursor + styleMarker.length, styleEnd, nestedStyle,
          linkUrl, linkSourceStart, linkSourceEnd, depth + 1);
        cursor = styleEnd + styleMarker.length;
        continue;
      }
    }

    if (linkUrl === undefined && startsWithHttpUrl(state.source, cursor, end)) {
      const rawUrlEnd: number = findBareUrlEnd(state.source, cursor, end);
      const rawUrl: string = state.source.substring(cursor, rawUrlEnd);
      const bareUrl: string = trimUrlEnd(rawUrl);
      if (bareUrl.length > 0) {
        const bareEnd: number = cursor + bareUrl.length;
        const firstTokenIndex: number = state.tokens.length;
        const linkDisplayStart: number = state.displayLength;
        appendInlineToken(state, bareUrl, cursor, bareEnd, style, bareUrl, cursor, bareEnd);
        applyLinkDisplayRange(state.tokens, firstTokenIndex, bareUrl, cursor,
          linkDisplayStart, state.displayLength);
        cursor = bareEnd;
        continue;
      }
    }

    appendInlineToken(state, current, cursor, cursor + 1, style,
      linkUrl, linkSourceStart, linkSourceEnd);
    cursor += 1;
  }
}

function createInlineStyle(bold: boolean, italic: boolean, strike: boolean, code: boolean): MarkdownInlineStyle {
  return {
    bold: bold,
    italic: italic,
    strike: strike,
    code: code
  };
}

function styleForMarker(current: MarkdownInlineStyle, marker: string): MarkdownInlineStyle {
  const isBold: boolean = marker === '**' || marker === '__' || marker === '***' || marker === '___';
  const isItalic: boolean = marker === '*' || marker === '_' || marker === '***' || marker === '___';
  return createInlineStyle(current.bold || isBold, current.italic || isItalic,
    current.strike || marker === '~~', false);
}

function styleForHtmlTag(current: MarkdownInlineStyle, name: string): MarkdownInlineStyle {
  return createInlineStyle(current.bold || name === 'b' || name === 'strong',
    current.italic || name === 'i' || name === 'em',
    current.strike || name === 's' || name === 'del', current.code || name === 'code');
}

function appendInlineToken(state: MarkdownInlineParseState, text: string, sourceStart: number, sourceEnd: number,
  style: MarkdownInlineStyle, linkUrl: string | undefined, linkSourceStart: number | undefined,
  linkSourceEnd: number | undefined): void {
  if (text.length === 0) {
    return;
  }

  let kind: string = MD_INLINE_TEXT;
  if (style.code) {
    kind = MD_INLINE_CODE;
  } else if (linkUrl !== undefined) {
    kind = MD_INLINE_LINK;
  }

  const lastIndex: number = state.tokens.length - 1;
  if (lastIndex >= 0) {
    const last: MarkdownInlineToken = state.tokens[lastIndex];
    if (last.kind === kind && last.sourceEnd === sourceStart && last.displayEnd === state.displayLength &&
      sameInlineStyle(last.style, style) && last.linkUrl === linkUrl &&
      last.linkSourceStart === linkSourceStart && last.linkSourceEnd === linkSourceEnd &&
      last.linkDisplayStart === undefined && last.linkDisplayEnd === undefined) {
      last.text += text;
      last.sourceEnd = sourceEnd;
      last.displayEnd += text.length;
      state.displayLength += text.length;
      return;
    }
  }

  const token: MarkdownInlineToken = {
    kind: kind,
    text: text,
    sourceStart: sourceStart,
    sourceEnd: sourceEnd,
    displayStart: state.displayLength,
    displayEnd: state.displayLength + text.length,
    style: createInlineStyle(style.bold, style.italic, style.strike, style.code)
  };
  if (linkUrl !== undefined) {
    token.linkUrl = linkUrl;
    token.linkSourceStart = linkSourceStart;
    token.linkSourceEnd = linkSourceEnd;
  }
  state.tokens.push(token);
  state.displayLength += text.length;
}

function sameInlineStyle(left: MarkdownInlineStyle, right: MarkdownInlineStyle): boolean {
  return left.bold === right.bold && left.italic === right.italic &&
    left.strike === right.strike && left.code === right.code;
}

function applyLinkDisplayRange(tokens: MarkdownInlineToken[], firstTokenIndex: number, linkUrl: string,
  linkSourceStart: number, displayStart: number, displayEnd: number): void {
  for (let i: number = firstTokenIndex; i < tokens.length; i++) {
    const token: MarkdownInlineToken = tokens[i];
    if (token.linkUrl === linkUrl && token.linkSourceStart === linkSourceStart) {
      token.linkDisplayStart = displayStart;
      token.linkDisplayEnd = displayEnd;
    }
  }
}

function findOpeningStyleMarker(source: string, start: number, end: number): string {
  const triple: string = source.substring(start, Math.min(start + 3, end));
  if ((triple === '***' || triple === '___') && canOpenStyleMarker(source, start, 3, end)) {
    return triple;
  }
  const pair: string = source.substring(start, Math.min(start + 2, end));
  if ((pair === '**' || pair === '__' || pair === '~~') && canOpenStyleMarker(source, start, 2, end)) {
    return pair;
  }
  const single: string = source.charAt(start);
  if ((single === '*' || single === '_') && canOpenStyleMarker(source, start, 1, end)) {
    return single;
  }
  return '';
}

function canOpenStyleMarker(source: string, start: number, length: number, end: number): boolean {
  const contentStart: number = start + length;
  if (contentStart >= end || isWhitespaceCharacter(source.charAt(contentStart))) {
    return false;
  }
  if (source.charAt(start) === '_' && start > 0 && isWordCharacter(source.charAt(start - 1)) &&
    isWordCharacter(source.charAt(contentStart))) {
    return false;
  }
  return true;
}

function findClosingStyleMarker(source: string, marker: string, start: number, end: number): number {
  const markerCharacter: string = marker.charAt(0);
  let cursor: number = start;
  while (cursor < end) {
    if (source.charAt(cursor) === '\\') {
      cursor += 2;
      continue;
    }
    if (source.charAt(cursor) === '`') {
      const codeDelimiterLength: number = countCharacterRun(source, cursor, end, '`');
      const codeDelimiter: string = source.substring(cursor, cursor + codeDelimiterLength);
      const codeEnd: number = findClosingRun(source, codeDelimiter, cursor + codeDelimiterLength, end);
      if (codeEnd >= 0) {
        cursor = codeEnd + codeDelimiterLength;
        continue;
      }
    }
    if (source.charAt(cursor) !== markerCharacter) {
      cursor += 1;
      continue;
    }

    const runLength: number = countCharacterRun(source, cursor, end, markerCharacter);
    let candidate: number = -1;
    if (marker.length === 1) {
      if (runLength === 1) {
        candidate = cursor;
      } else if (runLength >= 3) {
        candidate = cursor + runLength - 1;
      }
    } else if (marker.length === 2) {
      if (runLength === 2) {
        candidate = cursor;
      } else if (runLength >= 3) {
        candidate = cursor + runLength - 2;
      }
    } else if (runLength >= 3) {
      candidate = cursor + runLength - 3;
    }

    if (candidate > start && candidate > 0 &&
      !isWhitespaceCharacter(source.charAt(candidate - 1))) {
      if (markerCharacter !== '_' || candidate + marker.length >= end ||
        !isWordCharacter(source.charAt(candidate + marker.length))) {
        return candidate;
      }
    }
    cursor += Math.max(1, runLength);
  }
  return -1;
}

function countCharacterRun(source: string, start: number, end: number, character: string): number {
  let cursor: number = start;
  while (cursor < end && source.charAt(cursor) === character) {
    cursor += 1;
  }
  return cursor - start;
}

function findClosingRun(source: string, delimiter: string, start: number, end: number): number {
  const delimiterCharacter: string = delimiter.charAt(0);
  let candidate: number = source.indexOf(delimiterCharacter, start);
  while (candidate >= 0 && candidate < end) {
    const runLength: number = countCharacterRun(source, candidate, end, delimiterCharacter);
    if (runLength === delimiter.length && (candidate === 0 || source.charAt(candidate - 1) !== '\\')) {
      return candidate;
    }
    candidate = source.indexOf(delimiterCharacter, candidate + Math.max(1, runLength));
  }
  return -1;
}

function findMarkdownLinkAt(source: string, start: number, end: number): MarkdownLinkMatch | null {
  if (source.charAt(start) !== '[') {
    return null;
  }
  let bracketDepth: number = 1;
  let labelEnd: number = -1;
  let cursor: number = start + 1;
  while (cursor < end) {
    const current: string = source.charAt(cursor);
    if (current === '\\') {
      cursor += 2;
      continue;
    }
    if (current === '[') {
      bracketDepth += 1;
    } else if (current === ']') {
      bracketDepth -= 1;
      if (bracketDepth === 0) {
        labelEnd = cursor;
        break;
      }
    }
    cursor += 1;
  }
  if (labelEnd <= start + 1 || labelEnd + 1 >= end || source.charAt(labelEnd + 1) !== '(') {
    return null;
  }

  const urlStart: number = labelEnd + 2;
  let parenthesisDepth: number = 1;
  cursor = urlStart;
  while (cursor < end) {
    const current: string = source.charAt(cursor);
    if (current === '\\') {
      cursor += 2;
      continue;
    }
    if (current === '(') {
      parenthesisDepth += 1;
    } else if (current === ')') {
      parenthesisDepth -= 1;
      if (parenthesisDepth === 0) {
        const rawUrl: string = source.substring(urlStart, cursor);
        if (!hasWhitespace(rawUrl)) {
          const url: string = trimUrlEnd(rawUrl);
          if (isHttpUrl(url)) {
            return {
              labelStart: start + 1,
              labelEnd: labelEnd,
              sourceEnd: cursor + 1,
              url: url
            };
          }
        }
        return null;
      }
    }
    cursor += 1;
  }
  return null;
}

/**
 * Finds a small, intentionally whitelisted, inline HTML element. This is not
 * an HTML parser: block tags, arbitrary tags, unquoted href values and remote
 * image markup remain plain text by design.
 */
function findSupportedHtmlTagAt(source: string, start: number, end: number): MarkdownHtmlTagMatch | null {
  const openingEnd: number = source.indexOf('>', start + 1);
  if (openingEnd < 0 || openingEnd >= end) {
    return null;
  }
  const opening: string = source.substring(start + 1, openingEnd);
  const nameMatch: RegExpMatchArray | null = opening.match(/^\s*(a|b|strong|i|em|s|del|u|code)\b/i);
  if (nameMatch === null || nameMatch.length < 2 || /\/\s*$/.test(opening)) {
    return null;
  }
  const name: string = nameMatch[1].toLowerCase();
  let href: string | undefined;
  if (name === 'a') {
    const hrefMatch: RegExpMatchArray | null = opening.match(/\bhref\s*=\s*(["'])(.*?)\1/i);
    if (hrefMatch === null || hrefMatch.length < 3) {
      return null;
    }
    const candidate: string = trimUrlEnd(hrefMatch[2]);
    if (!isHttpUrl(candidate)) {
      return null;
    }
    href = candidate;
  }

  const closing: string = '</' + name + '>';
  let cursor: number = openingEnd + 1;
  let nesting: number = 1;
  while (cursor < end) {
    const lower: string = source.substring(cursor, Math.min(end, cursor + closing.length)).toLowerCase();
    if (lower === closing) {
      nesting -= 1;
      if (nesting === 0) {
        const result: MarkdownHtmlTagMatch = {
          name: name,
          openingEnd: openingEnd + 1,
          closingStart: cursor,
          sourceEnd: cursor + closing.length
        };
        if (href !== undefined) {
          result.href = href;
        }
        return result;
      }
      cursor += closing.length;
      continue;
    }
    const nestedOpening: string = '<' + name;
    const nested: string = source.substring(cursor, Math.min(end, cursor + nestedOpening.length)).toLowerCase();
    if (nested === nestedOpening) {
      const next: string = source.charAt(cursor + nestedOpening.length);
      if (next === '>' || isWhitespaceCharacter(next)) {
        nesting += 1;
      }
    }
    cursor += 1;
  }
  return null;
}

function startsWithHttpUrl(source: string, start: number, end: number): boolean {
  const prefixEnd: number = Math.min(start + 8, end);
  const prefix: string = source.substring(start, prefixEnd).toLowerCase();
  return prefix.startsWith('http://') || prefix.startsWith('https://');
}

function isHttpUrl(value: string): boolean {
  const lower: string = value.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

function findBareUrlEnd(source: string, start: number, end: number): number {
  let cursor: number = start;
  while (cursor < end) {
    const current: string = source.charAt(cursor);
    if (isWhitespaceCharacter(current) || current === '<' || current === '>' || current === '"' ||
      current === '\'' || current === '`') {
      break;
    }
    cursor += 1;
  }
  return cursor;
}

function hasWhitespace(value: string): boolean {
  for (let i: number = 0; i < value.length; i++) {
    if (isWhitespaceCharacter(value.charAt(i))) {
      return true;
    }
  }
  return false;
}

function isWhitespaceCharacter(value: string): boolean {
  return value.length > 0 && value.charCodeAt(0) <= 32;
}

function isWordCharacter(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  const code: number = value.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

function isEscapableInlineCharacter(value: string): boolean {
  return value === '\\' || value === '`' || value === '*' || value === '_' || value === '~' ||
    value === '[' || value === ']' || value === '(' || value === ')';
}

export function parseMarkdownLines(content: string, mode: string): MarkdownLine[] {
  const sourceLines: string[] = content.replace(/\r\n/g, '\n').split('\n');
  const result: MarkdownLine[] = [];
  let inCode: boolean = false;
  let fence: MarkdownFence | undefined;

  for (let i: number = 0; i < sourceLines.length; i++) {
    const source: string = sourceLines[i];
    const trimmed: string = source.trim();

    const foundFence: MarkdownFence | null = findFence(trimmed);
    if (!inCode && foundFence !== null) {
      inCode = true;
      fence = foundFence;
      if (mode !== MARKDOWN_ENHANCED) {
        result.push({ id: 'line_' + i, kind: MD_KIND_CODE, text: source, level: 0 });
      }
      continue;
    }

    if (inCode) {
      if (fence !== undefined && isClosingFence(trimmed, fence)) {
        inCode = false;
        fence = undefined;
        if (mode !== MARKDOWN_ENHANCED) {
          result.push({ id: 'line_' + i, kind: MD_KIND_CODE, text: source, level: 0 });
        }
        continue;
      }
      result.push({ id: 'line_' + i, kind: MD_KIND_CODE, text: source, level: 0 });
      continue;
    }

    const imageLine: MarkdownLine | null = parseImageLine(trimmed, i);
    if (imageLine !== null) {
      result.push(imageLine);
      continue;
    }

    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      result.push({ id: 'line_' + i, kind: MD_KIND_RULE, text: '', level: 0 });
      continue;
    }

    const headingLevel: number = getHeadingLevel(source);
    if (headingLevel > 0) {
      let headingText: string = source;
      const headingSource: string = source.substring(headingLevel).trimStart();
      if (mode === MARKDOWN_ENHANCED) {
        headingText = headingSource;
        headingText = stripInlineMarkers(headingText);
      }
      result.push({
        id: 'line_' + i,
        kind: MD_KIND_HEADING,
        text: headingText,
        level: headingLevel,
        linkUrl: findClickableUrl(source),
        inlineTokens: enhancedInlineTokens(headingSource, mode)
      });
      continue;
    }

    if (trimmed.startsWith('> ')) {
      let quoteText: string = source;
      const quoteSource: string = trimmed.substring(2);
      if (mode === MARKDOWN_ENHANCED) {
        quoteText = quoteSource;
        quoteText = stripInlineMarkers(quoteText);
      }
      result.push({
        id: 'line_' + i,
        kind: MD_KIND_QUOTE,
        text: quoteText,
        level: 0,
        linkUrl: findClickableUrl(source),
        inlineTokens: enhancedInlineTokens(quoteSource, mode)
      });
      continue;
    }

    const bulletPrefixLength: number = getBulletPrefixLength(trimmed);
    if (bulletPrefixLength > 0) {
      let bulletText: string = source;
      const bulletSource: string = '• ' + trimmed.substring(bulletPrefixLength);
      if (mode === MARKDOWN_ENHANCED) {
        bulletText = '• ' + stripInlineMarkers(trimmed.substring(bulletPrefixLength));
      }
      result.push({
        id: 'line_' + i,
        kind: MD_KIND_BULLET,
        text: bulletText,
        level: 0,
        linkUrl: findClickableUrl(source),
        inlineTokens: enhancedInlineTokens(bulletSource, mode)
      });
      continue;
    }

    const orderedPrefixLength: number = getOrderedPrefixLength(trimmed);
    if (orderedPrefixLength > 0) {
      let orderedText: string = source;
      if (mode === MARKDOWN_ENHANCED) {
        orderedText = stripInlineMarkers(trimmed);
      }
      result.push({
        id: 'line_' + i,
        kind: MD_KIND_ORDERED,
        text: orderedText,
        level: 0,
        linkUrl: findClickableUrl(source),
        inlineTokens: enhancedInlineTokens(trimmed, mode)
      });
      continue;
    }

    result.push({
      id: 'line_' + i,
      kind: MD_KIND_TEXT,
      text: mode === MARKDOWN_ENHANCED ? stripInlineMarkers(source) : source,
      level: 0,
      linkUrl: findClickableUrl(source),
      inlineTokens: enhancedInlineTokens(source, mode)
    });
  }

  return result;
}

function findFence(trimmed: string): MarkdownFence | null {
  if (trimmed.length < 3) {
    return null;
  }
  const character: string = trimmed.charAt(0);
  if (character !== '`' && character !== '~') {
    return null;
  }
  const length: number = countCharacterRun(trimmed, 0, trimmed.length, character);
  if (length < 3) {
    return null;
  }
  return { character: character, length: length };
}

function isClosingFence(trimmed: string, fence: MarkdownFence): boolean {
  if (trimmed.length < fence.length || trimmed.charAt(0) !== fence.character) {
    return false;
  }
  const length: number = countCharacterRun(trimmed, 0, trimmed.length, fence.character);
  if (length < fence.length) {
    return false;
  }
  for (let i: number = length; i < trimmed.length; i++) {
    if (!isWhitespaceCharacter(trimmed.charAt(i))) {
      return false;
    }
  }
  return true;
}

function enhancedInlineTokens(source: string, mode: string): MarkdownInlineToken[] | undefined {
  if (mode !== MARKDOWN_ENHANCED) {
    return undefined;
  }
  return parseMarkdownInlineTokens(source);
}

function parseImageLine(trimmed: string, index: number): MarkdownLine | null {
  const match: RegExpMatchArray | null = trimmed.match(
    /^!\[([^|\]]*)(?:\|([^\]]+))?\]\(i:([A-Za-z0-9_-]+)\)(?:\{width=(\d{1,4})(%)?\})?$/
  );
  if (match === null || match.length < 4) {
    return null;
  }

  const inlineSize: string = match[2] === undefined ? '' : match[2].trim();
  const parsedInlineSize: MarkdownImageInlineSize | null = inlineSize.length === 0 ?
    {} : parseImageInlineSize(inlineSize);
  const suffixWidth: string = match[4] === undefined ? '' : match[4];
  const suffixIsPercent: boolean = match[5] === '%';
  const suffixPercent: number | undefined = suffixIsPercent ? parseImagePercent(suffixWidth + '%') : undefined;
  const suffixWidthNumber: number | undefined = !suffixIsPercent && suffixWidth.length > 0 ? Number(suffixWidth) : undefined;
  if (parsedInlineSize === null ||
    (suffixWidth.length > 0 && suffixPercent === undefined &&
      (suffixWidthNumber === undefined || !Number.isFinite(suffixWidthNumber) || suffixWidthNumber <= 0))) {
    return null;
  }

  const line: MarkdownLine = {
    id: 'line_' + index,
    kind: MD_KIND_IMAGE,
    text: '',
    level: 0,
    imageId: match[3],
    imageAlt: match[1].trim(),
    imagePercent: suffixPercent === undefined ?
      (parsedInlineSize.percent === undefined ? 100 : parsedInlineSize.percent) : suffixPercent
  };
  if (parsedInlineSize.width !== undefined) {
    line.imageWidth = parsedInlineSize.width;
    line.imageHeight = parsedInlineSize.height;
  }
  if (suffixWidthNumber !== undefined && !suffixIsPercent) {
    line.imageWidth = suffixWidthNumber;
  }
  return line;
}

function parseImageInlineSize(value: string): MarkdownImageInlineSize | null {
  const percent: number | undefined = parseImagePercent(value);
  if (percent !== undefined) {
    return { percent: percent };
  }
  const match: RegExpMatchArray | null = value.match(/^(\d{1,4})[x×](\d{1,4})(?:\s*,\s*(\d{1,3})%)?$/i);
  if (match === null || match.length < 3) {
    return null;
  }
  const width: number = Number(match[1]);
  const height: number = Number(match[2]);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return null;
  }
  const result: MarkdownImageInlineSize = { width: width, height: height };
  if (match[3] !== undefined && match[3].length > 0) {
    const parsedPercent: number | undefined = parseImagePercent(match[3] + '%');
    if (parsedPercent === undefined) {
      return null;
    }
    result.percent = parsedPercent;
  }
  return result;
}

function parseImagePercent(value: string): number | undefined {
  const match: RegExpMatchArray | null = value.match(/^(\d{1,3})%$/);
  if (match === null || match.length < 2) {
    return undefined;
  }
  const parsed: number = Number(match[1]);
  return Number.isFinite(parsed) ? Math.max(10, Math.min(100, parsed)) : undefined;
}

export function stripInlineMarkers(text: string): string {
  let result: string = text;
  result = result.replace(/<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)<\/a>/gi, '$2 ($1)');
  result = result.replace(/<\/?(?:b|strong|i|em|s|del|u|code)(?:\s+[^>]*)?>/gi, '');
  result = result.replace(/\*\*(.*?)\*\*/g, '$1');
  result = result.replace(/~~(.*?)~~/g, '$1');
  result = result.replace(/`([^`]*)`/g, '$1');
  result = result.replace(/\*([^*]+)\*/g, '$1');
  result = result.replace(/_([^_]+)_/g, '$1');
  result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)');
  return result;
}

export function findClickableUrl(source: string): string | undefined {
  const withoutInlineCode: string = removeInlineCodeSpans(source);
  const markdownUrl: string | undefined = findFirstMarkdownLinkUrl(source);
  if (markdownUrl !== undefined) {
    return markdownUrl;
  }

  const htmlLink = /<a\s+[^>]*href\s*=\s*["'](https?:\/\/[^"']+)["'][^>]*>/i.exec(withoutInlineCode);
  if (htmlLink !== null && htmlLink.length > 1) {
    return trimUrlEnd(htmlLink[1]);
  }

  const bareLink = /https?:\/\/[^\s<>"']+/i.exec(withoutInlineCode);
  if (bareLink === null || bareLink.length === 0) {
    return undefined;
  }
  const candidate: string = trimUrlEnd(bareLink[0]);
  return candidate.length > 0 ? candidate : undefined;
}

function removeInlineCodeSpans(source: string): string {
  let result: string = '';
  let cursor: number = 0;
  while (cursor < source.length) {
    if (source.charAt(cursor) === '`' && (cursor === 0 || source.charAt(cursor - 1) !== '\\')) {
      const delimiterLength: number = countCharacterRun(source, cursor, source.length, '`');
      const delimiter: string = source.substring(cursor, cursor + delimiterLength);
      const codeEnd: number = findClosingRun(source, delimiter, cursor + delimiterLength, source.length);
      if (codeEnd >= 0) {
        result += ' ';
        cursor = codeEnd + delimiterLength;
        continue;
      }
    }
    result += source.charAt(cursor);
    cursor += 1;
  }
  return result;
}

function findFirstMarkdownLinkUrl(source: string): string | undefined {
  let cursor: number = 0;
  while (cursor < source.length) {
    if (source.charAt(cursor) === '`') {
      const delimiterLength: number = countCharacterRun(source, cursor, source.length, '`');
      const delimiter: string = source.substring(cursor, cursor + delimiterLength);
      const codeEnd: number = findClosingRun(source, delimiter, cursor + delimiterLength, source.length);
      if (codeEnd >= 0) {
        cursor = codeEnd + delimiterLength;
        continue;
      }
    }
    if (source.charAt(cursor) === '[') {
      const markdownLink: MarkdownLinkMatch | null = findMarkdownLinkAt(source, cursor, source.length);
      if (markdownLink !== null) {
        return markdownLink.url;
      }
    }
    cursor += 1;
  }
  return undefined;
}

function trimUrlEnd(value: string): string {
  let result: string = value;
  while (result.length > 0) {
    const last: string = result.charAt(result.length - 1);
    if (last === '.' || last === ',' || last === '!' || last === '?' || last === ';' || last === ':' ||
      last === '。' || last === '，' || last === '！' || last === '？' || last === '；' || last === '：') {
      result = result.substring(0, result.length - 1);
      continue;
    }
    if (last === ')' && countCharacter(result, ')') > countCharacter(result, '(')) {
      result = result.substring(0, result.length - 1);
      continue;
    }
    if (last === ']' && countCharacter(result, ']') > countCharacter(result, '[')) {
      result = result.substring(0, result.length - 1);
      continue;
    }
    if (result.endsWith('**') || result.endsWith('__') || result.endsWith('~~')) {
      result = result.substring(0, result.length - 2);
      continue;
    }
    break;
  }
  return result;
}

function countCharacter(value: string, character: string): number {
  let count: number = 0;
  for (let i: number = 0; i < value.length; i++) {
    if (value.charAt(i) === character) {
      count += 1;
    }
  }
  return count;
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

function getBulletPrefixLength(trimmed: string): number {
  if (trimmed.length === 0) {
    return 0;
  }
  const marker: string = trimmed.charAt(0);
  if (marker !== '-' && marker !== '*' && marker !== '+') {
    return 0;
  }
  if (trimmed.length === 1) {
    return 1;
  }
  if (!isMarkdownListWhitespace(trimmed.charAt(1))) {
    return 0;
  }
  let contentStart: number = 2;
  while (contentStart < trimmed.length && isMarkdownListWhitespace(trimmed.charAt(contentStart))) {
    contentStart += 1;
  }
  return contentStart;
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
  if (i === 0 || i >= trimmed.length) {
    return 0;
  }
  const marker: string = trimmed.charAt(i);
  if (marker !== '.' && marker !== ')' && marker !== '、') {
    return 0;
  }
  let contentStart: number = i + 1;
  if (contentStart >= trimmed.length) {
    return contentStart;
  }
  if (!isMarkdownListWhitespace(trimmed.charAt(contentStart))) {
    return 0;
  }
  while (contentStart < trimmed.length && isMarkdownListWhitespace(trimmed.charAt(contentStart))) {
    contentStart += 1;
  }
  return contentStart;
}

function isMarkdownListWhitespace(value: string): boolean {
  return value.length > 0 && value.trim().length === 0;
}
