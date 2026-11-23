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
import { ShuYoEmptyState, ShuYoTopBar } from '../../components/ShuYoCommonViews';

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
  @Local isLoading: boolean = false;
  @Local errorMessage: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private async reloadData(): Promise<void> {
    if (this.unitId.length === 0) {
      return;
    }
    if (this.store.isDemoMode) {
      this.unit = CourseReviewService.getUnitById(this.unitId);
      this.stats = CourseReviewService.computeQuestionStats(this.unitId);
      this.reviews = CourseReviewService.getReviewsForUnit(this.unitId);
      return;
    }
    const cached = CourseReviewService.getUnitById(this.unitId);
    if (cached !== undefined && this.unit === undefined) {
      this.unit = cached;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const detail = await CourseReviewService.fetchLiveUnitDetail(this.unitId);
      this.unit = detail.unit;
      this.stats = detail.stats;
      this.reviews = [];
    } catch (err) {
      const e = err as Error;
      this.errorMessage = e.message.length > 0 ? e.message : '加载课程评价详情失败';
    } finally {
      this.isLoading = false;
    }
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

  private formatAverage(): string {
    if (this.unit === undefined || this.unit.reviewCount <= 0 || this.unit.average <= 0) {
      return '暂无';
    }
    return this.unit.average.toFixed(1);
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

        if (this.isLoading && this.stats.length === 0 && this.unit === undefined) {
          Column({ space: 10 }) {
            LoadingProgress().width(34).height(34).color(this.store.colors.accent)
            Text('正在加载课程评价统计...')
              .fontSize(13)
              .fontColor(this.store.colors.textTertiary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.unit === undefined && this.errorMessage.length > 0) {
          ShuYoEmptyState({
            emptyTitle: '详情加载失败',
            emptyHint: this.errorMessage,
            actionText: '重试',
            onActionTap: () => {
              this.reloadData();
            }
          })
        } else {
          Scroll() {
            Column({ space: 14 }) {
              if (this.unit !== undefined) {
                // Hero score card
                Row({ space: 14 }) {
                  Column({ space: 4 }) {
                    Text(this.formatAverage())
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
                    Text(this.unit.college.length > 0 ? this.unit.college : '上海大学')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.store.colors.textPrimary)
                    if (this.unit.credits.length > 0) {
                      Text(`${this.unit.credits} 学分`)
                        .fontSize(12)
                        .fontColor(this.store.colors.textTertiary)
                    }
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding(18)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })

                if (this.isLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(16).height(16).color(this.store.colors.accent)
                    Text('正在更新各维度统计数据...')
                      .fontSize(12)
                      .fontColor(this.store.colors.accent)
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(10)
                  .backgroundColor(this.store.colors.accentSoft)
                } else if (this.errorMessage.length > 0) {
                  Text(this.errorMessage)
                    .fontSize(12)
                    .fontColor(this.store.colors.danger)
                    .width('100%')
                }

                // Dimension stats
                if (this.stats.length === 0 && !this.isLoading) {
                  Column({ space: 6 }) {
                    Text('暂无各维度投票统计')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.store.colors.textSecondary)
                    Text('点击右上角“写评价”提交首份课程反馈')
                      .fontSize(12)
                      .fontColor(this.store.colors.textTertiary)
                  }
                  .width('100%')
                  .padding(18)
                  .borderRadius(16)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                } else {
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
                }

                // Reviews list (Demo mode sample comments)
                if (this.reviews.length > 0) {
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
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 28 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
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
