import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import {
  CAPSULE_HEIGHT,
  CAPSULE_WIDTH,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM
} from '../common/Models';
import {
  MarkdownLine,
  MD_KIND_BULLET,
  MD_KIND_CODE,
  MD_KIND_HEADING,
  MD_KIND_ORDERED,
  MD_KIND_QUOTE,
  MD_KIND_RULE,
  parseMarkdownLines
} from '../common/MarkdownLite';
import { PaperStore } from '../common/PaperStore';

@Entry
@Component
struct Paper {
  @LocalStorageProp('paperId') paperId: string = '';
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('markdownRenderMode') @Watch('onMarkdownModeChanged') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onDeepCapsuleChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State title: string = '';
  @State items: PaperItem[] = [];
  @State content: string = '';
  @State draft: string = '';
  @State isNoteBrowsing: boolean = true;
  @State alwaysOnTop: boolean = false;
  @State isCollapsed: boolean = false;
  @State markdownLines: MarkdownLine[] = [];
  @State deleteConfirm: boolean = false;

  private paper: PaperData | null = null;
  private moveBaseX: number = 0;
  private moveBaseY: number = 0;
  private moveCurrentX: number = 0;
  private moveCurrentY: number = 0;
  private resizeBaseWidth: number = 0;
  private resizeBaseHeight: number = 0;
  private resizeCurrentWidth: number = 0;
  private resizeCurrentHeight: number = 0;

  aboutToAppear(): void {
    this.reloadPaper();
  }

