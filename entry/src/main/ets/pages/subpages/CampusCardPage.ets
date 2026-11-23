import {
  ShuYoCampusCardBill,
  ShuYoDailySpending
} from '../../models/ShuYoModels';
import { CampusCardService } from '../../services/CampusCardService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function CampusCardPageBuilder(): void {
  CampusCardPage()
}

@ComponentV2
export struct CampusCardPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local filterType: string = 'all'; // 'all' | 'spend' | 'topup'
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private pendingReauthSync: boolean = false;

  aboutToAppear(): void {
    if (!this.store.isDemoMode && this.store.isLoggedIn && !this.store.isSyncingCampusCard) {
      this.refreshCard(false);
    }
  }

  private getSubtitle(): string {
    if (this.store.isDemoMode) {
      return '演示用户 · DEMO0001';
    }
    if (this.store.cardInfo.isLoaded) {
      return `${this.store.cardInfo.holderName} · ${this.store.cardInfo.studentId}`;
    }
    if (this.store.isLoggedIn) {
      return `${this.store.studentId} · 尚未同步一卡通`;
    }
    return '未登录校园账号';
  }

  private getBalanceDisplay(): string {
    if (this.store.cardInfo.isLoaded) {
      return `¥ ${this.store.cardInfo.balance.toFixed(2)}`;
    }
    if (this.store.isSyncingCampusCard) {
      return '查询中...';
    }
    return '¥ --';
  }

  private getCardMetaText(): string {
    const parts: string[] = [];
    if (this.store.cardInfo.validUntil.length > 0) {
      parts.push(`有效期至 ${this.store.cardInfo.validUntil}`);
    }
    if (this.store.campusCardUpdatedAt.length > 0) {
      parts.push(this.store.isDemoMode ? '演示数据' : `更新于 ${this.store.campusCardUpdatedAt}`);
    }
    if (parts.length === 0) {
      return '数据来自上海大学融合门户 (eportal.shu.edu.cn)';
    }
    return parts.join(' · ');
  }

  private getRangeBg(days: number): string {
    return this.store.campusCardRangeDays === days ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getRangeText(days: number): string {
    return this.store.campusCardRangeDays === days ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getDailySpending(): ShuYoDailySpending[] {
    return CampusCardService.summarizeDailySpending(this.store.cardBills);
  }

  private getMaxDailySpend(): number {
    const list = this.getDailySpending();
    let maxVal = 1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].totalAmount > maxVal) {
        maxVal = list[i].totalAmount;
      }
    }
    return maxVal;
  }

  private getBarHeight(val: number): number {
    const ratio = val / this.getMaxDailySpend();
    return Math.max(8, Math.round(ratio * 84));
  }

  private getFilteredBills(): ShuYoCampusCardBill[] {
    const out: ShuYoCampusCardBill[] = [];
    for (let i = 0; i < this.store.cardBills.length; i++) {
      const b = this.store.cardBills[i];
      if (this.filterType === 'spend' && b.amount <= 0) {
        continue;
      }
      if (this.filterType === 'topup' && b.amount >= 0) {
        continue;
      }
      out.push(b);
    }
    return out;
  }

  private getFilterBg(kind: string): string {
    return this.filterType === kind ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getFilterText(kind: string): string {
    return this.filterType === kind ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private formatAmount(amount: number): string {
    if (amount > 0) {
      return `-${amount.toFixed(2)}`;
    }
    return `+${Math.abs(amount).toFixed(2)}`;
  }

  private amountColor(amount: number): string {
    return amount > 0 ? this.store.colors.textPrimary : this.store.colors.success;
  }

  private async refreshCard(showToast: boolean): Promise<void> {
    const msg = await this.store.syncCampusCard();
    if (showToast) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: msg });
      } catch (_err) {
        // Ignore toast failure if page dismissed
      }
    }
  }

  private async switchRange(days: number): Promise<void> {
    if (this.store.campusCardRangeDays === days && this.store.cardInfo.isLoaded) {
      return;
    }
    const msg = await this.store.syncCampusCard(days);
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_err) {
      // Ignore toast failure if page dismissed
    }
  }

  private openRelogin(): void {
    this.pendingReauthSync = true;
    this.navStack.pushDestination({ name: 'NativeLoginPage' });
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '校园一卡通',
          subtitleText: this.getSubtitle(),
          showBack: true,
          rightLabel: this.store.isSyncingCampusCard ? '同步中' : '刷新',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            if (!this.store.isSyncingCampusCard) {
              this.refreshCard(true);
            }
          }
        })

        Scroll() {
          Column({ space: 14 }) {
            // Balance card
            Column({ space: 10 }) {
              Row() {
                Text('当前卡内余额')
                  .fontSize(13)
                  .fontColor(this.store.colors.onAccent)
                  .opacity(0.9)
                Blank()
                Text(this.store.cardInfo.cardStatus)
                  .fontSize(12)
                  .fontColor(this.store.colors.onAccent)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(8)
                  .backgroundColor('#33FFFFFF')
              }
              .width('100%')

              Text(this.getBalanceDisplay())
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.onAccent)

              Text(this.getCardMetaText())
                .fontSize(11)
                .fontColor(this.store.colors.onAccent)
                .opacity(0.85)
            }
            .width('100%')
            .padding(20)
            .borderRadius(18)
            .backgroundColor(this.store.colors.accent)
            .alignItems(HorizontalAlign.Start)

            // Sync / Error Banner
            if (this.store.isSyncingCampusCard) {
              Row({ space: 10 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.store.colors.accent)
                Text('正在从融合门户同步校园卡余额与交易记录...')
                  .fontSize(13)
                  .fontColor(this.store.colors.accent)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.store.colors.accentSoft)
            } else if (!this.store.isDemoMode && this.store.campusCardError.length > 0) {
              Column({ space: 10 }) {
                Text(this.store.campusCardError)
                  .fontSize(13)
                  .fontColor(this.store.colors.danger)
                  .width('100%')
                Row({ space: 10 }) {
                  if (this.store.campusCardAuthRequired) {
                    Button('重新登录认证')
                      .layoutWeight(1)
                      .height(36)
                      .fontSize(13)
                      .fontColor(this.store.colors.onAccent)
                      .backgroundColor(this.store.colors.accent)
                      .borderRadius(10)
                      .onClick(() => {
                        this.openRelogin();
                      })
                  }
                  Button('立即重试')
                    .layoutWeight(1)
                    .height(36)
                    .fontSize(13)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .border({ width: 1, color: this.store.colors.border })
                    .borderRadius(10)
                    .onClick(() => {
                      this.refreshCard(true);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
            }

            // Range Selector (real query horizon)
            if (!this.store.isDemoMode) {
              Row({ space: 8 }) {
                Text('查询范围')
                  .fontSize(12)
                  .fontColor(this.store.colors.textTertiary)
                Blank()
                Button('近30天')
                  .height(28)
                  .fontSize(12)
                  .fontColor(this.getRangeText(30))
                  .backgroundColor(this.getRangeBg(30))
                  .borderRadius(14)
                  .padding({ left: 10, right: 10 })
                  .enabled(!this.store.isSyncingCampusCard)
                  .onClick(() => {
                    this.switchRange(30);
                  })
                Button('近90天')
                  .height(28)
                  .fontSize(12)
                  .fontColor(this.getRangeText(90))
                  .backgroundColor(this.getRangeBg(90))
                  .borderRadius(14)
                  .padding({ left: 10, right: 10 })
                  .enabled(!this.store.isSyncingCampusCard)
                  .onClick(() => {
                    this.switchRange(90);
                  })
                Button('近1年')
                  .height(28)
                  .fontSize(12)
                  .fontColor(this.getRangeText(365))
                  .backgroundColor(this.getRangeBg(365))
                  .borderRadius(14)
                  .padding({ left: 10, right: 10 })
                  .enabled(!this.store.isSyncingCampusCard)
                  .onClick(() => {
                    this.switchRange(365);
                  })
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }

            // Spending Bar Chart Card
            Column({ space: 12 }) {
              Text('近期日消费趋势')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)

              if (this.getDailySpending().length === 0) {
                Text(this.store.cardInfo.isLoaded ? '所选时间段暂无消费记录' : '同步校园卡后将展示日消费趋势')
                  .fontSize(13)
                  .fontColor(this.store.colors.textTertiary)
                  .padding({ top: 12, bottom: 12 })
              } else {
                Row({ space: 8 }) {
                  ForEach(this.getDailySpending(), (item: ShuYoDailySpending, idx: number) => {
                    Column({ space: 4 }) {
                      Text(`¥${item.totalAmount.toFixed(0)}`)
                        .fontSize(10)
                        .fontColor(this.store.colors.textTertiary)
                      Column()
                        .width(22)
                        .height(this.getBarHeight(item.totalAmount))
                        .borderRadius(6)
                        .backgroundColor(this.store.colors.accent)
                      Text(item.dateLabel)
                        .fontSize(10)
                        .fontColor(this.store.colors.textMuted)
                    }
                    .layoutWeight(1)
                    .height(128)
                    .justifyContent(FlexAlign.End)
                    .alignItems(HorizontalAlign.Center)
                  }, (item: ShuYoDailySpending, idx: number): string => `bar-${item.dateLabel}-${idx}`)
                }
                .width('100%')
                .padding({ top: 6 })
              }
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Filter Chips
            Row({ space: 8 }) {
              Button('全部记录')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterText('all'))
                .backgroundColor(this.getFilterBg('all'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.filterType = 'all';
                })
              Button('消费')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterText('spend'))
                .backgroundColor(this.getFilterBg('spend'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.filterType = 'spend';
                })
              Button('充值')
                .height(32)
                .fontSize(12)
                .fontColor(this.getFilterText('topup'))
                .backgroundColor(this.getFilterBg('topup'))
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.filterType = 'topup';
                })
            }
            .width('100%')

            // Bill List
            if (this.getFilteredBills().length === 0) {
              Column() {
                Text(this.store.cardInfo.isLoaded ? '当前筛选条件下暂无流水记录' : '尚未获取校园卡交易记录')
                  .fontSize(13)
                  .fontColor(this.store.colors.textTertiary)
              }
              .width('100%')
              .padding(24)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else {
              Column({ space: 8 }) {
                ForEach(this.getFilteredBills(), (bill: ShuYoCampusCardBill, idx: number) => {
                  Row() {
                    Column({ space: 3 }) {
                      Text(bill.merchantName)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.store.colors.textPrimary)
                      Text(bill.payTime)
                        .fontSize(12)
                        .fontColor(this.store.colors.textMuted)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(this.formatAmount(bill.amount))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.amountColor(bill.amount))
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(12)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                }, (bill: ShuYoCampusCardBill, idx: number): string => `${bill.id}-${idx}`)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onShown(() => {
      if (this.pendingReauthSync) {
        this.pendingReauthSync = false;
        if (!this.store.isDemoMode && this.store.isLoggedIn && !this.store.isSyncingCampusCard) {
          this.refreshCard(false);
        }
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
