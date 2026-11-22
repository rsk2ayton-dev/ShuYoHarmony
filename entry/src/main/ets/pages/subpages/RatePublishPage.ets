import { ShuYoRatePublishParam } from '../../models/ShuYoModels';
import { CourseReviewService } from '../../services/CourseReviewService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

interface ShuYoScoreChoice {
  score: number;
  label: string;
}

interface ShuYoTagChoice {
  key: string;
  label: string;
}

@Builder
export function RatePublishPageBuilder(): void {
  RatePublishPage()
}

@ComponentV2
export struct RatePublishPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local unitId: string = '';
  @Local courseName: string = '';
  @Local teacherName: string = '';
  @Local overallScore: number = 5;
  @Local gradingChoice: string = 'fair';
  @Local teachingChoices: string[] = ['clear'];
  @Local commentInput: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly scoreOptions: ShuYoScoreChoice[] = [
    { score: 1, label: '1星 不太推荐' },
    { score: 2, label: '2星 有待改进' },
    { score: 3, label: '3星 中规中矩' },
    { score: 4, label: '4星 值得推荐' },
    { score: 5, label: '5星 强烈推荐' }
  ];
  private readonly gradingOptions: ShuYoTagChoice[] = [
    { key: 'strict', label: '要求严格' },
    { key: 'fair', label: '给分合理' },
    { key: 'generous', label: '给分宽松' }
  ];
  private readonly teachingOptions: ShuYoTagChoice[] = [
    { key: 'clear', label: '讲解清晰' },
    { key: 'interactive', label: '互动充分' },
    { key: 'practical', label: '注重实践' },
    { key: 'fast', label: '节奏较快' }
  ];

  private toggleTeaching(key: string): void {
    if (this.teachingChoices.includes(key)) {
      const next: string[] = [];
      for (let i = 0; i < this.teachingChoices.length; i++) {
        if (this.teachingChoices[i] !== key) {
          next.push(this.teachingChoices[i]);
        }
      }
      this.teachingChoices = next;
      return;
    }
    if (this.teachingChoices.length >= 2) {
      this.getUIContext().getPromptAction().showToast({ message: '课堂体验最多选择 2 项' });
      return;
    }
    this.teachingChoices = [...this.teachingChoices, key];
  }

  private submitReview(): void {
    if (this.unitId.length === 0) {
      return;
    }
    CourseReviewService.submitDemoReview(
      this.unitId,
      this.overallScore,
      this.gradingChoice,
      this.teachingChoices,
      this.commentInput
    );
    this.store.rateHome = CourseReviewService.buildDemoHome(this.store.scheduleData);
    this.getUIContext().getPromptAction().showToast({ message: '评价已发布' });
    this.navStack.pop();
  }

  private getChipBg(selected: boolean): string {
    return selected ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getChipText(selected: boolean): string {
    return selected ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '发表课程评价',
          subtitleText: `${this.courseName} · ${this.teacherName}`,
          showBack: true,
          rightLabel: '提交',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.submitReview();
          }
        })

        Scroll() {
          Column({ space: 14 }) {
            // Overall rating
            Column({ space: 10 }) {
              Text('总体评价 *')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Column({ space: 8 }) {
                ForEach(this.scoreOptions, (opt: ShuYoScoreChoice, idx: number) => {
                  Button(opt.label)
                    .width('100%')
                    .height(38)
                    .fontSize(13)
                    .fontColor(this.getChipText(this.overallScore === opt.score))
                    .backgroundColor(this.getChipBg(this.overallScore === opt.score))
                    .borderRadius(10)
                    .onClick(() => {
                      this.overallScore = opt.score;
                    })
                }, (opt: ShuYoScoreChoice, idx: number): string => `sc-${opt.score}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Grading tendency
            Column({ space: 10 }) {
              Text('给分倾向')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Row({ space: 8 }) {
                ForEach(this.gradingOptions, (opt: ShuYoTagChoice, idx: number) => {
                  Button(opt.label)
                    .layoutWeight(1)
                    .height(36)
                    .fontSize(12)
                    .fontColor(this.getChipText(this.gradingChoice === opt.key))
                    .backgroundColor(this.getChipBg(this.gradingChoice === opt.key))
                    .borderRadius(10)
                    .onClick(() => {
                      this.gradingChoice = opt.key;
                    })
                }, (opt: ShuYoTagChoice, idx: number): string => `grd-${opt.key}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Teaching style
            Column({ space: 10 }) {
              Text('课堂体验（最多选 2 项）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Row({ space: 8 }) {
                ForEach(this.teachingOptions, (opt: ShuYoTagChoice, idx: number) => {
                  Button(opt.label)
                    .layoutWeight(1)
                    .height(36)
                    .fontSize(11)
                    .fontColor(this.getChipText(this.teachingChoices.includes(opt.key)))
                    .backgroundColor(this.getChipBg(this.teachingChoices.includes(opt.key)))
                    .borderRadius(10)
                    .onClick(() => {
                      this.toggleTeaching(opt.key);
                    })
                }, (opt: ShuYoTagChoice, idx: number): string => `tch-${opt.key}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Comment
            Column({ space: 8 }) {
              Text('课程评价正文')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              TextArea({ placeholder: '分享授课特点、作业量、考核方式与选课建议...', text: this.commentInput })
                .height(110)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.commentInput = val;
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            Button('提交课程评价')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontColor(this.store.colors.onAccent)
              .backgroundColor(this.store.colors.accent)
              .borderRadius(12)
              .onClick(() => {
                this.submitReview();
              })
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
      const param = ctx.pathInfo.param as ShuYoRatePublishParam | undefined;
      if (param !== undefined) {
        this.unitId = param.unitId;
        this.courseName = param.courseName;
        this.teacherName = param.teacherName;
      }
    })
  }
}
