import {
  ShuYoRateDetailParam,
  ShuYoRatePublishParam,
  ShuYoRateUnitItem
} from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState } from '../../components/ShuYoCommonViews';

@ComponentV2
export struct RateHomeView {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local searchKeyword: string = '';
  @Local selectedTab: number = 0; // 0: 近期评价, 1: 综合评分榜
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private getDisplayedUnits(): ShuYoRateUnitItem[] {
    const source = this.selectedTab === 1
      ? this.store.rateHome.rankingItems
      : this.store.rateHome.recent;
    const kw = this.searchKeyword.trim().toLowerCase();
    if (kw.length === 0) {
      return source;
    }
    const filtered: ShuYoRateUnitItem[] = [];
    for (let i = 0; i < source.length; i++) {
      const u = source[i];
      const hay = `${u.courseName} ${u.courseId} ${u.teacherName} ${u.college}`.toLowerCase();
      if (hay.includes(kw)) {
        filtered.push(u);
      }
    }
    return filtered;
  }

  private openDetail(unit: ShuYoRateUnitItem): void {
    const param: ShuYoRateDetailParam = { unitId: unit.id };
    this.navStack.pushDestination({ name: 'RateDetailPage', param: param });
  }

  private openPublish(unit: ShuYoRateUnitItem): void {
    const param: ShuYoRatePublishParam = {
      unitId: unit.id,
      courseName: unit.courseName,
      teacherName: unit.teacherName
    };
    this.navStack.pushDestination({ name: 'RatePublishPage', param: param });
  }

  private getSegmentBg(idx: number): string {
    return this.selectedTab === idx ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getSegmentTextColor(idx: number): string {
    return this.selectedTab === idx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  build() {
    Column({ space: 12 }) {
      // Header
      Row() {
        Column({ space: 2 }) {
          Text('课程评价')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)
          Text('基于选课记录与同学真实反馈')
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.store.rateHome.recent.length > 0) {
          Button('写评课')
            .height(34)
            .fontSize(13)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(17)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.openPublish(this.store.rateHome.recent[0]);
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })
      .alignItems(VerticalAlign.Center)

      // Search input
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.store.colors.textMuted])
        TextInput({ placeholder: '搜索课程名、课程号或教师姓名', text: this.searchKeyword })
          .layoutWeight(1)
          .height(38)
          .backgroundColor(Color.Transparent)
          .fontColor(this.store.colors.textPrimary)
          .placeholderColor(this.store.colors.textMuted)
          .fontSize(14)
          .onChange((val: string) => {
            this.searchKeyword = val;
          })
        if (this.searchKeyword.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([this.store.colors.textMuted])
            .onClick(() => {
              this.searchKeyword = '';
            })
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .margin({ left: 16, right: 16 })
      .borderRadius(12)
      .backgroundColor(this.store.colors.surface)
      .border({ width: 1, color: this.store.colors.border })

      // Mode switch chips
      Row({ space: 10 }) {
        Button('近期热评')
          .height(32)
          .fontSize(13)
          .fontColor(this.getSegmentTextColor(0))
          .backgroundColor(this.getSegmentBg(0))
          .borderRadius(16)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.selectedTab = 0;
          })
        Button('综合评分榜')
          .height(32)
          .fontSize(13)
          .fontColor(this.getSegmentTextColor(1))
          .backgroundColor(this.getSegmentBg(1))
          .borderRadius(16)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.selectedTab = 1;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      if (this.getDisplayedUnits().length === 0) {
        ShuYoEmptyState({
          emptyTitle: '未找到匹配的课程评价',
          emptyHint: '可以尝试更换课程名称或教师姓名关键词',
          actionText: '',
          onActionTap: () => {}
        })
      } else {
        List({ space: 10 }) {
          ForEach(this.getDisplayedUnits(), (unit: ShuYoRateUnitItem, idx: number) => {
            ListItem() {
              Column({ space: 10 }) {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(unit.courseName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Text(`${unit.teacherName} · ${unit.courseId} · ${unit.college}`)
                      .fontSize(12)
                      .fontColor(this.store.colors.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.star_fill'))
                        .fontSize(15)
                        .fontColor([this.store.colors.warning])
                      Text(unit.average.toFixed(1))
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.textPrimary)
                    }
                    Text(`${unit.reviewCount} 条评价`)
                      .fontSize(11)
                      .fontColor(this.store.colors.textMuted)
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')

                if (unit.tags.length > 0) {
                  Row({ space: 6 }) {
                    ForEach(unit.tags, (tag: string, tIdx: number) => {
                      Text(tag)
                        .fontSize(11)
                        .fontColor(this.store.colors.accent)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(6)
                        .backgroundColor(this.store.colors.accentSoft)
                    }, (tag: string, tIdx: number): string => `${unit.id}-tag-${tIdx}`)
                    Blank()
                    Text(unit.lastReviewedText)
                      .fontSize(11)
                      .fontColor(this.store.colors.textMuted)
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .onClick(() => {
                this.openDetail(unit);
              })
            }
          }, (unit: ShuYoRateUnitItem, idx: number): string => `${unit.id}-${unit.reviewCount}-${idx}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.colors.background)
  }
}
