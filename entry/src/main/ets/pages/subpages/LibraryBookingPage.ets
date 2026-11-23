import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../../models/ShuYoModels';
import { LibraryBookingService } from '../../services/LibraryBookingService';
import { LibraryFloorPlanView } from '../../components/LibraryFloorPlanView';
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
  @Local activeTabMode: number = 0; // 0: 平面图选座, 1: 我的预约, 2: 说明与规则
  @Local displayMode: number = 0; // 0: 交互平面图, 1: 座位列表
  @Local selectedDay: string = LibraryBookingService.todayDateStr();
  @Local selectedStartTime: string = '09:00';
  @Local selectedEndTime: string = '12:00';
  @Local onlyShowAvailable: boolean = false;
  @Local areas: ShuYoLibraryArea[] = [];
  @Local isLiveMode: boolean = false;
  @Local dataStatusText: string = '正在加载座位分布...';
  @Local isLoadingSeats: boolean = false;
  @Local isSubmittingBooking: boolean = false;
  @Local selectedSeatId: string = '';
  @Local selectedSeatZoneHint: string = '';
  @Local showFullScreenMapSheet: boolean = false;
  @Local floorRevision: number = 0;

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private loadGeneration: number = 0;
  private readonly todayStr: string = LibraryBookingService.todayDateStr();
  private readonly tomorrowStr: string = LibraryBookingService.tomorrowDateStr();

  aboutToAppear(): void {
    this.reloadSeatAvailability();
  }

  private getCurrentVenue(): ShuYoLibraryVenue {
    const idx = Math.max(0, Math.min(this.selectedVenueIdx, LibraryBookingService.venues.length - 1));
    return LibraryBookingService.venues[idx];
  }

  private getCurrentArea(): ShuYoLibraryArea | undefined {
    if (this.areas.length === 0) {
      return undefined;
    }
    const idx = Math.max(0, Math.min(this.selectedAreaIdx, this.areas.length - 1));
    return this.areas[idx];
  }

  private findSelectedSeat(): ShuYoLibrarySeat | undefined {
    if (this.selectedSeatId.length === 0) {
      return undefined;
    }
    const area = this.getCurrentArea();
    if (area === undefined) {
      return undefined;
    }
    for (let i = 0; i < area.seats.length; i++) {
      if (area.seats[i].id === this.selectedSeatId) {
        return area.seats[i];
      }
    }
    return undefined;
  }

  private async reloadSeatAvailability(): Promise<void> {
    const gen = ++this.loadGeneration;
    this.isLoadingSeats = true;
    const venue = this.getCurrentVenue();
    const res = await LibraryBookingService.fetchAreasAndSeatsForSlot(
      venue,
      this.selectedAreaIdx,
      this.selectedDay,
      this.selectedStartTime,
      this.selectedEndTime,
      this.store.libraryBookings,
      this.store.isDemoMode,
      this.store.useWebVpn
    );
    if (gen !== this.loadGeneration) {
      return;
    }
    this.areas = res.areas;
    if (this.areas.length > 0 && this.selectedAreaIdx >= this.areas.length) {
      this.selectedAreaIdx = 0;
    }
    this.isLiveMode = res.isLive;
    this.dataStatusText = res.statusText;
    this.isLoadingSeats = false;
    this.floorRevision++;
  }

  private applyPresetSlot(start: string, end: string): void {
    if (this.selectedStartTime === start && this.selectedEndTime === end) {
      return;
    }
    this.selectedStartTime = start;
    this.selectedEndTime = end;
    this.selectedSeatId = '';
    this.selectedSeatZoneHint = '';
    this.reloadSeatAvailability();
  }

  private stepStartTime(delta: number): void {
    const opts = LibraryBookingService.timeOptions;
    const curStartIdx = opts.indexOf(this.selectedStartTime);
    const curEndIdx = opts.indexOf(this.selectedEndTime);
    const baseStart = curStartIdx >= 0 ? curStartIdx : 2;
    const nextStart = Math.max(0, Math.min(opts.length - 2, baseStart + delta));
    const minEnd = Math.min(opts.length - 1, nextStart + 1);
    const nextEnd = curEndIdx >= minEnd ? curEndIdx : Math.min(opts.length - 1, nextStart + 2);
    this.selectedStartTime = opts[nextStart];
    this.selectedEndTime = opts[nextEnd];
    this.selectedSeatId = '';
    this.selectedSeatZoneHint = '';
    this.reloadSeatAvailability();
  }

  private stepEndTime(delta: number): void {
    const opts = LibraryBookingService.timeOptions;
    const curStartIdx = Math.max(0, opts.indexOf(this.selectedStartTime));
    const curEndIdx = opts.indexOf(this.selectedEndTime);
    const baseEnd = curEndIdx >= 0 ? curEndIdx : curStartIdx + 2;
    const nextEnd = Math.max(curStartIdx + 1, Math.min(opts.length - 1, baseEnd + delta));
    this.selectedEndTime = opts[nextEnd];
    this.selectedSeatId = '';
    this.selectedSeatZoneHint = '';
    this.reloadSeatAvailability();
  }

  private handleSeatSelected(seat: ShuYoLibrarySeat, zoneHint: string): void {
    if (this.selectedSeatId === seat.id) {
      this.selectedSeatId = '';
      this.selectedSeatZoneHint = '';
    } else {
      this.selectedSeatId = seat.id;
      this.selectedSeatZoneHint = zoneHint;
    }
    this.floorRevision++;
  }

  private getTabBg(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getTabText(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getDisplayedListSeats(area: ShuYoLibraryArea): ShuYoLibrarySeat[] {
    if (!this.onlyShowAvailable) {
      return area.seats;
    }
    const out: ShuYoLibrarySeat[] = [];
    for (let i = 0; i < area.seats.length; i++) {
      const s = area.seats[i];
      if (!s.isDisabled && !s.isBusy && !s.isBooked) {
        out.push(s);
      }
    }
    return out;
  }

  private getSeatCardBg(seat: ShuYoLibrarySeat): string {
    if (seat.isDisabled) {
      return this.store.colors.disabledFill;
    }
    if (seat.isBooked) {
      return '#DBEAFE';
    }
    if (seat.isBusy) {
      return '#FEE2E2';
    }
    return '#DCFCE7';
  }

  private getSeatCardBorder(seat: ShuYoLibrarySeat): string {
    if (seat.id === this.selectedSeatId && this.selectedSeatId.length > 0) {
      return '#1D4ED8';
    }
    if (seat.isDisabled) {
      return this.store.colors.border;
    }
    if (seat.isBooked) {
      return '#2563EB';
    }
    if (seat.isBusy) {
      return '#DC2626';
    }
    return '#16A34A';
  }

  private getSeatCardText(seat: ShuYoLibrarySeat): string {
    if (seat.isDisabled) {
      return this.store.colors.textMuted;
    }
    if (seat.isBooked) {
      return '#1D4ED8';
    }
    if (seat.isBusy) {
      return '#B91C1C';
    }
    return '#15803D';
  }

  private getSeatStatusLabel(seat: ShuYoLibrarySeat): string {
    if (seat.isDisabled) {
      return '停用维护';
    }
    if (seat.isBooked) {
      return '我的预约';
    }
    if (seat.isBusy) {
      return '该时段已占用';
    }
    return '该时段空闲 · 可预约';
  }

  private isSeatBookable(seat: ShuYoLibrarySeat): boolean {
    return !seat.isDisabled && !seat.isBusy && !seat.isBooked;
  }

  private async confirmBookSelectedSeat(): Promise<void> {
    const area = this.getCurrentArea();
    const seat = this.findSelectedSeat();
    if (area === undefined || seat === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在平面图中选择一个座位' });
      return;
    }
    if (!this.isSeatBookable(seat)) {
      this.getUIContext().getPromptAction().showToast({ message: this.getSeatStatusLabel(seat) });
      return;
    }
    if (!LibraryBookingService.isValidTimeSlot(this.selectedStartTime, this.selectedEndTime)) {
      this.getUIContext().getPromptAction().showToast({ message: '结束时间需晚于开始时间' });
      return;
    }
    if (this.isSubmittingBooking) {
      return;
    }
    this.isSubmittingBooking = true;
    try {
      const res = await LibraryBookingService.createBooking(
        this.getCurrentVenue(),
        area,
        seat,
        this.selectedDay,
        this.selectedStartTime,
        this.selectedEndTime,
        this.isLiveMode,
        this.store.useWebVpn
      );
      this.getUIContext().getPromptAction().showToast({ message: res.message });
      if (res.ok && res.record !== undefined) {
        this.store.addLibraryBooking(res.record);
        this.showFullScreenMapSheet = false;
        await this.reloadSeatAvailability();
      }
    } finally {
      this.isSubmittingBooking = false;
    }
  }

  private getOccupiedCount(area: ShuYoLibraryArea): number {
    let busy = 0;
    for (let i = 0; i < area.seats.length; i++) {
      const s = area.seats[i];
      if (!s.isDisabled && (s.isBusy || s.isBooked)) {
        busy++;
      }
    }
    return busy;
  }

  @Builder
  private fullScreenMapSheetBuilder() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text(`${this.getCurrentVenue().name} · ${this.getCurrentArea()?.name ?? ''}`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)
          Text(`${this.selectedDay} ${this.selectedStartTime}-${this.selectedEndTime} · 绿=空闲 / 红=占用`)
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.getCurrentArea() !== undefined) {
        LibraryFloorPlanView({
          venueId: this.getCurrentVenue().id,
          areaName: this.getCurrentArea()!.name,
          seats: this.getCurrentArea()!.seats,
          selectedSeatId: this.selectedSeatId,
          onlyShowAvailable: this.onlyShowAvailable,
          dataRevision: this.floorRevision,
          isFullScreen: true,
          onSeatTap: (seat: ShuYoLibrarySeat, zoneHint: string) => {
            this.handleSeatSelected(seat, zoneHint);
          },
          onRequestFullScreen: () => {}
        })
      }

      if (this.findSelectedSeat() !== undefined) {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(`座位 ${this.findSelectedSeat()!.seatLabel}${this.selectedSeatZoneHint.length > 0 ? ' · ' + this.selectedSeatZoneHint : ''}`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)
            Text(this.getSeatStatusLabel(this.findSelectedSeat()!))
              .fontSize(12)
              .fontColor(this.getSeatCardText(this.findSelectedSeat()!))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.isSubmittingBooking ? '提交中...' : '预约此座')
            .height(36)
            .fontSize(13)
            .enabled(this.isSeatBookable(this.findSelectedSeat()!) && !this.isSubmittingBooking)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(
              this.isSeatBookable(this.findSelectedSeat()!)
                ? '#16A34A'
                : this.store.colors.disabledFill
            )
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.confirmBookSelectedSeat();
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(this.store.colors.surfaceAlt)
        .border({ width: 1, color: this.store.colors.border })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .backgroundColor(this.store.colors.surface)
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '图书馆预约',
          subtitleText: '先选时段，在平面图查看绿/红空位',
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
          Button('选座平面图')
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
          Button('说明与规则')
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
                        if (this.selectedVenueIdx !== idx) {
                          this.selectedVenueIdx = idx;
                          this.selectedAreaIdx = 0;
                          this.selectedSeatId = '';
                          this.selectedSeatZoneHint = '';
                          this.reloadSeatAvailability();
                        }
                      })
                  }, (v: ShuYoLibraryVenue): string => `ven-${v.id}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(36)

              // Date & Time Slot Picker Card
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  Text('预约日期')
                    .fontSize(12)
                    .fontColor(this.store.colors.textSecondary)
                  Button(`今天 (${this.todayStr.substring(5)})`)
                    .height(26)
                    .fontSize(11)
                    .fontColor(this.selectedDay === this.todayStr ? this.store.colors.onSelectedFill : this.store.colors.textSecondary)
                    .backgroundColor(this.selectedDay === this.todayStr ? this.store.colors.selectedFill : this.store.colors.chipFill)
                    .borderRadius(13)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      if (this.selectedDay !== this.todayStr) {
                        this.selectedDay = this.todayStr;
                        this.selectedSeatId = '';
                        this.reloadSeatAvailability();
                      }
                    })
                  Button(`明天 (${this.tomorrowStr.substring(5)})`)
                    .height(26)
                    .fontSize(11)
                    .fontColor(this.selectedDay === this.tomorrowStr ? this.store.colors.onSelectedFill : this.store.colors.textSecondary)
                    .backgroundColor(this.selectedDay === this.tomorrowStr ? this.store.colors.selectedFill : this.store.colors.chipFill)
                    .borderRadius(13)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      if (this.selectedDay !== this.tomorrowStr) {
                        this.selectedDay = this.tomorrowStr;
                        this.selectedSeatId = '';
                        this.reloadSeatAvailability();
                      }
                    })
                  Blank()
                  if (this.isLoadingSeats) {
                    LoadingProgress().width(16).height(16).color(this.store.colors.accent)
                  }
                }
                .width('100%')

                // Quick time slot chips
                Scroll() {
                  Row({ space: 6 }) {
                    Button('08:00-11:00')
                      .height(28)
                      .fontSize(11)
                      .fontColor(
                        this.selectedStartTime === '08:00' && this.selectedEndTime === '11:00'
                          ? this.store.colors.onAccent
                          : this.store.colors.textPrimary
                      )
                      .backgroundColor(
                        this.selectedStartTime === '08:00' && this.selectedEndTime === '11:00'
                          ? this.store.colors.accent
                          : this.store.colors.surfaceAlt
                      )
                      .borderRadius(10)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.applyPresetSlot('08:00', '11:00');
                      })

                    Button('09:00-12:00')
                      .height(28)
                      .fontSize(11)
                      .fontColor(
                        this.selectedStartTime === '09:00' && this.selectedEndTime === '12:00'
                          ? this.store.colors.onAccent
                          : this.store.colors.textPrimary
                      )
                      .backgroundColor(
                        this.selectedStartTime === '09:00' && this.selectedEndTime === '12:00'
                          ? this.store.colors.accent
                          : this.store.colors.surfaceAlt
                      )
                      .borderRadius(10)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.applyPresetSlot('09:00', '12:00');
                      })

                    Button('14:00-17:00')
                      .height(28)
                      .fontSize(11)
                      .fontColor(
                        this.selectedStartTime === '14:00' && this.selectedEndTime === '17:00'
                          ? this.store.colors.onAccent
                          : this.store.colors.textPrimary
                      )
                      .backgroundColor(
                        this.selectedStartTime === '14:00' && this.selectedEndTime === '17:00'
                          ? this.store.colors.accent
                          : this.store.colors.surfaceAlt
                      )
                      .borderRadius(10)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.applyPresetSlot('14:00', '17:00');
                      })

                    Button('18:00-21:30')
                      .height(28)
                      .fontSize(11)
                      .fontColor(
                        this.selectedStartTime === '18:00' && this.selectedEndTime === '21:30'
                          ? this.store.colors.onAccent
                          : this.store.colors.textPrimary
                      )
                      .backgroundColor(
                        this.selectedStartTime === '18:00' && this.selectedEndTime === '21:30'
                          ? this.store.colors.accent
                          : this.store.colors.surfaceAlt
                      )
                      .borderRadius(10)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.applyPresetSlot('18:00', '21:30');
                      })
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')

                // Fine 30-min start/end steppers
                Row({ space: 6 }) {
                  Text('开始')
                    .fontSize(11)
                    .fontColor(this.store.colors.textTertiary)
                  Button('-')
                    .width(24)
                    .height(24)
                    .padding(0)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .borderRadius(8)
                    .onClick(() => {
                      this.stepStartTime(-1);
                    })
                  Text(this.selectedStartTime)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.accent)
                  Button('+')
                    .width(24)
                    .height(24)
                    .padding(0)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .borderRadius(8)
                    .onClick(() => {
                      this.stepStartTime(1);
                    })

                  Text('→')
                    .fontSize(12)
                    .fontColor(this.store.colors.textMuted)

                  Text('结束')
                    .fontSize(11)
                    .fontColor(this.store.colors.textTertiary)
                  Button('-')
                    .width(24)
                    .height(24)
                    .padding(0)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .borderRadius(8)
                    .onClick(() => {
                      this.stepEndTime(-1);
                    })
                  Text(this.selectedEndTime)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.accent)
                  Button('+')
                    .width(24)
                    .height(24)
                    .padding(0)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .borderRadius(8)
                    .onClick(() => {
                      this.stepEndTime(1);
                    })
                }
                .width('100%')

                Row({ space: 8 }) {
                  Text(this.dataStatusText)
                    .fontSize(11)
                    .fontColor(this.isLiveMode ? '#16A34A' : this.store.colors.textTertiary)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button('刷新空位')
                    .height(24)
                    .fontSize(11)
                    .fontColor(this.store.colors.accent)
                    .backgroundColor(this.store.colors.accentSoft)
                    .borderRadius(12)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.reloadSeatAvailability();
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })

              // Areas + View Switcher
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.areas, (area: ShuYoLibraryArea, aIdx: number) => {
                    Button(`${area.name} (空${area.freeCount}/${area.totalCount})`)
                      .height(30)
                      .fontSize(12)
                      .fontColor(this.selectedAreaIdx === aIdx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary)
                      .backgroundColor(this.selectedAreaIdx === aIdx ? this.store.colors.selectedFill : this.store.colors.chipFill)
                      .borderRadius(14)
                      .padding({ left: 12, right: 12 })
                      .onClick(() => {
                        if (this.selectedAreaIdx !== aIdx) {
                          this.selectedAreaIdx = aIdx;
                          this.selectedSeatId = '';
                          this.selectedSeatZoneHint = '';
                          this.reloadSeatAvailability();
                        }
                      })
                  }, (area: ShuYoLibraryArea): string => `area-${area.id}-${area.freeCount}-${this.floorRevision}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')

              // Floor Plan / List Card
              if (this.getCurrentArea() !== undefined) {
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(`${this.getCurrentArea()!.name} 座位空闲情况`)
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.textPrimary)
                      Text(`空闲 ${this.getCurrentArea()!.freeCount} 个 · 占用 ${this.getOccupiedCount(this.getCurrentArea()!)} 个`)
                        .fontSize(11)
                        .fontColor(this.store.colors.textTertiary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button('平面图')
                      .height(26)
                      .fontSize(11)
                      .fontColor(this.displayMode === 0 ? this.store.colors.onAccent : this.store.colors.textSecondary)
                      .backgroundColor(this.displayMode === 0 ? this.store.colors.accent : this.store.colors.chipFill)
                      .borderRadius(13)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.displayMode = 0;
                      })

                    Button('列表')
                      .height(26)
                      .fontSize(11)
                      .fontColor(this.displayMode === 1 ? this.store.colors.onAccent : this.store.colors.textSecondary)
                      .backgroundColor(this.displayMode === 1 ? this.store.colors.accent : this.store.colors.chipFill)
                      .borderRadius(13)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.displayMode = 1;
                      })
                  }
                  .width('100%')

                  Row({ space: 8 }) {
                    Text('仅高亮空闲座位')
                      .fontSize(12)
                      .fontColor(this.store.colors.textSecondary)
                    Blank()
                    Toggle({ type: ToggleType.Switch, isOn: this.onlyShowAvailable })
                      .selectedColor('#16A34A')
                      .onChange((val: boolean) => {
                        this.onlyShowAvailable = val;
                        this.floorRevision++;
                      })
                  }
                  .width('100%')

                  if (this.displayMode === 0) {
                    LibraryFloorPlanView({
                      venueId: this.getCurrentVenue().id,
                      areaName: this.getCurrentArea()!.name,
                      seats: this.getCurrentArea()!.seats,
                      selectedSeatId: this.selectedSeatId,
                      onlyShowAvailable: this.onlyShowAvailable,
                      dataRevision: this.floorRevision,
                      isFullScreen: false,
                      onSeatTap: (seat: ShuYoLibrarySeat, zoneHint: string) => {
                        this.handleSeatSelected(seat, zoneHint);
                      },
                      onRequestFullScreen: () => {
                        this.showFullScreenMapSheet = true;
                      }
                    })
                  } else {
                    Column({ space: 8 }) {
                      Row({ space: 12 }) {
                        Text('● 空闲(绿)')
                          .fontSize(11)
                          .fontColor('#16A34A')
                        Text('● 占用(红)')
                          .fontSize(11)
                          .fontColor('#DC2626')
                        Text('● 我的预约(蓝)')
                          .fontSize(11)
                          .fontColor('#2563EB')
                        Text('● 停用(灰)')
                          .fontSize(11)
                          .fontColor(this.store.colors.textMuted)
                      }
                      .width('100%')

                      Grid() {
                        ForEach(this.getDisplayedListSeats(this.getCurrentArea()!), (seat: ShuYoLibrarySeat) => {
                          GridItem() {
                            Column({ space: 2 }) {
                              Text(seat.seatLabel)
                                .fontSize(12)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.getSeatCardText(seat))
                              Text(seat.isDisabled ? '停用' : (seat.isBooked ? '已约' : (seat.isBusy ? '占用' : '空闲')))
                                .fontSize(10)
                                .fontColor(this.getSeatCardText(seat))
                            }
                            .width('100%')
                            .height(50)
                            .borderRadius(10)
                            .backgroundColor(this.getSeatCardBg(seat))
                            .border({
                              width: seat.id === this.selectedSeatId ? 2 : 1,
                              color: this.getSeatCardBorder(seat)
                            })
                            .justifyContent(FlexAlign.Center)
                            .onClick(() => {
                              this.handleSeatSelected(seat, `${this.getCurrentArea()!.name} ${seat.seatLabel}号`);
                            })
                          }
                        }, (seat: ShuYoLibrarySeat): string => `${seat.id}-${seat.isBusy}-${seat.isBooked}-${this.floorRevision}`)
                      }
                      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
                      .columnsGap(8)
                      .rowsGap(8)
                      .width('100%')
                      .height(
                        Math.min(
                          320,
                          Math.max(110, Math.ceil(this.getDisplayedListSeats(this.getCurrentArea()!).length / 5) * 58)
                        )
                      )
                      .nestedScroll({
                        scrollForward: NestedScrollMode.PARENT_FIRST,
                        scrollBackward: NestedScrollMode.SELF_FIRST
                      })
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })
              }

              // Selected seat confirmation card
              if (this.findSelectedSeat() !== undefined) {
                Column({ space: 10 }) {
                  Row({ space: 10 }) {
                    Column()
                      .width(12)
                      .height(12)
                      .borderRadius(6)
                      .backgroundColor(
                        this.isSeatBookable(this.findSelectedSeat()!)
                          ? '#16A34A'
                          : (this.findSelectedSeat()!.isBooked ? '#2563EB' : '#DC2626')
                      )
                    Column({ space: 2 }) {
                      Text(`${this.getCurrentVenue().name} · ${this.findSelectedSeat()!.seatLabel}`)
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.textPrimary)
                      Text(this.selectedSeatZoneHint.length > 0
                        ? `${this.selectedSeatZoneHint} · ${this.selectedDay} ${this.selectedStartTime}-${this.selectedEndTime}`
                        : `${this.selectedDay} ${this.selectedStartTime}-${this.selectedEndTime}`)
                        .fontSize(12)
                        .fontColor(this.store.colors.textTertiary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(this.getSeatStatusLabel(this.findSelectedSeat()!))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.getSeatCardText(this.findSelectedSeat()!))
                  }
                  .width('100%')

                  Button(this.isSubmittingBooking
                    ? '正在提交预约...'
                    : (this.isSeatBookable(this.findSelectedSeat()!) ? '确认预约该座位' : '该座位当前不可预约'))
                    .width('100%')
                    .height(42)
                    .fontSize(14)
                    .enabled(this.isSeatBookable(this.findSelectedSeat()!) && !this.isSubmittingBooking)
                    .fontColor(this.store.colors.onAccent)
                    .backgroundColor(
                      this.isSeatBookable(this.findSelectedSeat()!)
                        ? '#16A34A'
                        : this.store.colors.disabledFill
                    )
                    .borderRadius(12)
                    .onClick(() => {
                      this.confirmBookSelectedSeat();
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1.5, color: this.getSeatCardBorder(this.findSelectedSeat()!) })
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
              emptyHint: '切换到“选座平面图”页面，选好时段后点击绿色空闲座位即可预约',
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
                        .fontColor(rec.status === 'BOOKING' ? '#16A34A' : this.store.colors.textMuted)
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
                          this.reloadSeatAvailability();
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
                Row() {
                  Text('场馆楼层示意图')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                    .layoutWeight(1)
                  Button('查看时段空位平面图')
                    .height(28)
                    .fontSize(11)
                    .fontColor(this.store.colors.onAccent)
                    .backgroundColor(this.store.colors.accent)
                    .borderRadius(14)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.activeTabMode = 0;
                      this.displayMode = 0;
                    })
                }
                .width('100%')

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
      .bindSheet($$this.showFullScreenMapSheet, this.fullScreenMapSheetBuilder(), {
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
