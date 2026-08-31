interface TodoItem {
  id: number;
  text: string;
  done: boolean;
}

@Entry
@Component
struct Index {
  @State todos: TodoItem[] = [
    { id: 1, text: '完成鸿蒙基础纸片', done: true },
    { id: 2, text: '验证多窗口能力', done: false },
    { id: 3, text: '验证边缘胶囊', done: false }
  ];
  @State draft: string = '';

  private toggleTodo(id: number): void {
    this.todos = this.todos.map((item: TodoItem): TodoItem => {
      if (item.id === id) {
        return {
          id: item.id,
          text: item.text,
          done: !item.done
        };
      }
      return item;
    });
  }

  private addTodo(): void {
    const text: string = this.draft.trim();
    if (text.length === 0) {
      return;
    }

    let nextId: number = 1;
    this.todos.forEach((item: TodoItem): void => {
      if (item.id >= nextId) {
        nextId = item.id + 1;
      }
    });

    this.todos = this.todos.concat([
      {
        id: nextId,
        text: text,
        done: false
      }
    ]);
    this.draft = '';
  }

  build() {
    Column() {
      Column() {
        Row() {
          Column() {
            Text('PaperTodo')
              .fontSize(13)
              .fontColor('#746D5D')
            Text('今天')
              .fontSize(28)
              .fontWeight(FontWeight.Medium)
              .fontColor('#28251F')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Text(`${this.todos.filter((item: TodoItem): boolean => item.done).length}/${this.todos.length}`)
            .fontSize(13)
            .fontColor('#746D5D')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column() {
          ForEach(this.todos, (item: TodoItem) => {
            Row() {
              Button(item.done ? '✓' : '')
                .width(28)
                .height(28)
                .fontSize(15)
                .fontColor(item.done ? '#FFFFFF' : '#5B5548')
                .backgroundColor(item.done ? '#5B5548' : '#FFFDF4')
                .border({ width: 1, color: '#BEB38E' })
                .borderRadius(8)
                .onClick((): void => {
                  this.toggleTodo(item.id);
                })

              Text(item.text)
                .fontSize(16)
                .fontColor(item.done ? '#9B9482' : '#28251F')
                .opacity(item.done ? 0.65 : 1)
                .margin({ left: 12 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
          }, (item: TodoItem): string => item.id.toString())
        }
        .width('100%')
        .margin({ top: 20 })

        Row() {
          TextInput({
            placeholder: '添加待办',
            text: this.draft
          })
            .height(38)
            .layoutWeight(1)
            .fontSize(15)
            .backgroundColor('#FFFDF4')
            .border({ width: 1, color: '#D8CDA5' })
            .borderRadius(9)
            .onChange((value: string): void => {
              this.draft = value;
            })

          Button('+')
            .width(38)
            .height(38)
            .fontSize(22)
            .fontColor('#FFFFFF')
            .backgroundColor('#3D3A32')
            .borderRadius(9)
            .margin({ left: 8 })
            .onClick((): void => {
              this.addTodo();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width(380)
      .padding(24)
      .backgroundColor('#FFF4C7')
      .border({ width: 1, color: '#E2D59E' })
      .borderRadius(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#ECECEC')
  }
}
