import { emitter } from '@kit.BasicServicesKit';
import {
  STATUS_EVENT_HIDE_ALL,
  STATUS_EVENT_NEW_NOTE,
  STATUS_EVENT_NEW_TODO,
  STATUS_EVENT_OPEN_MANAGER,
  STATUS_EVENT_SHOW_ALL
} from '../common/StatusBarEvents';

@Entry
@Component
struct StatusBarPage {
  private emit(eventId: number): void {
    const event: emitter.InnerEvent = { eventId: eventId };
    emitter.emit(event);
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('PaperTodo')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button('管理')
          .height(30)
          .fontSize(11)
          .onClick((): void => this.emit(STATUS_EVENT_OPEN_MANAGER))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('☑ 新建待办')
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_TODO))
        Button('✎ 新建笔记')
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_NOTE))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('显示全部')
          .layoutWeight(1)
          .height(34)
          .fontSize(11)
          .onClick((): void => this.emit(STATUS_EVENT_SHOW_ALL))
        Button('隐藏全部')
          .layoutWeight(1)
          .height(34)
          .fontSize(11)
          .onClick((): void => this.emit(STATUS_EVENT_HIDE_ALL))
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
  }
}
