import { unifiedDataChannel } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

export const PAPER_LINK_UDMF_TYPE: string =
  'ApplicationDefined.com.snownico.papertodo.paper-link';
export const PAPER_LINK_PAYLOAD_VERSION: number = 1;

export interface PaperLinkDragPayload {
  version: number;
  paperId: string;
  paperType: string;
  title: string;
}

function isSupportedPaperType(type: string): boolean {
  return type === 'todo' || type === 'note';
}

export function createPaperLinkDragData(paperId: string, paperType: string,
  title: string): unifiedDataChannel.UnifiedData {
  const payload: PaperLinkDragPayload = {
    version: PAPER_LINK_PAYLOAD_VERSION,
    paperId: paperId,
    paperType: paperType,
    title: title
  };
  const record: unifiedDataChannel.ApplicationDefinedRecord =
    new unifiedDataChannel.ApplicationDefinedRecord();
  record.applicationDefinedType = PAPER_LINK_UDMF_TYPE;
  record.rawData = util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(payload));

  const data: unifiedDataChannel.UnifiedData = new unifiedDataChannel.UnifiedData(record);
  const plainText: unifiedDataChannel.PlainText = new unifiedDataChannel.PlainText();
  plainText.textContent = title;
  plainText.abstract = paperId;
  data.addRecord(plainText);
  return data;
}

export function parsePaperLinkDragRecord(record: unifiedDataChannel.UnifiedRecord): PaperLinkDragPayload | null {
  if (record.getType() !== PAPER_LINK_UDMF_TYPE) {
    return null;
  }
  try {
    const applicationRecord: unifiedDataChannel.ApplicationDefinedRecord =
      record as unifiedDataChannel.ApplicationDefinedRecord;
    if (applicationRecord.applicationDefinedType !== PAPER_LINK_UDMF_TYPE) {
      return null;
    }
    const raw: string = util.TextDecoder.create('utf-8').decodeToString(applicationRecord.rawData);
    const payload: PaperLinkDragPayload = JSON.parse(raw) as PaperLinkDragPayload;
    if (payload.version !== PAPER_LINK_PAYLOAD_VERSION || typeof payload.paperId !== 'string' ||
      payload.paperId.trim().length === 0 || payload.paperId.length > 256 || typeof payload.paperType !== 'string' ||
      !isSupportedPaperType(payload.paperType) || typeof payload.title !== 'string' || payload.title.length > 2000) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}
