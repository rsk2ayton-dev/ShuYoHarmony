import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../../models/ShuYoModels';
import { AnnouncementService } from '../../services/AnnouncementService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState, ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function AnnouncementsPageBuilder(): void {
  AnnouncementsPage()
}

@ComponentV2
export struct AnnouncementsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local items: ShuYoAnnouncementItem[] = [];
  @Local selectedSource: string = '全部';
  @Local searchKeyword: string = '';
  @Local selectedDetail: ShuYoAnnouncementItem | undefined = undefined;
  @Local showDetailSheet: boolean = false;
  @Local isLoading: boolean = false;
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly filterTabs: string[] = ['全部', '学校主页', '教务处'];

  aboutToAppear(): void {
    this.items = this.store.announcements;
  }

  private async refreshFeed(): Promise<void> {
    if (this.store.isDemoMode) {
      this.items = AnnouncementService.loadDemoAnnouncements();
      this.getUIContext().getPromptAction().showToast({ message: '演示公告已刷新' });
      return;
    }
    this.isLoading = true;
    try {
      const target = this.selectedSource === '教务处' ? '教务处' : '学校主页';
      this.items = await AnnouncementService.fetchLiveAnnouncements(target);
    } catch (_err) {
      this.items = AnnouncementService.loadDemoAnnouncements();
    } finally {
      this.isLoading = false;
    }
  }

  private getDisplayedItems(): ShuYoAnnouncementItem[] {
    const kw = this.searchKeyword.trim().toLowerCase();
    const out: ShuYoAnnouncementItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (this.selectedSource !== '全部' && !item.sourceName.includes(this.selectedSource) && this.selectedSource !== '学校主页') {
        continue;
      }
      if (kw.length > 0) {
        const hay = `${item.title} ${item.summary} ${item.department}`.toLowerCase();
        if (!hay.includes(kw)) {
          continue;
        }
      }
      out.push(item);
    }
    return out;
  }

  private getChipBg(label: string): string {
    return this.selectedSource === label ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getChipText(label: string): string {
    return this.selectedSource === label ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  @Builder
  private detailSheetBuilder() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.selectedDetail !== undefined) {
          Text(this.selectedDetail.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)

          Text(`${this.selectedDetail.sourceName} · ${this.selectedDetail.dateText}`)
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)

          if (this.selectedDetail.summary.length > 0) {
            Text(this.selectedDetail.summary)
              .fontSize(14)
              .fontColor(this.store.colors.textSecondary)
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surfaceAlt)
              .width('100%')
          }

          ForEach(this.selectedDetail.blocks, (blk: ShuYoAnnouncementBlock, idx: number) => {
            Text(blk.blockValue)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(this.store.colors.textPrimary)
              .width('100%')
          }, (blk: ShuYoAnnouncementBlock, idx: number): string => `blk-${idx}`)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .backgroundColor(this.store.colors.surface)
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '通知公告',
          subtitleText: '上海大学校内资讯汇总',
          showBack: true,
          rightLabel: '',
          rightSymbolName: 'refresh',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.refreshFeed();
          }
        })

        // Source chips
        Row({ space: 8 }) {
          ForEach(this.filterTabs, (tabName: string, idx: number) => {
            Button(tabName)
              .height(32)
              .fontSize(12)
              .fontColor(this.getChipText(tabName))
              .backgroundColor(this.getChipBg(tabName))
              .borderRadius(16)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.selectedSource = tabName;
              })
          }, (tabName: string, idx: number): string => `src-${tabName}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // Search bar
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([this.store.colors.textMuted])
          TextInput({ placeholder: '搜索通知标题或发布部门', text: this.searchKeyword })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor(this.store.colors.textPrimary)
            .fontSize(13)
            .onChange((val: string) => {
              this.searchKeyword = val;
            })
        }
        .height(42)
        .padding({ left: 12, right: 12 })
        .margin({ left: 16, right: 16 })
        .borderRadius(12)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(36).height(36).color(this.store.colors.accent)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.getDisplayedItems().length === 0) {
          ShuYoEmptyState({
            emptyTitle: '暂无符合条件的公告',
            emptyHint: '',
            actionText: '',
            onActionTap: () => {}
          })
        } else {
          List({ space: 10 }) {
            ForEach(this.getDisplayedItems(), (item: ShuYoAnnouncementItem, idx: number) => {
              ListItem() {
                Column({ space: 6 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  if (item.summary.length > 0) {
                    Text(item.summary)
                      .fontSize(13)
                      .fontColor(this.store.colors.textSecondary)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  Row() {
                    Text(item.sourceName)
                      .fontSize(11)
                      .fontColor(this.store.colors.accent)
                    Blank()
                    Text(item.dateText)
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
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.selectedDetail = item;
                  this.showDetailSheet = true;
                })
              }
            }, (item: ShuYoAnnouncementItem, idx: number): string => `${item.id}-${idx}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
      .bindSheet($$this.showDetailSheet, this.detailSheetBuilder(), {
        height: SheetSize.LARGE,
        dragBar: true,
        showClose: true
      })
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
