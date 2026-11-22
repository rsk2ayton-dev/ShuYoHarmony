import { pasteboard } from '@kit.BasicServicesKit';
import { ScheduleService } from '../../services/ScheduleService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function ScheduleSharePageBuilder(): void {
  ScheduleSharePage()
}

@ComponentV2
export struct ScheduleSharePage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local importTitle: string = '好友分享课表';
  @Local importCodeInput: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private getExportedJson(): string {
    return ScheduleService.exportScheduleCode(this.store.scheduleData);
  }

  private copyShareCode(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.getExportedJson());
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制课表分享口令到剪贴板' });
    } catch (_err) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    }
  }

  private handleImport(): void {
    const parsed = ScheduleService.importScheduleCode(this.importCodeInput);
    if (parsed === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '课表分享格式无效，请检查 JSON 内容' });
      return;
    }
    const title = this.importTitle.trim().length > 0 ? this.importTitle.trim() : '导入课表';
    this.store.addImportedCollection(title, parsed);
    this.getUIContext().getPromptAction().showToast({ message: `已导入并切换至「${title}」` });
    this.navStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '课表分享与导入',
          subtitleText: '导出 JSON 口令或导入好友课表',
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
        })

        Scroll() {
          Column({ space: 16 }) {
            // Export card
            Column({ space: 12 }) {
              Text('导出当前课表')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Text(`当前课表：${this.store.scheduleData.term.academicYearName} ${this.store.scheduleData.term.termName} · 共 ${this.store.scheduleData.sessions.length} 节课程`)
                .fontSize(13)
                .fontColor(this.store.colors.textTertiary)

              Button('复制课表分享口令 (JSON)')
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(12)
                .onClick(() => {
                  this.copyShareCode();
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Import card
            Column({ space: 10 }) {
              Text('导入课表')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)
              Text('课表名称')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '例如：室友课表 / 备选方案', text: this.importTitle })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.importTitle = val;
                })

              Text('粘贴课表分享 JSON')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextArea({ placeholder: '在此粘贴导出的课表 JSON 内容...', text: this.importCodeInput })
                .height(140)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.importCodeInput = val;
                })

              Button('解析并导入课表')
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontColor(this.store.colors.onSelectedFill)
                .backgroundColor(this.store.colors.selectedFill)
                .borderRadius(12)
                .onClick(() => {
                  this.handleImport();
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)
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
    })
  }
}
