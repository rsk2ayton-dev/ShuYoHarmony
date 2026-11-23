import {
  ShuYoRateDetailParam,
  ShuYoRatePublishParam,
  ShuYoRateRankingCategory,
  ShuYoRateUnitItem
} from '../../models/ShuYoModels';
import { CourseReviewService } from '../../services/CourseReviewService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState } from '../../components/ShuYoCommonViews';

@ComponentV2
export struct RateHomeView {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local searchKeyword: string = '';
  @Local selectedTab: number = 0; // 0: 近期热评, 1: 排行榜单
  @Local selectedRankIndex: number = 0;
  @Local searchResults: ShuYoRateUnitItem[] = [];
  @Local isSearching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local searchError: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    if (!this.store.isDemoMode &&
      this.store.rateHome.recent.length === 0 &&
      !this.store.isSyncingRate) {
      this.store.syncRateHome();
    }
  }

  private async handleRefresh(): Promise<void> {
    const msg = await this.store.syncRateHome();
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private async runRemoteSearch(): Promise<void> {
    const kw = this.searchKeyword.trim();
    if (kw.length === 0) {
      this.clearSearch();
      return;
    }
    if (this.store.isDemoMode) {
      return;
    }
    this.isSearching = true;
    this.hasSearched = true;
    this.searchError = '';
    try {
      this.searchResults = await CourseReviewService.searchLive(kw);
    } catch (err) {
      const e = err as Error;
      this.searchError = e.message.length > 0 ? e.message : '搜索失败，请稍后重试';
      this.searchResults = [];
    } finally {
      this.isSearching = false;
    }
  }

  private clearSearch(): void {
    this.searchKeyword = '';
    this.hasSearched = false;
    this.searchResults = [];
    this.searchError = '';
  }

  private getRankCategories(): ShuYoRateRankingCategory[] {
    return this.store.rateHome.rankings;
  }

  private getDisplayedUnits(): ShuYoRateUnitItem[] {
    if (!this.store.isDemoMode && this.hasSearched && this.searchKeyword.trim().length > 0) {
      return this.searchResults;
    }
    let source = this.store.rateHome.recent;
    if (this.selectedTab === 1) {
      const cats = this.store.rateHome.rankings;
      if (cats.length > 0) {
        const idx = this.selectedRankIndex >= 0 && this.selectedRankIndex < cats.length
          ? this.selectedRankIndex
          : 0;
        source = cats[idx].items;
      } else {
        source = this.store.rateHome.rankingItems;
      }
    }
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

  private getDefaultWriteTarget(): ShuYoRateUnitItem | undefined {
    const list = this.getDisplayedUnits();
    if (list.length > 0) {
      return list[0];
    }
    if (this.store.rateHome.recent.length > 0) {
      return this.store.rateHome.recent[0];
    }
    return undefined;
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

  private getRankChipBg(idx: number): string {
    return this.selectedRankIndex === idx ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getRankChipText(idx: number): string {
    return this.selectedRankIndex === idx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private formatUnitScore(unit: ShuYoRateUnitItem): string {
    if (unit.reviewCount <= 0 || unit.average <= 0) {
      return '暂无';
    }
    return unit.average.toFixed(1);
  }

  build() {
    Column({ space: 10 }) {
      // Header
      Row({ space: 8 }) {
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

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([this.store.colors.textPrimary])
        }
        .width(34)
        .height(34)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })
        .onClick(() => {
          this.handleRefresh();
        })

        if (this.getDefaultWriteTarget() !== undefined) {
          Button('写评课')
            .height(34)
            .fontSize(13)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(17)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              if (this.getDefaultWriteTarget() !== undefined) {
                this.openPublish(this.getDefaultWriteTarget()!);
              }
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
            if (val.trim().length === 0 && this.hasSearched) {
              this.hasSearched = false;
              this.searchResults = [];
              this.searchError = '';
            }
          })
          .onSubmit(() => {
            this.runRemoteSearch();
          })
        if (this.searchKeyword.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([this.store.colors.textMuted])
            .onClick(() => {
              this.clearSearch();
            })
        }
        if (!this.store.isDemoMode && this.searchKeyword.trim().length > 0) {
          Button('搜索')
            .height(28)
            .fontSize(12)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.runRemoteSearch();
            })
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 10 })
      .margin({ left: 16, right: 16 })
      .borderRadius(12)
      .backgroundColor(this.store.colors.surface)
      .border({ width: 1, color: this.store.colors.border })

      // Mode switch chips
      if (!this.hasSearched) {
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
          Button('排行榜单')
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

        if (this.selectedTab === 1 && this.getRankCategories().length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.getRankCategories(), (cat: ShuYoRateRankingCategory, idx: number) => {
                Button(cat.title)
                  .height(28)
                  .fontSize(12)
                  .fontColor(this.getRankChipText(idx))
                  .backgroundColor(this.getRankChipBg(idx))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.selectedRankIndex = idx;
                  })
              }, (cat: ShuYoRateRankingCategory, idx: number): string => `rcat-${cat.key}-${idx}`)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(32)
        }
      }

      if ((this.store.isSyncingRate && this.getDisplayedUnits().length === 0) || this.isSearching) {
        Column({ space: 10 }) {
          LoadingProgress().width(34).height(34).color(this.store.colors.accent)
          Text(this.isSearching ? '正在检索全校课程评价...' : '正在加载真实课程评价...')
            .fontSize(13)
            .fontColor(this.store.colors.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.store.isDemoMode &&
        (this.searchError.length > 0 || (this.store.rateError.length > 0 && this.getDisplayedUnits().length === 0))) {
        ShuYoEmptyState({
          emptyTitle: this.hasSearched ? '课程搜索失败' : '课程评价加载失败',
          emptyHint: this.hasSearched ? this.searchError : this.store.rateError,
          actionText: '重试',
          onActionTap: () => {
            if (this.hasSearched) {
              this.runRemoteSearch();
            } else {
              this.handleRefresh();
            }
          }
        })
      } else if (this.getDisplayedUnits().length === 0) {
        ShuYoEmptyState({
          emptyTitle: '未找到匹配的课程评价',
          emptyHint: this.store.isDemoMode
            ? '可以尝试更换课程名称或教师姓名关键词'
            : '可输入完整关键词点击“搜索”检索全校课程库',
          actionText: this.hasSearched ? '返回全部列表' : '刷新数据',
          onActionTap: () => {
            if (this.hasSearched) {
              this.clearSearch();
            } else {
              this.handleRefresh();
            }
          }
        })
      } else {
        List({ space: 10 }) {
          ForEach(this.getDisplayedUnits(), (unit: ShuYoRateUnitItem, idx: number) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(unit.courseName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Text(`${unit.teacherName} · ${unit.courseId}${unit.college.length > 0 ? ' · ' + unit.college : ''}`)
                      .fontSize(12)
                      .fontColor(this.store.colors.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.star_fill'))
                        .fontSize(15)
                        .fontColor([unit.reviewCount > 0 && unit.average > 0
                          ? this.store.colors.warning
                          : this.store.colors.textMuted])
                      Text(this.formatUnitScore(unit))
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

                Row({ space: 6 }) {
                  if (unit.tags.length > 0) {
                    ForEach(unit.tags, (tag: string, tIdx: number) => {
                      Text(tag)
                        .fontSize(11)
                        .fontColor(this.store.colors.accent)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(6)
                        .backgroundColor(this.store.colors.accentSoft)
                    }, (tag: string, tIdx: number): string => `${unit.id}-tag-${tIdx}`)
                  } else if (unit.credits.length > 0) {
                    Text(`${unit.credits} 学分`)
                      .fontSize(11)
                      .fontColor(this.store.colors.accent)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(6)
                      .backgroundColor(this.store.colors.accentSoft)
                  }
                  Blank()
                  Text(unit.lastReviewedText)
                    .fontSize(11)
                    .fontColor(this.store.colors.textMuted)
                }
                .width('100%')
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
          }, (unit: ShuYoRateUnitItem, idx: number): string => `${unit.id}-${unit.reviewCount}-${idx}-${this.store.dataRevision}`)
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
