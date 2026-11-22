import { ShuYoHomeLayoutItem } from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function HomeLayoutPageBuilder(): void {
  HomeLayoutPage()
}

@ComponentV2
export struct HomeLayoutPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local items: ShuYoHomeLayoutItem[] = [];
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    this.items = [...this.store.homeLayout];
  }

  private moveItem(idx: number, delta: number): void {
    const target = idx + delta;
    if (target < 0 || target >= this.items.length) {
      return;
    }
    const copy = [...this.items];
    const tmp = copy[idx];
    copy[idx] = copy[target];
    copy[target] = tmp;
    this.items = copy;
    this.store.updateHomeLayout(copy);
  }

  private toggleItem(idx: number, enabled: boolean): void {
    const copy = [...this.items];
    const cur = copy[idx];
    copy[idx] = {
      id: cur.id,
      title: cur.title,
      subtitle: cur.subtitle,
      enabled: enabled
    };
    this.items = copy;
    this.store.updateHomeLayout(copy);
  }

  private resetDefault(): void {
    this.store.resetHomeLayout();
    this.items = [...this.store.homeLayout];
    this.getUIContext().getPromptAction().showToast({ message: '已恢复默认首页排版' });
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        ShuYoTopBar({
          headerTitle: '首页排版',
          subtitleText: '调整模块显示顺序与开关',
          showBack: true,
          rightLabel: '恢复默认',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.resetDefault();
          }
        })

        List({ space: 10 }) {
          ForEach(this.items, (item: ShuYoHomeLayoutItem, idx: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  Text(item.subtitle)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button('上移')
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .padding({ left: 10, right: 10 })
                  .enabled(idx > 0)
                  .onClick(() => {
                    this.moveItem(idx, -1);
                  })

                Button('下移')
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .padding({ left: 10, right: 10 })
                  .enabled(idx < this.items.length - 1)
                  .onClick(() => {
                    this.moveItem(idx, 1);
                  })

                Toggle({ type: ToggleType.Switch, isOn: item.enabled })
                  .selectedColor(this.store.colors.accent)
                  .onChange((val: boolean) => {
                    this.toggleItem(idx, val);
                  })
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
            }
          }, (item: ShuYoHomeLayoutItem, idx: number): string => `${item.id}-${idx}-${item.enabled}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
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
