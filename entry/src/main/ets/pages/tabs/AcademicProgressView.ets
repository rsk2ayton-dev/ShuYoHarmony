import { ShuYoProgressCourse, ShuYoProgressNode } from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';

@ComponentV2
export struct AcademicProgressView {
  @Local statusFilter: string = 'all'; // 'all' | '1' | '4' | '3'
  private store: ShuYoAppStore = ShuYoAppStore.instance();

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

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // Title
        Row() {
          Column({ space: 2 }) {
            Text('学业修读')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)
            Text(`${this.store.progressSummary.ranking.collegeName} · ${this.store.progressSummary.ranking.majorName}`)
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

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
              Text(`${this.store.progressSummary.ranking.majorRank} / ${this.store.progressSummary.ranking.majorCount}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Text(`学院 ${this.store.progressSummary.ranking.collegeRank} / ${this.store.progressSummary.ranking.collegeCount}`)
                .fontSize(11)
                .fontColor(this.store.colors.textMuted)
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
        }
        .width('100%')

        // Nodes
        ForEach(this.store.progressSummary.nodes, (node: ShuYoProgressNode, nIdx: number) => {
          Column({ space: 10 }) {
            Row() {
              Text(node.name)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Blank()
              Text(`${node.earnedCredits} / ${node.requiredCredits} 学分`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.colors.accent)
            }
            .width('100%')

            Progress({
              value: node.earnedCredits,
              total: node.requiredCredits > 0 ? node.requiredCredits : 100,
              type: ProgressType.Linear
            })
              .width('100%')
              .color(this.store.colors.accent)
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
                    Text(`${course.code} · ${course.credits}学分 · ${course.nature}`)
                      .fontSize(11)
                      .fontColor(this.store.colors.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text(course.grade.length > 0 ? `${course.grade}分 (绩点 ${course.gradePoint})` : course.statusLabel)
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
        }, (node: ShuYoProgressNode, nIdx: number): string => `${node.id}-${nIdx}`)
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
