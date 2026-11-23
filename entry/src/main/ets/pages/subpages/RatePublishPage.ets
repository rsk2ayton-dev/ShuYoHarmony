import {
  ShuYoRateOption,
  ShuYoRatePublishParam,
  ShuYoRateQuestion
} from '../../models/ShuYoModels';
import { CourseReviewService } from '../../services/CourseReviewService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

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
  @Local questions: ShuYoRateQuestion[] = [];
  @Local overallScore: number = 5;
  @Local selectedAnswers: Record<string, string[]> = {};
  @Local selectionRevision: number = 0;
  @Local commentInput: string = '';
  @Local isSubmitting: boolean = false;
  @Local isLoadingQuestions: boolean = false;
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    if (this.store.isDemoMode) {
      this.questions = CourseReviewService.emptyHome().questions;
      this.selectedAnswers = { 'grading': ['fair'], 'teaching': ['clear'] };
      return;
    }
    this.loadLiveQuestions();
  }

  private async loadLiveQuestions(): Promise<void> {
    this.isLoadingQuestions = true;
    try {
      const qs = await CourseReviewService.fetchLiveQuestions();
      this.questions = qs;
      const next: Record<string, string[]> = {};
      for (let i = 0; i < qs.length; i++) {
        if (qs[i].key !== 'overall') {
          next[qs[i].key] = [];
        }
      }
      this.selectedAnswers = next;
    } finally {
      this.isLoadingQuestions = false;
    }
  }

  private isOptionSelected(questionKey: string, optKey: string): boolean {
    if (questionKey === 'overall') {
      return String(this.overallScore) === optKey;
    }
    const arr = this.selectedAnswers[questionKey];
    return arr !== undefined && arr.includes(optKey);
  }

  private toggleOption(q: ShuYoRateQuestion, optKey: string): void {
    if (q.key === 'overall') {
      const parsed = parseInt(optKey, 10);
      if (Number.isFinite(parsed) && parsed >= 1 && parsed <= 5) {
        this.overallScore = parsed;
      }
      this.selectionRevision++;
      return;
    }
    const current = this.selectedAnswers[q.key] ?? [];
    const nextMap: Record<string, string[]> = {};
    const keys = Object.keys(this.selectedAnswers);
    for (let i = 0; i < keys.length; i++) {
      nextMap[keys[i]] = this.selectedAnswers[keys[i]];
    }

    if (!q.multiple) {
      if (current.includes(optKey) && !q.required) {
        nextMap[q.key] = [];
      } else {
        nextMap[q.key] = [optKey];
      }
      this.selectedAnswers = nextMap;
      this.selectionRevision++;
      return;
    }

    if (current.includes(optKey)) {
      const filtered: string[] = [];
      for (let i = 0; i < current.length; i++) {
        if (current[i] !== optKey) {
          filtered.push(current[i]);
        }
      }
      nextMap[q.key] = filtered;
      this.selectedAnswers = nextMap;
      this.selectionRevision++;
      return;
    }

    const maxAllowed = q.maxSelections > 0 ? q.maxSelections : q.options.length;
    if (current.length >= maxAllowed) {
      this.getUIContext().getPromptAction().showToast({ message: `“${q.title}”最多选择 ${maxAllowed} 项` });
      return;
    }
    nextMap[q.key] = [...current, optKey];
    this.selectedAnswers = nextMap;
    this.selectionRevision++;
  }

  private getQuestionHint(q: ShuYoRateQuestion): string {
    if (q.key === 'overall') {
      return q.required ? '必答' : '可跳过';
    }
    const mode = q.multiple ? `可多选(最多${q.maxSelections}项)` : '单选';
    return q.required ? `${mode} · 必答` : mode;
  }

  private async submitReview(): Promise<void> {
    if (this.unitId.length === 0 || this.isSubmitting) {
      return;
    }
    for (let i = 0; i < this.questions.length; i++) {
      const q = this.questions[i];
      if (q.required && q.key !== 'overall') {
        const picked = this.selectedAnswers[q.key] ?? [];
        if (picked.length === 0) {
          this.getUIContext().getPromptAction().showToast({ message: `请先回答“${q.title}”` });
          return;
        }
      }
    }

    if (this.store.isDemoMode) {
      const gradingArr = this.selectedAnswers['grading'] ?? [];
      const gradingKey = gradingArr.length > 0 ? gradingArr[0] : '';
      const teachingKeys = this.selectedAnswers['teaching'] ?? [];
      CourseReviewService.submitDemoReview(
        this.unitId,
        this.overallScore,
        gradingKey,
        teachingKeys,
        this.commentInput
      );
      this.store.rateHome = CourseReviewService.buildDemoHome(this.store.scheduleData);
      this.getUIContext().getPromptAction().showToast({ message: '评价已发布' });
      this.navStack.pop();
      return;
    }

    this.isSubmitting = true;
    try {
      const cleanAnswers: Record<string, string[]> = {};
      for (let i = 0; i < this.questions.length; i++) {
        const q = this.questions[i];
        if (q.key !== 'overall') {
          cleanAnswers[q.key] = this.selectedAnswers[q.key] ?? [];
        }
      }
      await CourseReviewService.submitLiveReview(
        this.store.studentId,
        this.store.campusSystem,
        this.unitId,
        this.overallScore,
        cleanAnswers
      );
      this.store.syncRateHome();
      this.getUIContext().getPromptAction().showToast({ message: '课程评价已提交' });
      this.navStack.pop();
    } catch (err) {
      const e = err as Error;
      const msg = e.message.length > 0 ? e.message : '提交评价失败，请稍后重试';
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } finally {
      this.isSubmitting = false;
    }
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
          rightLabel: this.isSubmitting ? '提交中' : '提交',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.submitReview();
          }
        })

        if (this.isLoadingQuestions && this.questions.length === 0) {
          Column({ space: 10 }) {
            LoadingProgress().width(34).height(34).color(this.store.colors.accent)
            Text('正在加载评课问卷...')
              .fontSize(13)
              .fontColor(this.store.colors.textTertiary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 14 }) {
              ForEach(this.questions, (q: ShuYoRateQuestion, qIdx: number) => {
                Column({ space: 10 }) {
                  Row() {
                    Text(q.required ? `${q.title} *` : q.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                      .layoutWeight(1)
                    Text(this.getQuestionHint(q))
                      .fontSize(11)
                      .fontColor(this.store.colors.textMuted)
                  }
                  .width('100%')

                  Column({ space: 8 }) {
                    ForEach(q.options, (opt: ShuYoRateOption, oIdx: number) => {
                      Button(opt.label)
                        .width('100%')
                        .height(38)
                        .fontSize(13)
                        .fontColor(this.getChipText(this.isOptionSelected(q.key, opt.key)))
                        .backgroundColor(this.getChipBg(this.isOptionSelected(q.key, opt.key)))
                        .borderRadius(10)
                        .onClick(() => {
                          this.toggleOption(q, opt.key);
                        })
                    }, (opt: ShuYoRateOption, oIdx: number): string => `${q.key}-${opt.key}-${this.selectionRevision}`)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })
                .alignItems(HorizontalAlign.Start)
              }, (q: ShuYoRateQuestion, qIdx: number): string => `q-${q.key}-${qIdx}-${this.selectionRevision}`)

              if (this.store.isDemoMode) {
                Column({ space: 8 }) {
                  Text('课程评价正文（演示）')
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
              }

              Button(this.isSubmitting ? '正在提交...' : '提交课程评价')
                .width('100%')
                .height(46)
                .fontSize(15)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(12)
                .enabled(!this.isSubmitting)
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
