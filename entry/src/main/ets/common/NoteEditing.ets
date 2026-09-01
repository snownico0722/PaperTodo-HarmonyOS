export interface NoteTextSelection {
  start: number;
  end: number;
}

export interface NoteEditResult {
  nextText: string;
  selection: NoteTextSelection;
  caret: number;
  handled: boolean;
}

interface MarkdownListPrefix {
  markerStart: number;
  contentStart: number;
  continuation: string;
}

const DEFAULT_LINK_LABEL: string = 'link';
const DEFAULT_LINK_TARGET: string = 'https://';

/**
 * Normalizes TextArea-style UTF-16 offsets without leaving a boundary inside a
 * surrogate pair or between the CR and LF of a CRLF delimiter.
 */
export function normalizeNoteSelection(text: string, selection: NoteTextSelection): NoteTextSelection {
  const rawStart: number = clampOffset(selection.start, text.length);
  const rawEnd: number = clampOffset(selection.end, text.length);
  const lower: number = Math.min(rawStart, rawEnd);
  const upper: number = Math.max(rawStart, rawEnd);
  if (lower === upper) {
    const caret: number = safeCaretBoundary(text, lower);
    return { start: caret, end: caret };
  }
  return {
    start: safeRangeStart(text, lower),
    end: safeRangeEnd(text, upper)
  };
}

export function applyMarkdownBold(text: string, selection: NoteTextSelection): NoteEditResult {
  return wrapMarkdownSelection(text, selection, '**', '**');
}

export function applyMarkdownItalic(text: string, selection: NoteTextSelection): NoteEditResult {
  return wrapMarkdownSelection(text, selection, '*', '*');
}

export function applyMarkdownCode(text: string, selection: NoteTextSelection): NoteEditResult {
  const safeSelection: NoteTextSelection = normalizeNoteSelection(text, selection);
  const selected: string = text.substring(safeSelection.start, safeSelection.end);
  const delimiter: string = firstLineBreak(selected);
  if (delimiter.length > 0) {
    return wrapMarkdownSelection(text, safeSelection, '```' + delimiter, delimiter + '```');
  }
  return wrapMarkdownSelection(text, safeSelection, '`', '`');
}

export function insertMarkdownLinePrefix(text: string, selection: NoteTextSelection,
  prefix: string): NoteEditResult {
  const safeSelection: NoteTextSelection = normalizeNoteSelection(text, selection);
  if (prefix.length === 0) {
    return unchangedResult(text, safeSelection);
  }

  const insertionOffsets: number[] = [];
  let lineStart: number = findLineStart(text, safeSelection.start);
  while (true) {
    insertionOffsets.push(lineStart);
    const lineEnd: number = findLineEnd(text, lineStart);
    const delimiter: string = newlineAt(text, lineEnd);
    if (delimiter.length === 0) {
      break;
    }
    const nextLineStart: number = lineEnd + delimiter.length;
    if (safeSelection.start === safeSelection.end || nextLineStart >= safeSelection.end) {
      break;
    }
    lineStart = nextLineStart;
  }

  let nextText: string = '';
  let sourceOffset: number = 0;
  for (let i: number = 0; i < insertionOffsets.length; i++) {
    const insertionOffset: number = insertionOffsets[i];
    nextText += text.substring(sourceOffset, insertionOffset) + prefix;
    sourceOffset = insertionOffset;
  }
  nextText += text.substring(sourceOffset);

  if (safeSelection.start === safeSelection.end) {
    const caret: number = safeSelection.start + prefix.length;
    return editResult(nextText, caret, caret, true);
  }
  const nextStart: number = safeSelection.start + prefix.length;
  const nextEnd: number = safeSelection.end + insertionOffsets.length * prefix.length;
  return editResult(nextText, nextStart, nextEnd, true);
}

