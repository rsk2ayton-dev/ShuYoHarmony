import {
  ShuYoRateDetailParam,
  ShuYoRateOptionStat,
  ShuYoRatePublishParam,
  ShuYoRateQuestionStat,
  ShuYoRateReviewRecord,
  ShuYoRateUnitItem
} from '../../models/ShuYoModels';
import { CourseReviewService } from '../../services/CourseReviewService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function RateDetailPageBuilder(): void {
  RateDetailPage()
}

@ComponentV2
export struct RateDetailPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local unitId: string = '';
  @Local unit: ShuYoRateUnitItem | undefined = undefined;
  @Local stats: ShuYoRateQuestionStat[] = [];
  @Local reviews: ShuYoRateReviewRecord[] = [];
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private reloadData(): void {
    if (this.unitId.length === 0) {
      return;
    }
    this.unit = CourseReviewService.getUnitById(this.unitId);
    this.stats = CourseReviewService.computeQuestionStats(this.unitId);
    this.reviews = CourseReviewService.getReviewsForUnit(this.unitId);
  }

  private openPublish(): void {
    if (this.unit === undefined) {
      return;
    }
    const param: ShuYoRatePublishParam = {
      unitId: this.unit.id,
      courseName: this.unit.courseName,
      teacherName: this.unit.teacherName
    };
    this.navStack.pushDestination({ name: 'RatePublishPage', param: param });
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: this.unit !== undefined ? this.unit.courseName : '课程评价详情',
          subtitleText: this.unit !== undefined ? `${this.unit.teacherName} · ${this.unit.courseId}` : '',
          showBack: true,
          rightLabel: '写评价',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.openPublish();
          }
        })

        Scroll() {
          Column({ space: 14 }) {
            if (this.unit !== undefined) {
              // Hero score card
              Row({ space: 14 }) {
                Column({ space: 4 }) {
                  Text(this.unit.average.toFixed(1))
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.accent)
                  Text(`满分 10.0 · ${this.unit.reviewCount} 人评课`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Column({ space: 4 }) {
                  Text(this.unit.college)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                  Text(`${this.unit.credits} 学分`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding(18)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })

              // Dimension stats
              ForEach(this.stats, (stat: ShuYoRateQuestionStat, sIdx: number) => {
                Column({ space: 10 }) {
                  Row() {
                    Text(stat.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Blank()
                    Text(`${stat.answered} 份回答`)
                      .fontSize(12)
                      .fontColor(this.store.colors.textMuted)
                  }
                  .width('100%')

                  ForEach(stat.options, (opt: ShuYoRateOptionStat, oIdx: number) => {
                    Column({ space: 4 }) {
                      Row() {
                        Text(opt.label)
                          .fontSize(13)
                          .fontWeight(opt.isTop ? FontWeight.Bold : FontWeight.Normal)
                          .fontColor(this.store.colors.textPrimary)
                        Blank()
                        Text(`${opt.percent}% (${opt.count})`)
                          .fontSize(12)
                          .fontColor(opt.isTop ? this.store.colors.accent : this.store.colors.textTertiary)
                      }
                      .width('100%')

                      Progress({
                        value: opt.percent,
                        total: 100,
                        type: ProgressType.Linear
                      })
                        .width('100%')
                        .color(opt.isTop ? this.store.colors.accent : this.store.colors.borderStrong)
                        .backgroundColor(this.store.colors.surfaceAlt)
                        .style({ strokeWidth: 6 })
                    }
                    .width('100%')
                  }, (opt: ShuYoRateOptionStat, oIdx: number): string => `${stat.key}-${opt.key}`)
                }
                .width('100%')
                .padding(16)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })
              }, (stat: ShuYoRateQuestionStat, sIdx: number): string => `${stat.key}-${sIdx}`)

              // Reviews list
              Column({ space: 10 }) {
                Text('同学评价')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)

                ForEach(this.reviews, (rev: ShuYoRateReviewRecord, rIdx: number) => {
                  Column({ space: 6 }) {
                    Row() {
                      Text(`评分 ${rev.overall} / 5 星`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.warning)
                      Blank()
                      Text(rev.updatedAt)
                        .fontSize(11)
                        .fontColor(this.store.colors.textMuted)
                    }
                    .width('100%')

                    Text(rev.comment)
                      .fontSize(14)
                      .lineHeight(20)
                      .fontColor(this.store.colors.textPrimary)
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(12)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                  .alignItems(HorizontalAlign.Start)
                }, (rev: ShuYoRateReviewRecord, rIdx: number): string => `${rev.id}-${rIdx}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
      const param = ctx.pathInfo.param as ShuYoRateDetailParam | undefined;
      if (param !== undefined) {
        this.unitId = param.unitId;
        this.reloadData();
      }
    })
    .onShown(() => {
      this.reloadData();
    })
  }
}
