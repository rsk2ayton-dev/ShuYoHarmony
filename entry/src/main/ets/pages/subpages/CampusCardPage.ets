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

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '校园一卡通',
          subtitleText: `${this.store.cardInfo.holderName} · ${this.store.cardInfo.studentId}`,
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
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

              Text(`¥ ${this.store.cardInfo.balance.toFixed(2)}`)
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.onAccent)
            }
            .width('100%')
            .padding(20)
            .borderRadius(18)
            .backgroundColor(this.store.colors.accent)
            .alignItems(HorizontalAlign.Start)

            // Spending Bar Chart Card
            Column({ space: 12 }) {
              Text('近期日消费趋势')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)

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
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