export function wrapMarkdownSelection(text: string, selection: NoteTextSelection,
  prefix: string, suffix: string): NoteEditResult {
  const safeSelection: NoteTextSelection = normalizeNoteSelection(text, selection);
  const start: number = safeSelection.start;
  const end: number = safeSelection.end;
  const selected: string = text.substring(start, end);

  if (start === end) {
    const replacement: string = prefix + suffix;
    const caret: number = start + prefix.length;
    return editResult(text.substring(0, start) + replacement + text.substring(end), caret, caret, true);
  }

  if (hasLineBreak(selected) && !hasLineBreak(prefix) && !hasLineBreak(suffix)) {
    const replacement: string = wrapSelectedLines(selected, prefix, suffix);
    const nextText: string = text.substring(0, start) + replacement + text.substring(end);
    return editResult(nextText, start, start + replacement.length, true);
  }

  const replacement: string = prefix + selected + suffix;
  const nextText: string = text.substring(0, start) + replacement + text.substring(end);
  return editResult(nextText, start + prefix.length, start + prefix.length + selected.length, true);
}

export function insertMarkdownLink(text: string, selection: NoteTextSelection,
  defaultLabel: string = DEFAULT_LINK_LABEL, target: string = DEFAULT_LINK_TARGET): NoteEditResult {
  const safeSelection: NoteTextSelection = normalizeNoteSelection(text, selection);
  const selected: string = text.substring(safeSelection.start, safeSelection.end);
  if (hasLineBreak(selected)) {
    return unchangedResult(text, safeSelection);
  }
  const rawLabel: string = selected.trim().length > 0 ? selected : defaultLabel;
  const label: string = escapeMarkdownLinkLabel(rawLabel);
  const linkTarget: string = target.length > 0 ? target : DEFAULT_LINK_TARGET;
  const markdown: string = '[' + label + '](' + linkTarget + ')';
  const nextText: string = text.substring(0, safeSelection.start) + markdown +
    text.substring(safeSelection.end);
  const targetStart: number = safeSelection.start + label.length + 3;
  return editResult(nextText, targetStart, targetStart + linkTarget.length, true);
}

/**
 * Computes the result of pressing Enter in a Markdown list. A non-collapsed
 * selection or a caret before the list content is intentionally left to the
 * platform editor and returns handled=false.
 */
export function handleMarkdownListEnter(text: string, selection: NoteTextSelection): NoteEditResult {
  const safeSelection: NoteTextSelection = normalizeNoteSelection(text, selection);
  if (safeSelection.start !== safeSelection.end) {
    return unchangedResult(text, safeSelection);
  }

  const caret: number = safeSelection.start;
  const lineStart: number = findLineStart(text, caret);
  if (isInsideMarkdownCodeFence(text, lineStart)) {
    return unchangedResult(text, safeSelection);
  }
  const lineEnd: number = findLineEnd(text, caret);
  const line: string = text.substring(lineStart, lineEnd);
  const caretInLine: number = caret - lineStart;
  const list: MarkdownListPrefix | null = parseListPrefix(line);
  if (list === null || caretInLine < list.contentStart) {
    return unchangedResult(text, safeSelection);
  }

  if (line.substring(list.contentStart).trim().length === 0) {
    const removeStart: number = lineStart + list.markerStart;
    const removeEnd: number = lineStart + list.contentStart;
    const nextText: string = text.substring(0, removeStart) + text.substring(removeEnd);
    return editResult(nextText, removeStart, removeStart, true);
  }

  const delimiter: string = newlineForLine(text, lineStart, lineEnd);
  const insertion: string = delimiter + list.continuation;
  const nextText: string = text.substring(0, caret) + insertion + text.substring(caret);
  const nextCaret: number = caret + insertion.length;
  return editResult(nextText, nextCaret, nextCaret, true);
}