  private reloadPaper(): void {
    const loaded: PaperData | null = PaperStore.getPaper(this.paperId);
    if (loaded === null) {
      return;
    }
    this.paper = loaded;
    this.title = loaded.title;
    this.items = loaded.items;
    this.content = loaded.content;
    this.alwaysOnTop = loaded.alwaysOnTop;
    this.isCollapsed = loaded.isCollapsed && this.useCapsuleMode;
    this.refreshMarkdown();
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      setTimeout((): void => this.snapCapsule(false), 120);
    }
  }

  private savePaper(): void {
    if (this.paper === null) {
      return;
    }
    this.paper.title = this.title;
    this.paper.items = this.items;
    this.paper.content = this.content;
    this.paper.alwaysOnTop = this.alwaysOnTop;
    this.paper.isCollapsed = this.isCollapsed;
    PaperStore.updatePaper(this.paper);
  }

  private currentWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('paperWindow:' + this.paperId);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  private paperColor(): string {
    return this.isDark() ? '#2C2A24' : '#FFF4C7';
  }

  private textColor(): string {
    return this.isDark() ? '#F2EBD7' : '#28251F';
  }

  private mutedColor(): string {
    return this.isDark() ? '#AFA895' : '#746D5D';
  }

  private paperBorderColor(): string {
    return this.isDark() ? '#565044' : '#D8CDA5';
  }

  private inputColor(): string {
    return this.isDark() ? '#39362F' : '#FFFDF4';
  }

  private typeLabel(): string {
    if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
      return '✎';
    }
    return '☑';
  }

  private titleOrFallback(): string {
    if (this.title.trim().length > 0) {
      return this.title.trim();
    }
    if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
      return '笔记';
    }
    const unfinished: number = this.unfinishedCount();
    return unfinished > 0 ? '待办 ' + unfinished.toString() : '待办';
  }

  private unfinishedCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.items.length; i++) {
      if (!this.items[i].done) {
        count += 1;
      }
    }
    return count;
  }

  private completedCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].done) {
        count += 1;
      }
    }
    return count;
  }

  private toggleTopmost(): void {
    this.alwaysOnTop = !this.alwaysOnTop;
    this.savePaper();
    const win: window.Window | undefined = this.currentWindow();
    if (win !== undefined) {
      win.setWindowTopmost(this.alwaysOnTop).catch((error: BusinessError): void => {
        console.error('setWindowTopmost failed: ' + error.message);
      });
    }
  }

  private hidePaper(): void {
    if (this.paper === null) {
      return;
    }
    this.paper.isVisible = false;
    this.savePaper();
    this.hostContext().terminateSelf();
  }

  private deletePaper(): void {
    if (!this.deleteConfirm) {
      this.deleteConfirm = true;
      return;
    }
    PaperStore.deletePaper(this.paperId);
    this.hostContext().terminateSelf();
  }

  private createPaper(type: string): void {
    const created: PaperData = PaperStore.createPaper(type);
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: created.id,
        paperCommand: 'show'
      }
    };
    this.hostContext().startAbility(want).catch((error: BusinessError): void => {
      console.error('start new paper failed: ' + error.message);
    });
  }

  private cycleTheme(): void {
    if (this.theme === THEME_SYSTEM) {
      PaperStore.setTheme(THEME_LIGHT);
    } else if (this.theme === THEME_LIGHT) {
      PaperStore.setTheme(THEME_DARK);
    } else {
      PaperStore.setTheme(THEME_SYSTEM);
    }
  }

  private cycleMarkdownMode(): void {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      PaperStore.setMarkdownMode(MARKDOWN_BASIC);
    } else if (this.markdownRenderMode === MARKDOWN_BASIC) {
      PaperStore.setMarkdownMode(MARKDOWN_ENHANCED);
    } else {
      PaperStore.setMarkdownMode(MARKDOWN_OFF);
    }
  }

  private markdownModeLabel(): string {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      return 'MD×';
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return 'MD';
    }
    return 'MD+';
  }

  private onMarkdownModeChanged(): void {
    this.refreshMarkdown();
  }

  private onDeepCapsuleChanged(): void {
    if (this.isCollapsed) {
      this.snapCapsule(false);
    }
  }

  private setCollapsed(collapsed: boolean): void {
    if (collapsed && !this.useCapsuleMode) {
      return;
    }
    if (this.paper === null) {
      return;
    }
    this.isCollapsed = collapsed;
    this.paper.isCollapsed = collapsed;
    this.savePaper();

    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    if (collapsed) {
      win.resize(CAPSULE_WIDTH, CAPSULE_HEIGHT);
      if (this.useDeepCapsuleMode) {
        setTimeout((): void => this.snapCapsule(false), 80);
      }
    } else {
      win.resize(Math.round(this.paper.width), Math.round(this.paper.height));
      win.moveWindowTo(Math.round(this.paper.x), Math.round(this.paper.y));
    }
  }

  private snapCapsule(hovered: boolean): void {
    if (!this.isCollapsed || !this.useDeepCapsuleMode) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const screen: display.Display = display.getDefaultDisplaySync();
    const hidden: number = hovered ? 0 : Math.round(CAPSULE_WIDTH * 0.45);
    const targetX: number = screen.width - CAPSULE_WIDTH + hidden;
    const index: number = PaperStore.getCollapsedIndex(this.paperId);
    const targetY: number = 20 + index * (CAPSULE_HEIGHT + 8);
    win.moveWindowTo(targetX, targetY);
  }

  private beginMove(): void {
    if (this.paper === null) {
      return;
    }
    this.moveBaseX = this.paper.x;
    this.moveBaseY = this.paper.y;
    this.moveCurrentX = this.paper.x;
    this.moveCurrentY = this.paper.y;
  }

  private updateMove(event: GestureEvent): void {
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.moveCurrentX = Math.round(this.moveBaseX + event.offsetX);
    this.moveCurrentY = Math.round(this.moveBaseY + event.offsetY);
    win.moveWindowTo(this.moveCurrentX, this.moveCurrentY);
  }

  private endMove(): void {
    if (this.paper === null) {
      return;
    }
    this.paper.x = this.moveCurrentX;
    this.paper.y = this.moveCurrentY;
    PaperStore.updatePaper(this.paper);
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      this.snapCapsule(false);
    }
  }

  private beginResize(): void {
    if (this.paper === null) {
      return;
    }
    this.resizeBaseWidth = this.paper.width;
    this.resizeBaseHeight = this.paper.height;
    this.resizeCurrentWidth = this.paper.width;
    this.resizeCurrentHeight = this.paper.height;
  }

  private updateResize(event: GestureEvent): void {
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.resizeCurrentWidth = Math.max(PAPER_MIN_WIDTH, Math.round(this.resizeBaseWidth + event.offsetX));
    this.resizeCurrentHeight = Math.max(PAPER_MIN_HEIGHT, Math.round(this.resizeBaseHeight + event.offsetY));
    win.resize(this.resizeCurrentWidth, this.resizeCurrentHeight);
  }

  private endResize(): void {
    if (this.paper === null) {
      return;
    }
    this.paper.width = this.resizeCurrentWidth;
    this.paper.height = this.resizeCurrentHeight;
    PaperStore.updatePaper(this.paper);
  }

  private toggleTodo(id: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push({
        id: item.id,
        text: item.text,
        done: item.id === id ? !item.done : item.done,
        order: i
      });
    }
    this.items = next;
    this.savePaper();
  }

  private updateTodoText(id: string, text: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push({ id: item.id, text: item.id === id ? text : item.text, done: item.done, order: i });
    }
    this.items = next;
    this.savePaper();
  }

  private deleteTodo(id: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        const item: PaperItem = this.items[i];
        next.push({ id: item.id, text: item.text, done: item.done, order: next.length });
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper();
  }

  private insertTodoAfter(id: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push({ id: item.id, text: item.text, done: item.done, order: next.length });
      if (item.id === id) {
        next.push(PaperStore.createTodoItem('', next.length));
      }
    }
    this.items = next;
    this.savePaper();
  }

  private clearCompleted(): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (!this.items[i].done) {
        const item: PaperItem = this.items[i];
        next.push({ id: item.id, text: item.text, done: false, order: next.length });
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper();
  }

  private moveTodo(from: number, to: number): void {
    if (from < 0 || from >= this.items.length || to < 0 || to >= this.items.length || from === to) {
      return;
    }
    const next: PaperItem[] = this.items.slice();
    const moved: PaperItem[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    for (let i: number = 0; i < next.length; i++) {
      next[i].order = i;
    }
    this.items = next;
    this.savePaper();
  }

  private addDraftTodos(): void {
    const raw: string = this.draft.replace(/\r\n/g, '\n');
    const lines: string[] = raw.split('\n');
    const next: PaperItem[] = this.items.slice();
    let added: number = 0;
    for (let i: number = 0; i < lines.length; i++) {
      const cleaned: string = this.cleanTodoPrefix(lines[i]).trim();
      if (cleaned.length === 0) {
        continue;
      }
      next.push(PaperStore.createTodoItem(cleaned, next.length));
      added += 1;
    }
    if (added === 0 && raw.trim().length === 0) {
      next.push(PaperStore.createTodoItem('', next.length));
    }
    this.items = next;
    this.draft = '';
    this.savePaper();
  }

  private cleanTodoPrefix(text: string): string {
    let result: string = text.trim();
    result = result.replace(/^[-*+]\s+/, '');
    result = result.replace(/^\d+[.、]\s*/, '');
    result = result.replace(/^[-*+]\s*\[[ xX]\]\s*/, '');
    result = result.replace(/^[☐☑✓]\s*/, '');
    return result;
  }

  private updateNote(value: string): void {
    this.content = value;
    this.savePaper();
  }

  private toggleNoteBrowse(): void {
    this.isNoteBrowsing = !this.isNoteBrowsing;
    this.refreshMarkdown();
  }

  private refreshMarkdown(): void {
    this.markdownLines = parseMarkdownLines(this.content, this.markdownRenderMode);
  }

  private appendMarkdown(snippet: string): void {
    if (this.content.length > 0 && !this.content.endsWith('\n')) {
      this.content += '\n';
    }
    this.content += snippet;
    this.savePaper();
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return 26;
    }
    if (level === 2) {
      return 22;
    }
    if (level === 3) {
      return 19;
    }
    return 16;
  }

  @Builder
  private HeaderBar() {
    Row({ space: 4 }) {
      Text('⋮⋮')
        .width(26)
        .height(30)
        .fontSize(16)
        .fontColor(this.mutedColor())
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginMove())
            .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
            .onActionEnd((): void => this.endMove())
        )

      Button(this.alwaysOnTop ? this.typeLabel() : '○')
        .width(30)
        .height(30)
        .fontSize(14)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.toggleTopmost())

      TextInput({
        text: this.title,
        placeholder: this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ? '笔记' : '待办'
      })
        .layoutWeight(1)
        .height(30)
        .fontSize(14)
        .fontColor(this.textColor())
        .placeholderColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string): void => {
          this.title = value;
          this.savePaper();
        })

      if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
        Button(this.isNoteBrowsing ? '编' : '览')
          .width(30)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.toggleNoteBrowse())
        Button(this.markdownModeLabel())
          .width(38)
          .height(30)
          .fontSize(10)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.cycleMarkdownMode())
      }

      Button('◐')
        .width(30)
        .height(30)
        .fontSize(12)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.cycleTheme())

      if (this.useCapsuleMode) {
        Button('▁')
          .width(30)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.setCollapsed(true))
      }

      Button('☑+')
        .width(34)
        .height(30)
        .fontSize(10)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.createPaper(PAPER_TYPE_TODO))

      Button('✎+')
        .width(34)
        .height(30)
        .fontSize(10)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))

      Button('—')
        .width(28)
        .height(30)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.hidePaper())

      Button(this.deleteConfirm ? '确认' : '×')
        .width(this.deleteConfirm ? 42 : 28)
        .height(30)
        .fontSize(this.deleteConfirm ? 10 : 14)
        .fontColor(this.deleteConfirm ? '#B42318' : this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.deletePaper())
    }
    .width('100%')
    .height(34)
    .padding({ left: 6, right: 6 })
  }

  @Builder
  private TodoBody() {
    Column() {
      Row() {
        Text(this.completedCount().toString() + '/' + this.items.length.toString())
          .fontSize(11)
          .fontColor(this.mutedColor())
        Blank()
        Button('清已完成')
          .height(28)
          .fontSize(10)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.clearCompleted())
      }
      .width('100%')
      .height(30)
      .padding({ left: 10, right: 8 })

      List({ space: 2 }) {
        ForEach(this.items, (item: PaperItem) => {
          ListItem() {
            Row({ space: 6 }) {
              Button(item.done ? '✓' : '')
                .width(26)
                .height(26)
                .fontSize(13)
                .fontColor(item.done ? this.paperColor() : this.textColor())
                .backgroundColor(item.done ? this.textColor() : Color.Transparent)
                .border({ width: 1, color: this.paperBorderColor() })
                .borderRadius(7)
                .onClick((): void => this.toggleTodo(item.id))

              TextInput({ text: item.text, placeholder: '待办事项' })
                .layoutWeight(1)
                .height(34)
                .fontSize(14)
                .fontColor(item.done ? this.mutedColor() : this.textColor())
                .placeholderColor(this.mutedColor())
                .backgroundColor(Color.Transparent)
                .padding(0)
                .onChange((value: string): void => this.updateTodoText(item.id, value))
                .onSubmit((): void => this.insertTodoAfter(item.id))

              Text('≡')
                .width(22)
                .fontSize(15)
                .fontColor(this.mutedColor())
                .textAlign(TextAlign.Center)

              Button('×')
                .width(24)
                .height(28)
                .fontSize(12)
                .fontColor(this.mutedColor())
                .backgroundColor(Color.Transparent)
                .onClick((): void => this.deleteTodo(item.id))
            }
            .width('100%')
            .height(40)
            .padding({ left: 8, right: 4 })
          }
          .editable(true)
        }, (item: PaperItem): string => item.id)
          .onMove((from: number, to: number): void => this.moveTodo(from, to))
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Row({ space: 6 }) {
        TextInput({ text: this.draft, placeholder: '添加待办；可直接粘贴多行' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(this.textColor())
          .placeholderColor(this.mutedColor())
          .backgroundColor(this.inputColor())
          .border({ width: 1, color: this.paperBorderColor() })
          .borderRadius(8)
          .onChange((value: string): void => {
            this.draft = value;
          })
          .onSubmit((): void => this.addDraftTodos())
        Button('+')
          .width(38)
          .height(38)
          .fontSize(20)
          .fontColor(this.paperColor())
          .backgroundColor(this.textColor())
          .borderRadius(8)
          .onClick((): void => this.addDraftTodos())
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 8 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private MarkdownToolbar() {
    Row({ space: 4 }) {
      Button('B').onClick((): void => this.appendMarkdown('**文本**'))
      Button('I').onClick((): void => this.appendMarkdown('*文本*'))
      Button('S').onClick((): void => this.appendMarkdown('~~文本~~'))
      Button('H').onClick((): void => this.appendMarkdown('## 标题'))
      Button('>').onClick((): void => this.appendMarkdown('> 引用'))
      Button('•').onClick((): void => this.appendMarkdown('- 列表'))
      Button('{}').onClick((): void => this.appendMarkdown('```\ncode\n```'))
      Button('↗').onClick((): void => this.appendMarkdown('[链接](https://)'))
    }
    .width('100%')
    .height(34)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private NoteBody() {
    Column() {
      if (!this.isNoteBrowsing) {
        this.MarkdownToolbar()
        TextArea({ text: this.content, placeholder: '写点什么…' })
          .layoutWeight(1)
          .width('100%')
          .fontSize(14)
          .fontColor(this.textColor())
          .placeholderColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .padding(12)
          .onChange((value: string): void => this.updateNote(value))
      } else if (this.markdownRenderMode === MARKDOWN_OFF) {
        Scroll() {
          Text(this.content.length > 0 ? this.content : '点击“编”开始记录')
            .width('100%')
            .fontSize(14)
            .fontColor(this.content.length > 0 ? this.textColor() : this.mutedColor())
            .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.toggleNoteBrowse())
      } else {
        Scroll() {
          Column({ space: 3 }) {
            ForEach(this.markdownLines, (line: MarkdownLine) => {
              if (line.kind === MD_KIND_RULE) {
                Divider()
                  .color(this.paperBorderColor())
                  .margin({ top: 6, bottom: 6 })
              } else if (line.kind === MD_KIND_HEADING) {
                Text(line.text)
                  .width('100%')
                  .fontSize(this.headingSize(line.level))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textColor())
                  .margin({ top: 4, bottom: 2 })
              } else if (line.kind === MD_KIND_QUOTE) {
                Text('│ ' + line.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.mutedColor())
                  .padding({ left: 6, top: 4, bottom: 4 })
              } else if (line.kind === MD_KIND_CODE) {
                Text(line.text)
                  .width('100%')
                  .fontSize(13)
                  .fontColor(this.textColor())
                  .backgroundColor(this.inputColor())
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              } else if (line.kind === MD_KIND_BULLET || line.kind === MD_KIND_ORDERED) {
                Text(line.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.textColor())
                  .padding({ left: 10 })
              } else {
                Text(line.text.length > 0 ? line.text : ' ')
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.textColor())
              }
            }, (line: MarkdownLine): string => line.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.toggleNoteBrowse())
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ResizeHandle() {
    Row() {
      Blank()
      Text('◢')
        .width(28)
        .height(24)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginResize())
            .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
            .onActionEnd((): void => this.endResize())
        )
    }
    .width('100%')
    .height(24)
  }

  @Builder
  private CapsuleBody() {
    Row({ space: 4 }) {
      Text(this.typeLabel())
        .fontSize(13)
        .fontColor(this.textColor())
      Text(this.titleOrFallback())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(12)
        .fontColor(this.textColor())
      Text('›')
        .fontSize(16)
        .fontColor(this.mutedColor())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 8 })
    .backgroundColor(this.paperColor())
    .border({ width: 1, color: this.paperBorderColor() })
    .borderRadius(22)
    .onHover((isHover: boolean): void => this.snapCapsule(isHover))
    .onClick((): void => this.setCollapsed(false))
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((): void => this.beginMove())
        .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
        .onActionEnd((): void => this.endMove())
    )
  }

  build() {
    if (this.isCollapsed) {
      this.CapsuleBody()
    } else {
      Column() {
        this.HeaderBar()
        Divider().color(this.paperBorderColor()).opacity(0.45)
        if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
          this.NoteBody()
        } else {
          this.TodoBody()
        }
        this.ResizeHandle()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.paperColor())
      .border({ width: 1, color: this.paperBorderColor() })
      .borderRadius(14)
    }
  }
}
