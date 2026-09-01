import { unifiedDataChannel } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

export const TODO_ITEM_UDMF_TYPE: string =
  'ApplicationDefined.com.snownico.papertodo.todo-item';
export const TODO_ITEM_PAYLOAD_VERSION: number = 1;

export interface TodoItemDragPayload {
  version: number;
  paperId: string;
  todoId: string;
}

export function createTodoItemDragData(paperId: string, todoId: string): unifiedDataChannel.UnifiedData {
  const payload: TodoItemDragPayload = {
    version: TODO_ITEM_PAYLOAD_VERSION,
    paperId: paperId,
    todoId: todoId
  };
  const record: unifiedDataChannel.ApplicationDefinedRecord =
    new unifiedDataChannel.ApplicationDefinedRecord();
  record.applicationDefinedType = TODO_ITEM_UDMF_TYPE;
  record.rawData = util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(payload));
  return new unifiedDataChannel.UnifiedData(record);
}

export function parseTodoItemDragRecord(record: unifiedDataChannel.UnifiedRecord): TodoItemDragPayload | null {
  if (record.getType() !== TODO_ITEM_UDMF_TYPE) {
    return null;
  }
  try {
    const applicationRecord: unifiedDataChannel.ApplicationDefinedRecord =
      record as unifiedDataChannel.ApplicationDefinedRecord;
    if (applicationRecord.applicationDefinedType !== TODO_ITEM_UDMF_TYPE) {
      return null;
    }
    const raw: string = util.TextDecoder.create('utf-8').decodeToString(applicationRecord.rawData);
    const payload: TodoItemDragPayload = JSON.parse(raw) as TodoItemDragPayload;
    if (payload.version !== TODO_ITEM_PAYLOAD_VERSION || typeof payload.paperId !== 'string' ||
      payload.paperId.trim().length === 0 || payload.paperId.length > 256 || typeof payload.todoId !== 'string' ||
      payload.todoId.trim().length === 0 || payload.todoId.length > 256) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}