function parseListPrefix(line: string): MarkdownListPrefix | null {
  let markerStart: number = 0;
  while (markerStart < line.length && isIndentCharacter(line.charAt(markerStart))) {
    markerStart += 1;
  }
  if (markerStart >= line.length) {
    return null;
  }

  const marker: string = line.charAt(markerStart);
  if (marker === '-' || marker === '*' || marker === '+') {
    let contentStart: number = markerStart + 1;
    if (contentStart < line.length && !isLineWhitespace(line.charAt(contentStart))) {
      return null;
    }
    contentStart = skipLineWhitespace(line, contentStart);
    const markerSpacing: string = line.substring(markerStart + 1, contentStart);
    return withTaskListPrefix(line, markerStart, contentStart,
      line.substring(0, markerStart) + marker + (markerSpacing.length > 0 ? markerSpacing : ' '));
  }

  let delimiterIndex: number = markerStart;
  while (delimiterIndex < line.length && isAsciiDigit(line.charCodeAt(delimiterIndex))) {
    delimiterIndex += 1;
  }
  if (delimiterIndex === markerStart || delimiterIndex >= line.length) {
    return null;
  }
  const delimiter: string = line.charAt(delimiterIndex);
  if (delimiter !== '.' && delimiter !== ')' && delimiter !== '、') {
    return null;
  }
  let contentStart: number = delimiterIndex + 1;
  if (contentStart < line.length && !isLineWhitespace(line.charAt(contentStart))) {
    return null;
  }
  contentStart = skipLineWhitespace(line, contentStart);
  const nextNumber: string = incrementDecimal(line.substring(markerStart, delimiterIndex));
  const markerSpacing: string = line.substring(delimiterIndex + 1, contentStart);
  const continuation: string = line.substring(0, markerStart) + nextNumber + delimiter +
    (markerSpacing.length > 0 ? markerSpacing : ' ');
  return withTaskListPrefix(line, markerStart, contentStart, continuation);
}

function withTaskListPrefix(line: string, markerStart: number, contentStart: number,
  continuation: string): MarkdownListPrefix {
  if (contentStart + 2 < line.length && line.charAt(contentStart) === '[' &&
    line.charAt(contentStart + 2) === ']' && isTaskState(line.charAt(contentStart + 1))) {
    const taskContentStart: number = skipLineWhitespace(line, contentStart + 3);
    return {
      markerStart: markerStart,
      contentStart: taskContentStart,
      continuation: continuation + '[ ] '
    };
  }
  return {
    markerStart: markerStart,
    contentStart: contentStart,
    continuation: continuation
  };
}

function escapeMarkdownLinkLabel(value: string): string {
  let result: string = '';
  for (let i: number = 0; i < value.length; i++) {
    const current: string = value.charAt(i);
    if (current === '\\' || current === '[' || current === ']') {
      result += '\\';
    }
    result += current;
  }
  return result;
}

function isInsideMarkdownCodeFence(text: string, lineStart: number): boolean {
  let inCode: boolean = false;
  let cursor: number = 0;
  while (cursor < lineStart) {
    const lineEnd: number = findLineEnd(text, cursor);
    if (text.substring(cursor, lineEnd).trim().startsWith('```')) {
      inCode = !inCode;
    }
    const delimiter: string = newlineAt(text, lineEnd);
    if (delimiter.length === 0) {
      break;
    }
    cursor = lineEnd + delimiter.length;
  }
  return inCode;
}

function wrapSelectedLines(selected: string, prefix: string, suffix: string): string {
  let result: string = '';
  let index: number = 0;
  while (index < selected.length) {
    const lineStart: number = index;
    while (index < selected.length && selected.charAt(index) !== '\r' && selected.charAt(index) !== '\n') {
      index += 1;
    }
    const line: string = selected.substring(lineStart, index);
    result += line.trim().length === 0 ? line : prefix + line + suffix;
    if (index >= selected.length) {
      break;
    }
    if (selected.charAt(index) === '\r' && index + 1 < selected.length && selected.charAt(index + 1) === '\n') {
      result += '\r\n';
      index += 2;
    } else {
      result += selected.charAt(index);
      index += 1;
    }
  }
  return result;
}

function newlineForLine(text: string, lineStart: number, lineEnd: number): string {
  const following: string = newlineAt(text, lineEnd);
  if (following.length > 0) {
    return following;
  }
  if (lineStart > 0) {
    if (text.charAt(lineStart - 1) === '\n' && lineStart > 1 && text.charAt(lineStart - 2) === '\r') {
      return '\r\n';
    }
    const previous: string = text.charAt(lineStart - 1);
    if (previous === '\r' || previous === '\n') {
      return previous;
    }
  }
  for (let i: number = 0; i < text.length; i++) {
    const delimiter: string = newlineAt(text, i);
    if (delimiter.length > 0) {
      return delimiter;
    }
  }
  return '\n';
}

