import { ShuYoScheduleCollection } from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function ScheduleCollectionPageBuilder(): void {
  ScheduleCollectionPage()
}

@ComponentV2
export struct ScheduleCollectionPage {
  @Local navStack: NavPathStack = new NavPathStack();
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private isActive(colId: string): boolean {
    return this.store.activeCollectionId === colId;
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        ShuYoTopBar({
          headerTitle: '课表管理',
          subtitleText: '切换不同学期或导入的他人课表',
          showBack: true,
          rightLabel: '导入',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.navStack.pushDestination({ name: 'ScheduleSharePage' });
          }
        })

        List({ space: 10 }) {
          ForEach(this.store.scheduleCollections, (col: ShuYoScheduleCollection, idx: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(col.title)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    if (this.isActive(col.id)) {
                      Text('当前使用')
                        .fontSize(11)
                        .fontColor(this.store.colors.onAccent)
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                        .borderRadius(8)
                        .backgroundColor(this.store.colors.accent)
                    }
                  }
                  Text(`${col.schedule.term.studentName} · 共 ${col.schedule.sessions.length} 门时段课程`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.store.scheduleCollections.length > 1) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash'))
                      .fontSize(16)
                      .fontColor([this.store.colors.danger])
                  }
                  .width(34)
                  .height(34)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .onClick(() => {
                    this.store.deleteCollection(col.id);
                  })
                }
              }
              .width('100%')
              .padding(16)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({
                width: this.isActive(col.id) ? 1.5 : 1,
                color: this.isActive(col.id) ? this.store.colors.accent : this.store.colors.border
              })
              .onClick(() => {
                this.store.switchCollection(col.id);
                this.getUIContext().getPromptAction().showToast({ message: `已切换至 ${col.title}` });
                this.navStack.pop();
              })
            }
          }, (col: ShuYoScheduleCollection, idx: number): string => `${col.id}-${idx}-${this.store.activeCollectionId}-${this.store.dataRevision}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
