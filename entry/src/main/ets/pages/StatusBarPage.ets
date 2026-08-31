import { emitter } from '@kit.BasicServicesKit';
import { PAPER_TYPE_NOTE, PaperData } from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import {
  STATUS_EVENT_HIDE_ALL,
  STATUS_EVENT_NEW_NOTE,
  STATUS_EVENT_NEW_TODO,
  STATUS_EVENT_OPEN_MANAGER,
  STATUS_EVENT_SHOW_ALL,
  STATUS_EVENT_TOGGLE_PAPER
} from '../common/StatusBarEvents';

@Entry
@Component
struct StatusBarPage {
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @State papers: PaperData[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  private onPaperRevision(): void {
    this.refresh();
  }

  private refresh(): void {
    this.papers = PaperStore.listPapers();
  }

  private emit(eventId: number): void {
    const event: emitter.InnerEvent = { eventId: eventId };
    emitter.emit(event);
  }

  private togglePaper(paperId: string): void {
    const event: emitter.InnerEvent = { eventId: STATUS_EVENT_TOGGLE_PAPER };
    const data: emitter.EventData = {
      data: {
        paperId: paperId
      }
    };
    emitter.emit(event, data);
  }

  private paperTitle(paper: PaperData): string {
    if (paper.title.trim().length > 0) {
      return paper.title.trim();
    }
    if (paper.type === PAPER_TYPE_NOTE) {
      const firstLine: string = paper.content.split('\n')[0].trim();
      return firstLine.length > 0 ? firstLine.slice(0, 24) : '未命名笔记';
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      if (paper.items[i].text.trim().length > 0) {
        return paper.items[i].text.trim().slice(0, 24);
      }
    }
    return '未命名待办';
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('PaperTodo')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button('管理')
          .height(28)
          .fontSize(10)
          .onClick((): void => this.emit(STATUS_EVENT_OPEN_MANAGER))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('☑ 新建待办')
          .layoutWeight(1)
          .height(34)
          .fontSize(11)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_TODO))
        Button('✎ 新建笔记')
          .layoutWeight(1)
          .height(34)
          .fontSize(11)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_NOTE))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('显示全部')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .onClick((): void => this.emit(STATUS_EVENT_SHOW_ALL))
        Button('隐藏全部')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .onClick((): void => this.emit(STATUS_EVENT_HIDE_ALL))
      }
      .width('100%')

      Divider().opacity(0.45)

      if (this.papers.length === 0) {
        Text('还没有纸片')
          .width('100%')
          .height(76)
          .fontSize(11)
          .fontColor('#777777')
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 3 }) {
          ForEach(this.papers, (paper: PaperData) => {
            ListItem() {
              Row({ space: 6 }) {
                Text(paper.type === PAPER_TYPE_NOTE ? '✎' : '☑')
                  .width(20)
                  .fontSize(12)
                Text(this.paperTitle(paper))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontSize(11)
                Text(paper.isVisible ? '●' : '○')
                  .fontSize(11)
                  .opacity(paper.isVisible ? 1 : 0.55)
              }
              .width('100%')
              .height(32)
              .padding({ left: 8, right: 8 })
              .borderRadius(7)
              .onClick((): void => this.togglePaper(paper.id))
            }
          }, (paper: PaperData): string => paper.id)
        }
        .width('100%')
        .height(150)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
  }
}
