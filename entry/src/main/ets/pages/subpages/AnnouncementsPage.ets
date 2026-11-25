import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../../models/ShuYoModels';
import { ShuYoGlass, ShuYoMotion } from '../../core/ShuYoMotionGlass';
import { AnnouncementService } from '../../services/AnnouncementService';
import { NativeSystemService } from '../../services/NativeSystemService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState, ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function AnnouncementsPageBuilder(): void {
  AnnouncementsPage()
}

@ComponentV2
struct AnnouncementTableView {
  @Param rows: string[][] = [];
  @Param cellSurfaceColor: string = '#FFFFFF';
  @Param headerBgColor: string = '#F8FAFC';
  @Param lineBorderColor: string = '#E2E8F0';
  @Param cellTextColor: string = '#0F172A';
  @Param captionMutedColor: string = '#64748B';

  @Local colWidths: number[] = [];
  @Local totalWidth: number = 0;

  aboutToAppear(): void {
    this.recomputeMetrics();
  }

  @Monitor('rows')
  onRowsChanged(): void {
    this.recomputeMetrics();
  }

  private recomputeMetrics(): void {
    let maxCols = 0;
    for (let r = 0; r < this.rows.length; r++) {
      if (this.rows[r].length > maxCols) {
        maxCols = this.rows[r].length;
      }
    }
    if (maxCols <= 0) {
      this.colWidths = [];
      this.totalWidth = 0;
      return;
    }
    const widths: number[] = [];
    let sum = 0;
    for (let c = 0; c < maxCols; c++) {
      let maxUnits = 4;
      for (let r = 0; r < this.rows.length; r++) {
        const cell = c < this.rows[r].length ? this.rows[r][c] : '';
        let units = 0;
        for (let k = 0; k < cell.length; k++) {
          units += cell.charCodeAt(k) > 255 ? 2 : 1;
        }
        if (units > maxUnits) {
          maxUnits = units;
        }
      }
      const w = Math.max(78, Math.min(220, Math.round(20 + maxUnits * 7.2)));
      widths.push(w);
      sum += w;
    }
    this.colWidths = widths;
    this.totalWidth = sum;
  }