function newlineAt(text: string, offset: number): string {
  if (offset < 0 || offset >= text.length) {
    return '';
  }
  if (text.charAt(offset) === '\r') {
    return offset + 1 < text.length && text.charAt(offset + 1) === '\n' ? '\r\n' : '\r';
  }
  return text.charAt(offset) === '\n' ? '\n' : '';
}

function findLineStart(text: string, caret: number): number {
  let index: number = caret;
  while (index > 0) {
    const previous: string = text.charAt(index - 1);
    if (previous === '\r' || previous === '\n') {
      break;
    }
    index -= 1;
  }
  return index;
}

function findLineEnd(text: string, caret: number): number {
  let index: number = caret;
  while (index < text.length) {
    const value: string = text.charAt(index);
    if (value === '\r' || value === '\n') {
      break;
    }
    index += 1;
  }
  return index;
}

function incrementDecimal(value: string): string {
  const digits: string[] = value.split('');
  let carry: number = 1;
  for (let i: number = digits.length - 1; i >= 0 && carry > 0; i--) {
    const next: number = digits[i].charCodeAt(0) - 48 + carry;
    digits[i] = String.fromCharCode(48 + (next % 10));
    carry = next >= 10 ? 1 : 0;
  }
  return carry > 0 ? '1' + digits.join('') : digits.join('');
}

function safeCaretBoundary(text: string, offset: number): number {
  if (isInsideSurrogatePair(text, offset) || isInsideCrLf(text, offset)) {
    return Math.min(text.length, offset + 1);
  }
  return offset;
}

function safeRangeStart(text: string, offset: number): number {
  if (isInsideSurrogatePair(text, offset) || isInsideCrLf(text, offset)) {
    return Math.max(0, offset - 1);
  }
  return offset;
}

function safeRangeEnd(text: string, offset: number): number {
  if (isInsideSurrogatePair(text, offset) || isInsideCrLf(text, offset)) {
    return Math.min(text.length, offset + 1);
  }
  return offset;
}

function isInsideSurrogatePair(text: string, offset: number): boolean {
  if (offset <= 0 || offset >= text.length) {
    return false;
  }
  return isHighSurrogate(text.charCodeAt(offset - 1)) && isLowSurrogate(text.charCodeAt(offset));
}

function isInsideCrLf(text: string, offset: number): boolean {
  return offset > 0 && offset < text.length &&
    text.charAt(offset - 1) === '\r' && text.charAt(offset) === '\n';
}

function isHighSurrogate(value: number): boolean {
  return value >= 0xD800 && value <= 0xDBFF;
}

function isLowSurrogate(value: number): boolean {
  return value >= 0xDC00 && value <= 0xDFFF;
}

function isIndentCharacter(value: string): boolean {
  return value === ' ' || value === '\t';
}

function isLineWhitespace(value: string): boolean {
  return value !== '\r' && value !== '\n' && value.trim().length === 0;
}

function skipLineWhitespace(value: string, start: number): number {
  let index: number = start;
  while (index < value.length && isLineWhitespace(value.charAt(index))) {
    index += 1;
  }
  return index;
}

function isAsciiDigit(value: number): boolean {
  return value >= 48 && value <= 57;
}

function isTaskState(value: string): boolean {
  return value === ' ' || value === 'x' || value === 'X';
}

function hasLineBreak(value: string): boolean {
  return value.indexOf('\r') >= 0 || value.indexOf('\n') >= 0;
}

function firstLineBreak(value: string): string {
  for (let i: number = 0; i < value.length; i++) {
    if (value.charAt(i) === '\r') {
      return i + 1 < value.length && value.charAt(i + 1) === '\n' ? '\r\n' : '\r';
    }
    if (value.charAt(i) === '\n') {
      return '\n';
    }
  }
  return '';
}

function clampOffset(value: number, length: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.min(length, Math.floor(value)));
}

function unchangedResult(text: string, selection: NoteTextSelection): NoteEditResult {
  return editResult(text, selection.start, selection.end, false);
}

function editResult(nextText: string, selectionStart: number, selectionEnd: number,
  handled: boolean): NoteEditResult {
  return {
    nextText: nextText,
    selection: {
      start: selectionStart,
      end: selectionEnd
    },
    caret: selectionEnd,
    handled: handled
  };
}
