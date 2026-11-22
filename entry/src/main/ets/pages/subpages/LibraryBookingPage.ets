import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../../models/ShuYoModels';
import { LibraryBookingService } from '../../services/LibraryBookingService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState, ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function LibraryBookingPageBuilder(): void {
  LibraryBookingPage()
}

@ComponentV2
export struct LibraryBookingPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local selectedVenueIdx: number = 0;
  @Local selectedAreaIdx: number = 0;
  @Local activeTabMode: number = 0; // 0: 选座预约, 1: 我的预约, 2: 平面图与规则
  @Local selectedStartTime: string = '09:00';
  @Local selectedEndTime: string = '12:00';
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private getCurrentVenue(): ShuYoLibraryVenue {
    return LibraryBookingService.venues[this.selectedVenueIdx];
  }

  private getAreas(): ShuYoLibraryArea[] {
    return LibraryBookingService.buildAreasForVenue(this.getCurrentVenue(), this.store.libraryBookings);
  }

  private getCurrentArea(): ShuYoLibraryArea | undefined {
    const areas = this.getAreas();
    if (areas.length === 0) {
      return undefined;
    }
    const idx = Math.min(this.selectedAreaIdx, areas.length - 1);
    return areas[idx];
  }

  private getTabBg(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getTabText(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getSeatBg(seat: ShuYoLibrarySeat): string {
    if (seat.isDisabled) {
      return this.store.colors.disabledFill;
    }
    if (seat.isBooked) {
      return this.store.colors.accent;
    }
    if (seat.isBusy) {
      return this.store.colors.surfaceMuted;
    }
    return this.store.colors.surfaceAlt;
  }

  private getSeatText(seat: ShuYoLibrarySeat): string {
    if (seat.isBooked) {
      return this.store.colors.onAccent;
    }
    if (seat.isDisabled || seat.isBusy) {
      return this.store.colors.textMuted;
    }
    return this.store.colors.textPrimary;
  }

  private bookSeat(seat: ShuYoLibrarySeat, area: ShuYoLibraryArea): void {
    if (seat.isDisabled || seat.isBusy || seat.isBooked) {
      this.getUIContext().getPromptAction().showToast({ message: '该座位当前不可预约' });
      return;
    }
    const venue = this.getCurrentVenue();
    const day = LibraryBookingService.todayDateStr();
    const rec: ShuYoLibraryBookingRecord = {
      id: `bk-${Date.now()}`,
      venueId: venue.id,
      venueName: venue.name,
      areaId: area.id,
      areaName: area.name,
      seatId: seat.id,
      seatLabel: seat.seatLabel,
      day: day,
      beginTime: `${day} ${this.selectedStartTime}`,
      endTime: `${day} ${this.selectedEndTime}`,
      status: 'BOOKING'
    };
    this.store.addLibraryBooking(rec);
    this.getUIContext().getPromptAction().showToast({
      message: `已预约 ${venue.name} ${area.name} ${seat.seatLabel}号`
    });
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '图书馆预约',
          subtitleText: '上海大学座位与研习空间',
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
        })

        // Mode Tabs
        Row({ space: 8 }) {
          Button('选座预约')
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText(0))
            .backgroundColor(this.getTabBg(0))
            .borderRadius(12)
            .onClick(() => {
              this.activeTabMode = 0;
            })
          Button(`我的预约 (${this.store.libraryBookings.length})`)
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText(1))
            .backgroundColor(this.getTabBg(1))
            .borderRadius(12)
            .onClick(() => {
              this.activeTabMode = 1;
            })
          Button('平面与规则')
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText(2))
            .backgroundColor(this.getTabBg(2))
            .borderRadius(12)
            .onClick(() => {
              this.activeTabMode = 2;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.activeTabMode === 0) {
          Scroll() {
            Column({ space: 12 }) {
              // Venues
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(LibraryBookingService.venues, (v: ShuYoLibraryVenue, idx: number) => {
                    Button(v.name)
                      .height(32)
                      .fontSize(12)
                      .fontColor(this.selectedVenueIdx === idx ? this.store.colors.onAccent : this.store.colors.textSecondary)
                      .backgroundColor(this.selectedVenueIdx === idx ? this.store.colors.accent : this.store.colors.chipFill)
                      .borderRadius(16)
                      .padding({ left: 12, right: 12 })
                      .onClick(() => {
                        this.selectedVenueIdx = idx;
                        this.selectedAreaIdx = 0;
                      })
                  }, (v: ShuYoLibraryVenue, idx: number): string => `ven-${v.id}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(36)

              // Areas
              Row({ space: 8 }) {
                ForEach(this.getAreas(), (area: ShuYoLibraryArea, aIdx: number) => {
                  Button(`${area.name} (${area.freeCount}/${area.totalCount})`)
                    .height(32)
                    .fontSize(12)
                    .fontColor(this.selectedAreaIdx === aIdx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary)
                    .backgroundColor(this.selectedAreaIdx === aIdx ? this.store.colors.selectedFill : this.store.colors.chipFill)
                    .borderRadius(14)
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      this.selectedAreaIdx = aIdx;
                    })
                }, (area: ShuYoLibraryArea, aIdx: number): string => `area-${area.id}-${area.freeCount}`)
              }
              .width('100%')

              // Time selector
              Row({ space: 8 }) {
                Text('预约时段：')
                  .fontSize(12)
                  .fontColor(this.store.colors.textSecondary)
                Text(`${this.selectedStartTime} - ${this.selectedEndTime}`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.accent)
                Blank()
                Button('09:00-12:00')
                  .height(26)
                  .fontSize(11)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.selectedStartTime = '09:00';
                    this.selectedEndTime = '12:00';
                  })
                Button('14:00-17:00')
                  .height(26)
                  .fontSize(11)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.selectedStartTime = '14:00';
                    this.selectedEndTime = '17:00';
                  })
                Button('18:00-21:30')
                  .height(26)
                  .fontSize(11)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.selectedStartTime = '18:00';
                    this.selectedEndTime = '21:30';
                  })
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })

              // Seat Grid
              if (this.getCurrentArea() !== undefined) {
                Column({ space: 10 }) {
                  Row({ space: 14 }) {
                    Text('■ 可选')
                      .fontSize(11)
                      .fontColor(this.store.colors.textSecondary)
                    Text('■ 已占/维护')
                      .fontSize(11)
                      .fontColor(this.store.colors.textMuted)
                    Text('■ 我的预约')
                      .fontSize(11)
                      .fontColor(this.store.colors.accent)
                  }
                  .width('100%')

                  Grid() {
                    ForEach(this.getCurrentArea()!.seats, (seat: ShuYoLibrarySeat, sIdx: number) => {
                      GridItem() {
                        Column({ space: 2 }) {
                          Text(seat.seatLabel)
                            .fontSize(14)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(this.getSeatText(seat))
                          Text(seat.isDisabled ? '停用' : (seat.isBooked ? '已约' : (seat.isBusy ? '占用' : '空闲')))
                            .fontSize(10)
                            .fontColor(this.getSeatText(seat))
                        }
                        .width('100%')
                        .height(54)
                        .borderRadius(10)
                        .backgroundColor(this.getSeatBg(seat))
                        .border({ width: 1, color: this.store.colors.border })
                        .justifyContent(FlexAlign.Center)
                        .onClick(() => {
                          const area = this.getCurrentArea();
                          if (area !== undefined) {
                            this.bookSeat(seat, area);
                          }
                        })
                      }
                    }, (seat: ShuYoLibrarySeat, sIdx: number): string => `${seat.id}-${seat.isBooked}-${this.store.dataRevision}`)
                  }
                  .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
                  .columnsGap(8)
                  .rowsGap(8)
                  .width('100%')
                  .height(185)
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else if (this.activeTabMode === 1) {
          if (this.store.libraryBookings.length === 0) {
            ShuYoEmptyState({
              emptyTitle: '暂无预约记录',
              emptyHint: '切换到“选座预约”页面即可点击空闲座位进行预约',
              actionText: '去选座',
              onActionTap: () => {
                this.activeTabMode = 0;
              }
            })
          } else {
            List({ space: 10 }) {
              ForEach(this.store.libraryBookings, (rec: ShuYoLibraryBookingRecord, idx: number) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Column({ space: 4 }) {
                      Text(`${rec.venueName} · ${rec.areaName} (${rec.seatLabel}号)`)
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.textPrimary)
                      Text(`${rec.beginTime} 至 ${rec.endTime.substring(11)}`)
                        .fontSize(12)
                        .fontColor(this.store.colors.textTertiary)
                      Text(rec.status === 'BOOKING' ? '预约生效中' : '已取消')
                        .fontSize(12)
                        .fontColor(rec.status === 'BOOKING' ? this.store.colors.success : this.store.colors.textMuted)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (rec.status === 'BOOKING') {
                      Button('取消')
                        .height(32)
                        .fontSize(12)
                        .fontColor(this.store.colors.onDanger)
                        .backgroundColor(this.store.colors.danger)
                        .borderRadius(10)
                        .padding({ left: 12, right: 12 })
                        .onClick(() => {
                          this.store.cancelLibraryBooking(rec.id);
                        })
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(14)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                }
              }, (rec: ShuYoLibraryBookingRecord, idx: number): string => `${rec.id}-${rec.status}-${idx}`)
            }
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 20 })
          }
        } else {
          Scroll() {
            Column({ space: 14 }) {
              Column({ space: 8 }) {
                Text('场馆楼层示意图')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)
                Image($rawfile('library_booking/lib_map.jpg'))
                  .width('100%')
                  .height(190)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(12)
                Image($rawfile('library_booking/seats.jpg'))
                  .width('100%')
                  .height(190)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(12)
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 8 }) {
                Text('预约规则说明')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)
                Text(LibraryBookingService.getRulesMarkdown())
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(this.store.colors.textSecondary)
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 8 }) {
                Text('常见问题 Q&A')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)
                Text(LibraryBookingService.getQaMarkdown())
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(this.store.colors.textSecondary)
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 })
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
    })
  }
}