  build() {
    Column({ space: 4 }) {
      Scroll() {
        Column() {
          ForEach(this.rows, (row: string[], rIdx: number) => {
            Row() {
              ForEach(this.colWidths, (colW: number, cIdx: number) => {
                Text(cIdx < row.length && row[cIdx].length > 0 ? row[cIdx] : ' ')
                  .width(colW)
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .fontSize(12.5)
                  .lineHeight(18)
                  .fontWeight(rIdx === 0 && this.rows.length > 1 ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.cellTextColor)
                  .copyOption(CopyOptions.LocalDevice)
                  .border({
                    width: { right: cIdx < this.colWidths.length - 1 ? 1 : 0 },
                    color: this.lineBorderColor
                  })
              }, (colW: number, cIdx: number): string => `col-${rIdx}-${cIdx}-${colW}`)
            }
            .alignItems(VerticalAlign.Top)
            .backgroundColor(rIdx === 0 && this.rows.length > 1 ? this.headerBgColor : this.cellSurfaceColor)
            .border({
              width: { bottom: rIdx < this.rows.length - 1 ? 1 : 0 },
              color: this.lineBorderColor
            })
          }, (row: string[], rIdx: number): string => `row-${rIdx}-${row.length}`)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .borderRadius(10)
      .border({ width: 1, color: this.lineBorderColor })
      .backgroundColor(this.cellSurfaceColor)

      if (this.totalWidth > 300) {
        Text('← 左右滑动查看完整表格 →')
          .fontSize(11)
          .fontColor(this.captionMutedColor)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct AnnouncementsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local items: ShuYoAnnouncementItem[] = [];
  @Local selectedSource: string = '全部';
  @Local searchKeyword: string = '';
  @Local selectedDetail: ShuYoAnnouncementItem | undefined = undefined;
  @Local showDetailSheet: boolean = false;
  @Local previewImageUrl: string = '';
  @Local showImagePreview: boolean = false;
  @Local isLoading: boolean = false;
  @Local isLoadingDetail: boolean = false;
  @Local errorMessage: string = '';
  @Local detailError: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private sourceCache: Map<string, ShuYoAnnouncementItem[]> = new Map<string, ShuYoAnnouncementItem[]>();
  private detailScroller: Scroller = new Scroller();

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
    try {
      this.detailScroller.scrollEdge(Edge.Top);
    } catch (_err) {
      // Ignore if scroller is not attached yet
    }
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

  @Computed
  get displayedItems(): ShuYoAnnouncementItem[] {
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

  private getLinkLabel(blk: ShuYoAnnouncementBlock): string {
    if (blk.label !== undefined && blk.label.length > 0) {
      return blk.label;
    }
    const idx = blk.blockValue.indexOf('\n');
    return idx >= 0 ? blk.blockValue.substring(0, idx) : '查看附件 / 原文';
  }

  private getLinkUrl(blk: ShuYoAnnouncementBlock): string {
    const idx = blk.blockValue.indexOf('\n');
    return idx >= 0 ? blk.blockValue.substring(idx + 1) : blk.blockValue;
  }

  @Builder
  private imageBlockView(blk: ShuYoAnnouncementBlock) {
    Column({ space: 6 }) {
      Image(blk.blockValue)
        .width('100%')
        .constraintSize({ minHeight: 100, maxHeight: 420 })
        .objectFit(ImageFit.Contain)
        .borderRadius(10)
        .backgroundColor(this.store.colors.surfaceAlt)
        .onClick(() => {
          this.previewImageUrl = blk.blockValue;
          this.showImagePreview = true;
        })
      if (blk.alt !== undefined && blk.alt.length > 0) {
        Text(blk.alt)
          .fontSize(11)
          .fontColor(this.store.colors.textMuted)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private imagePreviewSheetBuilder() {
    Column({ space: 12 }) {
      Row() {
        Text('图片预览')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)
          .layoutWeight(1)
        if (this.previewImageUrl.length > 0) {
          Button('浏览器打开原图')
            .height(28)
            .fontSize(11)
            .fontColor(this.store.colors.accent)
            .backgroundColor(this.store.colors.accentSoft)
            .borderRadius(14)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              NativeSystemService.openExternalUrl(this.previewImageUrl, this.getUIContext());
            })
        }
      }
      .width('100%')

      if (this.previewImageUrl.length > 0) {
        Image(this.previewImageUrl)
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .borderRadius(12)
          .backgroundColor(this.store.colors.surfaceAlt)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private detailSheetBuilder() {
    Column() {
      Scroll(this.detailScroller) {
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
            if (blk.blockType === 'table' && blk.rows !== undefined && blk.rows.length > 0) {
              AnnouncementTableView({
                rows: blk.rows,
                cellSurfaceColor: this.store.colors.surface,
                headerBgColor: this.store.colors.surfaceAlt,
                lineBorderColor: this.store.colors.border,
                cellTextColor: this.store.colors.textPrimary,
                captionMutedColor: this.store.colors.textMuted
              })
            } else if (blk.blockType === 'image' && blk.blockValue.length > 0) {
              this.imageBlockView(blk)
            } else if (blk.blockType === 'link') {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.paperclip'))
                  .fontSize(16)
                  .fontColor([this.store.colors.accent])
                Column({ space: 2 }) {
                  Text(this.getLinkLabel(blk))
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.accent)
                  Text(this.getLinkUrl(blk))
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
                NativeSystemService.openExternalUrl(this.getLinkUrl(blk), this.getUIContext());
              })
            } else {
              Text(blk.blockValue)
                .fontSize(14)
                .lineHeight(22)
                .fontColor(this.store.colors.textPrimary)
                .copyOption(CopyOptions.LocalDevice)
                .width('100%')
            }
          }, (blk: ShuYoAnnouncementBlock, idx: number): string => `blk-${idx}-${blk.blockType}`)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 48 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.showImagePreview, this.imagePreviewSheetBuilder(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      backgroundColor: Color.Transparent,
      systemMaterial: ShuYoGlass.sheetMaterial()
    })
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
                .clickEffect(ShuYoMotion.lightClick)
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
        } else if (this.errorMessage.length > 0 && this.displayedItems.length === 0) {
          ShuYoEmptyState({
            emptyTitle: '公告加载失败',
            emptyHint: this.errorMessage,
            actionText: '重新加载',
            onActionTap: () => {
              this.refreshFeed(true);
            }
          })
        } else if (this.displayedItems.length === 0) {
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
            ForEach(this.displayedItems, (item: ShuYoAnnouncementItem, idx: number) => {
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
                .borderRadius(16)
                .backgroundColor(ShuYoGlass.cardSurfaceBg(this.store.colors))
                .border({ width: 0.8, color: ShuYoGlass.cardGlassBorder(this.store.colors) })
                .shadow(ShadowStyle.OUTER_DEFAULT_XS)
                .alignItems(HorizontalAlign.Start)
                .clickEffect(ShuYoMotion.lightClick)
                .onClick(() => {
                  this.openDetail(item);
                })
              }
            }, (item: ShuYoAnnouncementItem, idx: number): string => `${item.id}-${item.url}-${idx}`)
          }
          .cachedCount(4)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 165,
        colors: ShuYoGlass.ambientGradientColors(this.store.colors)
      })
      .bindSheet($$this.showDetailSheet, this.detailSheetBuilder(), {
        height: SheetSize.LARGE,
        dragBar: true,
        showClose: true,
        backgroundColor: Color.Transparent,
        systemMaterial: ShuYoGlass.sheetMaterial()
      })
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
