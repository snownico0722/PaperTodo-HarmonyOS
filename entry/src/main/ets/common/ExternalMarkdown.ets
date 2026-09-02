import { common, Want, wantConstant } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { NoteImageAsset, PaperData } from './Models';
import { NoteImageStore } from './NoteImageStore';
import { PaperStore } from './PaperStore';

export const EXTERNAL_MARKDOWN_DEPENDENCY_URI_BUDGET: number = 128 * 1024;

export interface ExternalMarkdownDocument {
  content: string;
  dependencyUris: string[];
}

export function rewriteExternalMarkdown(content: string,
  resolveImageUri: (assetId: string) => string): ExternalMarkdownDocument {
  const lines: string[] = content.split('\n');
  const output: string[] = [];
  const dependencyUris: string[] = [];
  let dependencyUriBytes: number = 0;
  let fenceMarker: string = '';

  for (let i: number = 0; i < lines.length; i++) {
    const line: string = lines[i];
    const hasCarriageReturn: boolean = line.endsWith('\r');
    const source: string = hasCarriageReturn ? line.substring(0, line.length - 1) : line;
    const trimmed: string = source.trim();
    const openingFence: string = markdownFenceMarker(trimmed);
    if (openingFence.length > 0) {
      if (fenceMarker.length === 0) {
        fenceMarker = openingFence;
      } else if (openingFence === fenceMarker) {
        fenceMarker = '';
      }
      output.push(source + (hasCarriageReturn ? '\r' : ''));
      continue;
    }

    let rewritten: string = source;
    if (fenceMarker.length === 0) {
      const match: RegExpMatchArray | null = source.match(
        /^(\s*!\[[^\]]*\]\()i:([A-Za-z0-9_-]+)(\)(?:\{width=\d{1,3}%\})?\s*)$/
      );
      if (match !== null && match.length >= 4) {
        const uri: string = resolveImageUri(match[2]);
        if (uri.length > 0) {
          rewritten = match[1] + uri + match[3];
          if (!containsString(dependencyUris, uri)) {
            dependencyUriBytes += uri.length;
            if (dependencyUriBytes > EXTERNAL_MARKDOWN_DEPENDENCY_URI_BUDGET) {
              throw new Error('external Markdown dependency URI budget exceeded');
            }
            dependencyUris.push(uri);
          }
        }
      }
    }
    output.push(rewritten + (hasCarriageReturn ? '\r' : ''));
  }

  return {
    content: output.join('\n'),
    dependencyUris: dependencyUris
  };
}

export class ExternalMarkdown {
  static async open(context: common.UIAbilityContext, paper: PaperData): Promise<void> {
    const document: ExternalMarkdownDocument = rewriteExternalMarkdown(
      paper.content,
      (assetId: string): string => ExternalMarkdown.resolveAssetUri(context, paper.id, assetId)
    );
    const path: string = context.cacheDir + '/' + ExternalMarkdown.fileName(paper);
    let outputFd: number = -1;
    try {
      const output: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      outputFd = output.fd;
      fileIo.writeSync(outputFd, document.content);
      fileIo.closeSync(outputFd);
      outputFd = -1;

      const parameters: Record<string, Object> = {};
      parameters[wantConstant.Params.PARAMS_STREAM] = document.dependencyUris;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(path),
        type: uniformTypeDescriptor.UniformDataType.MARKDOWN,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
        parameters: parameters
      };
      await context.startAbility(want);
    } finally {
      if (outputFd >= 0) {
        try {
          fileIo.closeSync(outputFd);
        } catch (error) {
          console.warn('close external Markdown failed: ' + String(error));
        }
      }
    }
  }

  static fileName(paper: PaperData): string {
    let safeTitle: string = '';
    const source: string = paper.title.trim();
    for (let i: number = 0; i < source.length && safeTitle.length < 48; i++) {
      const character: string = source.charAt(i);
      const code: number = source.charCodeAt(i);
      if (code >= 32 && character !== '/' && character !== '\\' && character !== ':' &&
        character !== '*' && character !== '?' && character !== '"' && character !== '<' &&
        character !== '>' && character !== '|') {
        safeTitle += character;
      }
    }
    if (safeTitle.length === 0) {
      safeTitle = 'PaperTodo';
    }
    const safeId: string = paper.id.replace(/[^a-zA-Z0-9_-]/g, '').substring(0, 24);
    return safeTitle + '-' + safeId + '.md';
  }

  private static resolveAssetUri(context: common.UIAbilityContext, paperId: string, assetId: string): string {
    const asset: NoteImageAsset | null = PaperStore.getNoteImageForPaper(assetId, paperId);
    if (asset === null || !NoteImageStore.assetExists(context, asset)) {
      return '';
    }
    return NoteImageStore.assetUri(context, asset);
  }
}

function markdownFenceMarker(trimmed: string): string {
  if (trimmed.startsWith('```')) {
    return '```';
  }
  if (trimmed.startsWith('~~~')) {
    return '~~~';
  }
  return '';
}

function containsString(values: string[], value: string): boolean {
  for (let i: number = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
}
