import { ShuYoContributor } from '../../models/ShuYoModels';
import { ContributorsService } from '../../services/ContributorsService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function ContributorsPageBuilder(): void {
  ContributorsPage()
}

@ComponentV2
export struct ContributorsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local contributors: ShuYoContributor[] = [];
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    this.contributors = ContributorsService.loadContributors();
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '项目贡献者',
          subtitleText: 'shuosc/ShuYo 开源贡献鸣谢',
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
        })

        List({ space: 10 }) {
          ForEach(this.contributors, (c: ShuYoContributor, idx: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column() {
                  Text(c.displayName.substring(0, 1).toUpperCase())
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.onAccent)
                }
                .width(42)
                .height(42)
                .borderRadius(21)
                .backgroundColor(this.store.colors.accent)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column({ space: 3 }) {
                  Text(c.displayName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  Text(`@${c.login} · ${c.commits} commits (+${c.additions} / -${c.deletions})`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
            }
          }, (c: ShuYoContributor, idx: number): string => `${c.login}-${idx}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
        .scrollBar(BarState.Off)
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
