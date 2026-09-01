import { emitter } from '@kit.BasicServicesKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  THEME_DARK,
  THEME_LIGHT
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import { tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';
import {
  STATUS_EVENT_HIDE_ALL,
  STATUS_EVENT_NEW_NOTE,
  STATUS_EVENT_NEW_TODO,
  STATUS_EVENT_OPEN_SETTINGS,
  STATUS_EVENT_SHOW_ALL
} from '../common/StatusBarEvents';

@Entry
@Component
struct StatusBarPage {
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('uiLanguage') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') systemLanguage: string = 'zh-CN';
  @StorageLink('theme') theme: string = 'system';
  @StorageLink('colorScheme') colorScheme: string = 'warm';
  @StorageLink('systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
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
    emitter.emit({ eventId: eventId });
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
  }

  private isDark(): boolean {
    if (this.theme === THEME_DARK) {
      return true;
    }
    if (this.theme === THEME_LIGHT) {
      return false;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private palette(): ThemePalette {
    return resolvePalette(this.colorScheme, this.isDark());
  }

  private paperCount(type: string): number {
    let count: number = 0;
    for (let i: number = 0; i < this.papers.length; i++) {
      if (this.papers[i].type === type) {
        count += 1;
      }
    }
    return count;
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 1 }) {
          Text(this.text('app.name'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().text)
          Text(this.text('app.subtitle'))
            .fontSize(10)
            .fontColor(this.palette().muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button(this.text('action.settings'))
          .type(ButtonType.Normal)
          .height(28)
          .padding({ left: 10, right: 10 })
          .fontSize(11)
          .fontColor(this.palette().text)
          .backgroundColor(this.palette().paper)
          .border({ width: 1, color: this.palette().border })
          .borderRadius(8)
          .onClick((): void => this.emit(STATUS_EVENT_OPEN_SETTINGS))
      }
      .width('100%')

      Row({ space: 10 }) {
        Row({ space: 9 }) {
          Text(this.text('glyph.todo'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Column({ space: 1 }) {
            Text(this.paperCount(PAPER_TYPE_TODO).toString())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().text)
            Text(this.text('paper.todo'))
              .fontSize(11)
              .fontColor(this.palette().muted)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height(62)
        .padding({ left: 13, right: 12 })
        .backgroundColor(this.palette().paper)
        .border({ width: 1, color: this.palette().border })
        .borderRadius(12)

        Row({ space: 9 }) {
          Text(this.text('glyph.note'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Column({ space: 1 }) {
            Text(this.paperCount(PAPER_TYPE_NOTE).toString())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().text)
            Text(this.text('paper.note'))
              .fontSize(11)
              .fontColor(this.palette().muted)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height(62)
        .padding({ left: 13, right: 12 })
        .backgroundColor(this.palette().paper)
        .border({ width: 1, color: this.palette().border })
        .borderRadius(12)
      }
      .width('100%')

      Row({ space: 10 }) {
        Button(this.text('action.newTodo'))
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primaryText)
          .backgroundColor(this.palette().primary)
          .borderRadius(10)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_TODO))
        Button(this.text('action.newNote'))
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primaryText)
          .backgroundColor(this.palette().primary)
          .borderRadius(10)
          .onClick((): void => this.emit(STATUS_EVENT_NEW_NOTE))
      }
      .width('100%')

      Divider()
        .color(this.palette().border)
        .opacity(0.65)

      Row({ space: 10 }) {
        Button(this.text('action.showAll'))
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .fontColor(this.palette().text)
          .backgroundColor(this.palette().paper)
          .border({ width: 1, color: this.palette().border })
          .borderRadius(9)
          .onClick((): void => this.emit(STATUS_EVENT_SHOW_ALL))
        Button(this.text('action.hideAll'))
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .fontColor(this.palette().text)
          .backgroundColor(this.palette().paper)
          .border({ width: 1, color: this.palette().border })
          .borderRadius(9)
          .onClick((): void => this.emit(STATUS_EVENT_HIDE_ALL))
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.palette().pageBackground)
  }
}
