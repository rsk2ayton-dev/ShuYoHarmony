import {
  ShuYoLoginPageParam,
  ShuYoProgressCourse,
  ShuYoProgressNode
} from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState } from '../../components/ShuYoCommonViews';

@ComponentV2
export struct AcademicProgressView {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local statusFilter: string = 'all'; // 'all' | '1' | '4' | '3' | '2'
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    if (!this.store.isDemoMode &&
      this.store.isLoggedIn &&
      !this.store.progressSummary.isLoaded &&
      !this.store.isSyncingProgress) {
      this.store.syncAcademicProgress();
    }
  }

  private async handleRefresh(): Promise<void> {
    const msg = await this.store.syncAcademicProgress();
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private openLogin(): void {
    const param: ShuYoLoginPageParam = { sourceLabel: 'progress' };
    this.navStack.pushDestination({ name: 'NativeLoginPage', param: param });
  }

  private getFilterBg(code: string): string {
    return this.statusFilter === code ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getFilterTextColor(code: string): string {
    return this.statusFilter === code ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getFilteredCourses(node: ShuYoProgressNode): ShuYoProgressCourse[] {
    if (this.statusFilter === 'all') {
      return node.courses;
    }
    const out: ShuYoProgressCourse[] = [];
    for (let i = 0; i < node.courses.length; i++) {
      if (node.courses[i].status === this.statusFilter) {
        out.push(node.courses[i]);
      }
    }
    return out;
  }

  private getVisibleNodes(): ShuYoProgressNode[] {
    const all = this.store.progressSummary.nodes;
    if (this.statusFilter === 'all') {
      return all;
    }
    const out: ShuYoProgressNode[] = [];
    for (let i = 0; i < all.length; i++) {
      if (this.getFilteredCourses(all[i]).length > 0) {
        out.push(all[i]);
      }
    }
    return out;
  }

  private getStatusColor(status: string): string {
    if (status === '4') {
      return this.store.colors.success;
    }
    if (status === '1') {
      return this.store.colors.accent;
    }
    if (status === '2') {
      return this.store.colors.danger;
    }
    return this.store.colors.textMuted;
  }

  private getHeaderSubtitle(): string {
    const r = this.store.progressSummary.ranking;
    if (r.collegeName.length > 0 && r.majorName.length > 0) {
      return `${r.collegeName} · ${r.majorName}`;
    }
    if (r.majorName.length > 0) {
      return r.majorName;
    }
    if (this.store.progressSummary.isLoaded && this.store.progressUpdatedAt.length > 0) {
      return `已同步 · ${this.store.progressUpdatedAt}`;
    }
    return '培养方案修读进度与平均绩点';
  }

  private getMajorRankText(): string {
    const r = this.store.progressSummary.ranking;
    if (r.majorRank > 0 && r.majorCount > 0) {
      return `${r.majorRank} / ${r.majorCount}`;
    }
    if (r.majorRank > 0) {
      return `第 ${r.majorRank} 名`;
    }
    return '暂无排名';
  }

  private getCollegeRankText(): string {
    const r = this.store.progressSummary.ranking;
    if (r.collegeRank > 0 && r.collegeCount > 0) {
      return `学院 ${r.collegeRank} / ${r.collegeCount}`;
    }
    if (r.collegeRank > 0) {
      return `学院第 ${r.collegeRank} 名`;
    }
    return r.academicYear.length > 0 ? `${r.academicYear} ${r.term}` : '';
  }

  private formatCredits(val: number): string {
    return Number.isInteger(val) ? String(val) : val.toFixed(1);
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // Title Bar
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('学业修读')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)
            Text(this.getHeaderSubtitle())
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (!this.store.isDemoMode) {
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
          }
        }
        .width('100%')

        if (!this.store.isDemoMode && !this.store.progressSummary.isLoaded) {
          if (this.store.isSyncingProgress) {
            Column({ space: 12 }) {
              LoadingProgress().width(36).height(36).color(this.store.colors.accent)
              Text('正在从本科生教务系统同步学业进度...')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
            }
            .width('100%')
            .padding({ top: 64, bottom: 64 })
            .justifyContent(FlexAlign.Center)
          } else {
            Column({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(42)
                .fontColor([this.store.colors.accent])
              Text(this.store.isLoggedIn ? '尚未同步学业修读数据' : '请先登录校园账号')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Text(this.store.progressError.length > 0
                ? this.store.progressError
                : (this.store.isLoggedIn
                  ? '点击下方按钮从教务系统获取 GPA、排名及培养方案进度'
                  : '使用上海大学统一身份认证登录后即可同步个人学业进度与成绩排名'))
                .fontSize(13)
                .fontColor(this.store.progressError.length > 0 ? this.store.colors.danger : this.store.colors.textSecondary)
                .textAlign(TextAlign.Center)
              Row({ space: 10 }) {
                if (this.store.isLoggedIn) {
                  Button('立即同步')
                    .layoutWeight(1)
                    .height(42)
                    .fontSize(14)
                    .fontColor(this.store.colors.onAccent)
                    .backgroundColor(this.store.colors.accent)
                    .borderRadius(12)
                    .onClick(() => {
                      this.handleRefresh();
                    })
                }
                Button(this.store.isLoggedIn ? '重新登录' : '前往统一认证登录')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.isLoggedIn ? this.store.colors.textPrimary : this.store.colors.onAccent)
                  .backgroundColor(this.store.isLoggedIn ? this.store.colors.surfaceAlt : this.store.colors.accent)
                  .border({ width: this.store.isLoggedIn ? 1 : 0, color: this.store.colors.border })
                  .borderRadius(12)
                  .onClick(() => {
                    this.openLogin();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(24)
            .borderRadius(18)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Center)
          }
        } else {
          if (this.store.isSyncingProgress) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(this.store.colors.accent)
              Text('正在更新最新学业修读数据...')
                .fontSize(12)
                .fontColor(this.store.colors.accent)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor(this.store.colors.accentSoft)
          } else if (this.store.progressError.length > 0) {
            Row({ space: 8 }) {
              Text(this.store.progressError)
                .fontSize(12)
                .fontColor(this.store.colors.danger)
                .layoutWeight(1)
              if (this.store.progressAuthRequired) {
                Button('重登')
                  .height(26)
                  .fontSize(11)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(13)
                  .onClick(() => {
                    this.openLogin();
                  })
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor(this.store.colors.surfaceAlt)
          }

          // GPA & Ranking Hero Card
          Column({ space: 14 }) {
            Row() {
              Column({ space: 4 }) {
                Text('平均学分绩点 (GPA)')
                  .fontSize(12)
                  .fontColor(this.store.colors.textTertiary)
                Text(this.store.progressSummary.gpa)
                  .fontSize(32)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.accent)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 4 }) {
                Text('专业排名')
                  .fontSize(12)
                  .fontColor(this.store.colors.textTertiary)
                Text(this.getMajorRankText())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)
                if (this.getCollegeRankText().length > 0) {
                  Text(this.getCollegeRankText())
                    .fontSize(11)
                    .fontColor(this.store.colors.textMuted)
                }
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')

            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(String(this.store.progressSummary.passedCourses))
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.success)
                Text('已通过')
                  .fontSize(11)
                  .fontColor(this.store.colors.textTertiary)
              }
              .layoutWeight(1)
              .padding(10)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surfaceAlt)

              Column({ space: 2 }) {
                Text(String(this.store.progressSummary.ongoingCourses))
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.accent)
                Text('在修中')
                  .fontSize(11)
                  .fontColor(this.store.colors.textTertiary)
              }
              .layoutWeight(1)
              .padding(10)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surfaceAlt)

              Column({ space: 2 }) {
                Text(String(this.store.progressSummary.notTakenCourses))
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textSecondary)
                Text('待修读')
                  .fontSize(11)
                  .fontColor(this.store.colors.textTertiary)
              }
              .layoutWeight(1)
              .padding(10)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surfaceAlt)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })

          // Filter row
          Scroll() {
            Row({ space: 8 }) {
              Button('全部')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterTextColor('all'))
                .backgroundColor(this.getFilterBg('all'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.statusFilter = 'all';
                })
              Button('在修')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterTextColor('1'))
                .backgroundColor(this.getFilterBg('1'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.statusFilter = '1';
                })
              Button('已修')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterTextColor('4'))
                .backgroundColor(this.getFilterBg('4'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.statusFilter = '4';
                })
              Button('未修')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterTextColor('3'))
                .backgroundColor(this.getFilterBg('3'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.statusFilter = '3';
                })
              Button('未通过')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterTextColor('2'))
                .backgroundColor(this.getFilterBg('2'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.statusFilter = '2';
                })
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          if (this.getVisibleNodes().length === 0) {
            ShuYoEmptyState({
              emptyTitle: '当前筛选下暂无课程记录',
              emptyHint: '可切换上方修读状态标签查看其他课程',
              actionText: '查看全部',
              onActionTap: () => {
                this.statusFilter = 'all';
              }
            })
          } else {
            ForEach(this.getVisibleNodes(), (node: ShuYoProgressNode, nIdx: number) => {
              Column({ space: 10 }) {
                Row() {
                  Text(node.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                    .layoutWeight(1)
                  Text(`${this.formatCredits(node.earnedCredits)} / ${this.formatCredits(node.requiredCredits)} 学分`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(node.passed ? this.store.colors.success : this.store.colors.accent)
                }
                .width('100%')

                Progress({
                  value: Math.min(node.earnedCredits, node.requiredCredits > 0 ? node.requiredCredits : 100),
                  total: node.requiredCredits > 0 ? node.requiredCredits : 100,
                  type: ProgressType.Linear
                })
                  .width('100%')
                  .color(node.passed ? this.store.colors.success : this.store.colors.accent)
                  .backgroundColor(this.store.colors.surfaceMuted)
                  .style({ strokeWidth: 6 })

                Column({ space: 8 }) {
                  ForEach(this.getFilteredCourses(node), (course: ShuYoProgressCourse, cIdx: number) => {
                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Text(course.name)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.store.colors.textPrimary)
                        Text(`${course.code} · ${course.credits}学分${course.nature.length > 0 ? ' · ' + course.nature : ''}`)
                          .fontSize(11)
                          .fontColor(this.store.colors.textTertiary)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Column({ space: 2 }) {
                        Text(course.grade.length > 0
                          ? (course.gradePoint.length > 0 ? `${course.grade} (绩点 ${course.gradePoint})` : course.grade)
                          : course.statusLabel)
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.getStatusColor(course.status))
                        if (course.academicYear.length > 0) {
                          Text(`${course.academicYear} ${course.term}`)
                            .fontSize(10)
                            .fontColor(this.store.colors.textMuted)
                        }
                      }
                      .alignItems(HorizontalAlign.End)
                    }
                    .width('100%')
                    .padding(10)
                    .borderRadius(10)
                    .backgroundColor(this.store.colors.surfaceAlt)
                  }, (course: ShuYoProgressCourse, cIdx: number): string => `${node.id}-${course.id}-${cIdx}`)
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
            }, (node: ShuYoProgressNode, nIdx: number): string => `${node.id}-${nIdx}-${this.store.dataRevision}`)
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.colors.background)
    .scrollBar(BarState.Off)
  }
}
