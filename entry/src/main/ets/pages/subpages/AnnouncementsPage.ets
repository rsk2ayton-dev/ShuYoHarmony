import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../../models/ShuYoModels';
import { AnnouncementService } from '../../services/AnnouncementService';
import { NativeSystemService } from '../../services/NativeSystemService';
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
  @Local isLoadingDetail: boolean = false;
  @Local errorMessage: string = '';
  @Local detailError: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private sourceCache: Map<string, ShuYoAnnouncementItem[]> = new Map<string, ShuYoAnnouncementItem[]>();

  aboutToAppear(): void {
    if (this.store.isDemoMode) {
      this.items = AnnouncementService.loadDemoAnnouncements();
      return;
    }
    if (this.store.announcements.length > 0) {
      this.items = this.store.announcements;
      this.sourceCache.set('全部', this.store.announcements);
    } else {
      this.refreshFeed(false);
    }
  }

  private async selectSourceTab(tabName: string): Promise<void> {
    if (this.selectedSource === tabName) {
      return;
    }
    this.selectedSource = tabName;
    if (this.store.isDemoMode) {
      return;
    }
    const cached = this.sourceCache.get(tabName);
    if (cached !== undefined && cached.length > 0) {
      this.items = cached;
      this.errorMessage = '';
      return;
    }
    await this.refreshFeed(false);
  }

  private async refreshFeed(showToast: boolean = true): Promise<void> {
    if (this.store.isDemoMode) {
      this.items = AnnouncementService.loadDemoAnnouncements();
      this.errorMessage = '';
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({ message: '演示公告已刷新' });
      }
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    const requestedSource = this.selectedSource;
    try {
      const liveItems = await AnnouncementService.fetchLiveAnnouncements(requestedSource);
      this.sourceCache.set(requestedSource, liveItems);
      if (this.selectedSource === requestedSource) {
        this.items = liveItems;
      }
      if (requestedSource === '全部') {
        this.store.announcements = liveItems;
        this.store.announcementsError = '';
      }
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({ message: `已加载 ${liveItems.length} 条通知公告` });
      }
    } catch (err) {
      const e = err as Error;
      const msg = e.message.length > 0 ? e.message : '无法加载通知公告，请检查网络';
      if (this.selectedSource === requestedSource) {
        this.errorMessage = msg;
        if (this.sourceCache.get(requestedSource) === undefined) {
          this.items = [];
        }
      }
    } finally {
      this.isLoading = false;
    }
  }

  private async openDetail(item: ShuYoAnnouncementItem): Promise<void> {
    this.selectedDetail = item;
    this.detailError = '';
    this.showDetailSheet = true;
    if (this.store.isDemoMode || item.blocks.length > 0) {
      return;
    }
    this.isLoadingDetail = true;
    try {
      const detailed = await AnnouncementService.fetchLiveDetail(item);
      if (this.selectedDetail !== undefined && this.selectedDetail.url === item.url) {
        this.selectedDetail = detailed;
      }
      this.replaceCachedItem(detailed);
    } catch (err) {
      const e = err as Error;
      this.detailError = e.message.length > 0 ? e.message : '公告正文加载失败';
    } finally {
      this.isLoadingDetail = false;
    }
  }

  private replaceCachedItem(updated: ShuYoAnnouncementItem): void {
    const nextList: ShuYoAnnouncementItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      nextList.push(this.items[i].url === updated.url ? updated : this.items[i]);
    }
    this.items = nextList;
  }

  private copyUrlToClipboard(urlText: string): void {
    if (urlText.length === 0) {
      return;
    }
    if (NativeSystemService.copyToClipboard(urlText)) {
      this.getUIContext().getPromptAction().showToast({ message: '已复制链接到剪贴板' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '复制链接失败' });
    }
  }

  private getDisplayedItems(): ShuYoAnnouncementItem[] {
    const kw = this.searchKeyword.trim().toLowerCase();
    const out: ShuYoAnnouncementItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (this.store.isDemoMode && this.selectedSource !== '全部') {
        const matchesSource = item.sourceName.includes(this.selectedSource) ||
          (this.selectedSource === '上海大学官网' && item.sourceName.includes('学校主页'));
        if (!matchesSource) {
          continue;
        }
      }
      if (kw.length > 0) {
        const hay = `${item.title} ${item.summary} ${item.department} ${item.sourceName}`.toLowerCase();
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

  private getLinkLabel(val: string): string {
    const idx = val.indexOf('\n');
    return idx >= 0 ? val.substring(0, idx) : '查看附件 / 原文';
  }

  private getLinkUrl(val: string): string {
    const idx = val.indexOf('\n');
    return idx >= 0 ? val.substring(idx + 1) : val;
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

          Row({ space: 6 }) {
            Text(`${this.selectedDetail.sourceName} · ${this.selectedDetail.dateText}`)
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
              .layoutWeight(1)
            if (this.selectedDetail.url.length > 0) {
              Button('浏览器打开')
                .height(26)
                .fontSize(11)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(13)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  if (this.selectedDetail !== undefined) {
                    NativeSystemService.openExternalUrl(this.selectedDetail.url, this.getUIContext());
                  }
                })
              Button('分享')
                .height(26)
                .fontSize(11)
                .fontColor(this.store.colors.accent)
                .backgroundColor(this.store.colors.accentSoft)
                .borderRadius(13)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  if (this.selectedDetail !== undefined) {
                    NativeSystemService.shareLink(
                      this.selectedDetail.title,
                      this.selectedDetail.url,
                      this.selectedDetail.sourceName,
                      this.getUIContext()
                    );
                  }
                })
              Button('复制')
                .height(26)
                .fontSize(11)
                .fontColor(this.store.colors.textSecondary)
                .backgroundColor(this.store.colors.surfaceAlt)
                .border({ width: 1, color: this.store.colors.border })
                .borderRadius(13)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  if (this.selectedDetail !== undefined) {
                    this.copyUrlToClipboard(this.selectedDetail.url);
                  }
                })
            }
          }
          .width('100%')

          if (this.isLoadingDetail) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20).color(this.store.colors.accent)
              Text('正在加载公告正文...')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
          } else if (this.detailError.length > 0) {
            Column({ space: 8 }) {
              Text(this.detailError)
                .fontSize(13)
                .fontColor(this.store.colors.danger)
              Button('重试加载')
                .height(34)
                .fontSize(12)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(10)
                .onClick(() => {
                  if (this.selectedDetail !== undefined) {
                    this.openDetail(this.selectedDetail);
                  }
                })
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor(this.store.colors.surfaceAlt)
            .alignItems(HorizontalAlign.Start)
          }

          if (this.selectedDetail.summary.length > 0 && this.selectedDetail.blocks.length === 0) {
            Text(this.selectedDetail.summary)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(this.store.colors.textSecondary)
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surfaceAlt)
              .width('100%')
          }

          ForEach(this.selectedDetail.blocks, (blk: ShuYoAnnouncementBlock, idx: number) => {
            if (blk.blockType === 'link') {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.paperclip'))
                  .fontSize(16)
                  .fontColor([this.store.colors.accent])
                Column({ space: 2 }) {
                  Text(this.getLinkLabel(blk.blockValue))
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.accent)
                  Text(this.getLinkUrl(blk.blockValue))
                    .fontSize(11)
                    .fontColor(this.store.colors.textMuted)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('打开')
                  .fontSize(12)
                  .fontColor(this.store.colors.accent)
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.store.colors.accentSoft)
              .onClick(() => {
                NativeSystemService.openExternalUrl(this.getLinkUrl(blk.blockValue), this.getUIContext());
              })
            } else {
              Text(blk.blockValue)
                .fontSize(14)
                .lineHeight(22)
                .fontColor(this.store.colors.textPrimary)
                .width('100%')
            }
          }, (blk: ShuYoAnnouncementBlock, idx: number): string => `blk-${idx}-${blk.blockType}`)
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
          rightLabel: '刷新',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.refreshFeed(true);
          }
        })

        // Source chips (horizontal scroll)
        Scroll() {
          Row({ space: 8 }) {
            ForEach(AnnouncementService.filterSources, (tabName: string, idx: number) => {
              Button(tabName)
                .height(32)
                .fontSize(12)
                .fontColor(this.getChipText(tabName))
                .backgroundColor(this.getChipBg(tabName))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.selectSourceTab(tabName);
                })
            }, (tabName: string, idx: number): string => `src-${tabName}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(36)

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

        if (this.isLoading && this.items.length === 0) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36).color(this.store.colors.accent)
            Text('正在获取校内最新通知公告...')
              .fontSize(13)
              .fontColor(this.store.colors.textTertiary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMessage.length > 0 && this.getDisplayedItems().length === 0) {
          ShuYoEmptyState({
            emptyTitle: '公告加载失败',
            emptyHint: this.errorMessage,
            actionText: '重新加载',
            onActionTap: () => {
              this.refreshFeed(true);
            }
          })
        } else if (this.getDisplayedItems().length === 0) {
          ShuYoEmptyState({
            emptyTitle: '暂无符合条件的公告',
            emptyHint: '可点击下方按钮刷新或切换栏目查看',
            actionText: '刷新公告',
            onActionTap: () => {
              this.refreshFeed(true);
            }
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
                  this.openDetail(item);
                })
              }
            }, (item: ShuYoAnnouncementItem, idx: number): string => `${item.id}-${item.url}-${idx}`)
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
