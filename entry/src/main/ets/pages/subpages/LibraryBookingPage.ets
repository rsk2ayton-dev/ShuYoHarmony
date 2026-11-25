import { ShuYoGlass } from '../../core/ShuYoMotionGlass';
import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../../models/ShuYoModels';
import { LibraryBookingService, ShuYoThereFailure } from '../../services/LibraryBookingService';
import {
  LibraryFloorPlanLayout,
  ShuYoFloorPlanPoint
} from '../../services/LibraryFloorPlanLayout';
import { LibraryFloorPlanView, LibrarySeatTicketCard } from '../../components/LibraryFloorPlanView';
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
  @Local selectedAreaIdx: number = -1; // -1 = 全馆总览 (studySpace only), >=0 = specific zone
  @Local activeTabMode: number = 0; // 0: 平面图选座, 1: 我的预约, 2: 说明与规则
  @Local displayMode: number = 0; // 0: 交互平面图, 1: 座位列表
  @Local selectedDay: string = LibraryBookingService.todayDateStr();
  @Local selectedStartTime: string = '09:00';
  @Local selectedEndTime: string = '12:00';
  @Local filterMode: number = 0; // 0: 全部, 1: 仅空闲, 2: 清静位(邻座皆空)
  @Local areas: ShuYoLibraryArea[] = [];
  @Local activeArea: ShuYoLibraryArea | undefined = undefined;
  @Local areaPoints: ShuYoFloorPlanPoint[] = [];
  @Local pointMap: Map<string, ShuYoFloorPlanPoint> = new Map<string, ShuYoFloorPlanPoint>();
  @Local quietCount: number = 0;
  @Local isLiveMode: boolean = false;
  @Local slotFailure: ShuYoThereFailure = ShuYoThereFailure.NONE;
  @Local dataStatusText: string = '正在加载座位分布...';
  @Local isLoadingSeats: boolean = false;
  @Local isSubmittingBooking: boolean = false;
  @Local cancellingBookingId: string = '';
  @Local selectedSeatId: string = '';
  @Local selectedPoint: ShuYoFloorPlanPoint | undefined = undefined;
  @Local showFullScreenMapSheet: boolean = false;
  @Local floorRevision: number = 0;

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private loadGeneration: number = 0;
  private readonly todayStr: string = LibraryBookingService.todayDateStr();
  private readonly tomorrowStr: string = LibraryBookingService.tomorrowDateStr();

  aboutToAppear(): void {
    this.selectedAreaIdx = this.getCurrentVenue().id === 'studySpace' ? -1 : 0;
    this.reloadSeatAvailability();
  }

  private getCurrentVenue(): ShuYoLibraryVenue {
    const idx = Math.max(0, Math.min(this.selectedVenueIdx, LibraryBookingService.venues.length - 1));
    return LibraryBookingService.venues[idx];
  }

  private getCurrentArea(): ShuYoLibraryArea | undefined {
    if (this.activeArea !== undefined) {
      return this.activeArea;
    }
    if (this.areas.length === 0) {
      return undefined;
    }
    const idx = Math.max(0, Math.min(this.selectedAreaIdx, this.areas.length - 1));
    return this.areas[idx];
  }

  private isOverviewAvailable(): boolean {
    return this.getCurrentVenue().id === 'studySpace';
  }

  private getOverviewSummaryLabel(): string {
    let freeSum = 0;
    let totalSum = 0;
    for (let i = 0; i < this.areas.length; i++) {
      freeSum += this.areas[i].freeCount;
      totalSum += this.areas[i].totalCount;
    }
    if (totalSum <= 0 && this.activeArea !== undefined) {
      freeSum = this.activeArea.freeCount;
      totalSum = this.activeArea.totalCount;
    }
    return totalSum > 0 ? `全馆总览 (空${freeSum}/${totalSum})` : '全馆总览 (A+B+C)';
  }

  private resolveBookingAreaForSeat(seat: ShuYoLibrarySeat): ShuYoLibraryArea | undefined {
    for (let i = 0; i < this.areas.length; i++) {
      if (this.areas[i].id === seat.areaId) {
        return this.areas[i];
      }
    }
    return this.getCurrentArea();
  }

  private findSelectedSeat(): ShuYoLibrarySeat | undefined {
    if (this.selectedPoint !== undefined) {
      return this.selectedPoint.seat;
    }
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

  private rebuildAreaPoints(): void {
    const area = this.getCurrentArea();
    if (area === undefined) {
      this.areaPoints = [];
      this.pointMap = new Map<string, ShuYoFloorPlanPoint>();
      this.quietCount = 0;
      return;
    }
    const pts = LibraryFloorPlanLayout.buildFloorPlanPoints(
      this.getCurrentVenue().id,
      area.name,
      area.seats
    );
    const map = new Map<string, ShuYoFloorPlanPoint>();
    let quiet = 0;
    for (let i = 0; i < pts.length; i++) {
      const pt = pts[i];
      map.set(pt.seat.id, pt);
      if (pt.isQuiet) {
        quiet++;
      }
    }
    this.areaPoints = pts;
    this.pointMap = map;
    this.quietCount = quiet;
    if (this.selectedSeatId.length > 0) {
      const refreshed = map.get(this.selectedSeatId);
      if (refreshed !== undefined) {
        this.selectedPoint = refreshed;
      } else {
        this.selectedSeatId = '';
        this.selectedPoint = undefined;
      }
    }
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
    if (venue.id !== 'studySpace' && this.selectedAreaIdx < 0) {
      this.selectedAreaIdx = 0;
    }
    if (this.areas.length > 0 && this.selectedAreaIdx >= this.areas.length) {
      this.selectedAreaIdx = 0;
    }
    this.activeArea = res.activeArea;
    this.isLiveMode = res.isLive;
    this.slotFailure = res.failure !== undefined ? res.failure : ShuYoThereFailure.NONE;
    this.dataStatusText = res.statusText;
    this.rebuildAreaPoints();
    this.isLoadingSeats = false;
    this.floorRevision++;
  }

  private clearSelection(): void {
    this.selectedSeatId = '';
    this.selectedPoint = undefined;
  }

  private applyPresetSlot(start: string, end: string): void {
    if (this.selectedStartTime === start && this.selectedEndTime === end) {
      return;
    }
    this.selectedStartTime = start;
    this.selectedEndTime = end;
    this.clearSelection();
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
    this.clearSelection();
    this.reloadSeatAvailability();
  }

  private stepEndTime(delta: number): void {
    const opts = LibraryBookingService.timeOptions;
    const curStartIdx = Math.max(0, opts.indexOf(this.selectedStartTime));
    const curEndIdx = opts.indexOf(this.selectedEndTime);
    const baseEnd = curEndIdx >= 0 ? curEndIdx : curStartIdx + 2;
    const nextEnd = Math.max(curStartIdx + 1, Math.min(opts.length - 1, baseEnd + delta));
    this.selectedEndTime = opts[nextEnd];
    this.clearSelection();
    this.reloadSeatAvailability();
  }

  private handlePointSelected(pt: ShuYoFloorPlanPoint): void {
    if (this.selectedSeatId === pt.seat.id) {
      this.clearSelection();
    } else {
      this.selectedSeatId = pt.seat.id;
      this.selectedPoint = pt;
    }
    this.floorRevision++;
  }

  private handleSeatSelectedFromList(seat: ShuYoLibrarySeat): void {
    const existing = this.pointMap.get(seat.id);
    if (existing !== undefined) {
      this.handlePointSelected(existing);
      return;
    }
    const fallbackPt: ShuYoFloorPlanPoint = {
      seat: seat,
      normalizedCode: seat.seatLabel,
      nx: 0.5,
      ny: 0.5,
      facingDeg: -90,
      zoneHint: `${this.getCurrentArea()?.name ?? ''} ${seat.seatLabel}号`,
      isQuiet: LibraryFloorPlanLayout.isSeatFree(seat),
      isRealFloorPlan: false
    };
    this.handlePointSelected(fallbackPt);
  }

  private getTabBg(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getTabText(idx: number): string {
    return this.activeTabMode === idx ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getFilterBg(mode: number): string {
    if (this.filterMode !== mode) {
      return this.store.colors.chipFill;
    }
    return mode === 2 ? '#059669' : (mode === 1 ? '#16A34A' : this.store.colors.selectedFill);
  }

  private getFilterText(mode: number): string {
    if (this.filterMode !== mode) {
      return this.store.colors.textSecondary;
    }
    return mode === 0 ? this.store.colors.onSelectedFill : '#FFFFFF';
  }

  private getDisplayedListPoints(): ShuYoFloorPlanPoint[] {
    if (this.filterMode === 0) {
      return this.areaPoints;
    }
    const out: ShuYoFloorPlanPoint[] = [];
    for (let i = 0; i < this.areaPoints.length; i++) {
      const pt = this.areaPoints[i];
      if (this.filterMode === 1 && LibraryFloorPlanLayout.isSeatFree(pt.seat)) {
        out.push(pt);
      } else if (this.filterMode === 2 && pt.isQuiet) {
        out.push(pt);
      }
    }
    return out;
  }

  private getSeatCardBg(pt: ShuYoFloorPlanPoint): string {
    const seat = pt.seat;
    if (seat.isDisabled) {
      return this.store.colors.disabledFill;
    }
    if (seat.isBooked) {
      return '#DBEAFE';
    }
    if (seat.isBusy) {
      return '#FEE2E2';
    }
    return pt.isQuiet ? '#D1FAE5' : '#DCFCE7';
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
    const seat = this.findSelectedSeat();
    if (seat === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在平面图中选择一个座位' });
      return;
    }
    const targetArea = this.resolveBookingAreaForSeat(seat);
    if (targetArea === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '未定位到该座位所属分区，请刷新后重试' });
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
        targetArea,
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

  private async cancelBookingRecord(rec: ShuYoLibraryBookingRecord): Promise<void> {
    if (this.cancellingBookingId.length > 0) {
      return;
    }
    this.cancellingBookingId = rec.id;
    try {
      const isLiveRecord = !this.store.isDemoMode && !rec.id.startsWith('bk-');
      const res = await LibraryBookingService.cancelBooking(rec, isLiveRecord, this.store.useWebVpn);
      this.getUIContext().getPromptAction().showToast({ message: res.message });
      if (res.ok) {
        this.store.cancelLibraryBooking(rec.id);
        await this.reloadSeatAvailability();
      }
    } finally {
      this.cancellingBookingId = '';
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
          Text(`${this.selectedDay} ${this.selectedStartTime}-${this.selectedEndTime} · 空${this.getCurrentArea()?.freeCount ?? 0} / 清静${this.quietCount}`)
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      // Filter strip in full-screen sheet too
      Row({ space: 6 }) {
        Button('全部')
          .height(28)
          .fontSize(11)
          .fontColor(this.getFilterText(0))
          .backgroundColor(this.getFilterBg(0))
          .borderRadius(12)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.filterMode = 0;
            this.floorRevision++;
          })
        Button('仅空闲')
          .height(28)
          .fontSize(11)
          .fontColor(this.getFilterText(1))
          .backgroundColor(this.getFilterBg(1))
          .borderRadius(12)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.filterMode = 1;
            this.floorRevision++;
          })
        Button(`✨ 清静位 (${this.quietCount})`)
          .height(28)
          .fontSize(11)
          .fontColor(this.getFilterText(2))
          .backgroundColor(this.getFilterBg(2))
          .borderRadius(12)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.filterMode = 2;
            this.floorRevision++;
          })
      }
      .width('100%')

      if (this.getCurrentArea() !== undefined) {
        LibraryFloorPlanView({
          venueId: this.getCurrentVenue().id,
          areaName: this.getCurrentArea()!.name,
          seats: this.getCurrentArea()!.seats,
          selectedSeatId: this.selectedSeatId,
          filterMode: this.filterMode,
          dataRevision: this.floorRevision,
          isFullScreen: true,
          onSeatDetailTap: (pt: ShuYoFloorPlanPoint) => {
            this.handlePointSelected(pt);
          },
          onRequestFullScreen: () => {}
        })
      }

      if (this.selectedPoint !== undefined) {
        LibrarySeatTicketCard({
          point: this.selectedPoint,
          selectedDay: this.selectedDay,
          selectedStartTime: this.selectedStartTime,
          selectedEndTime: this.selectedEndTime,
          isSubmitting: this.isSubmittingBooking,
          compact: true,
          onBookTap: () => {
            this.confirmBookSelectedSeat();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .backgroundColor(Color.Transparent)
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '图书馆预约',
          subtitleText: '先选时段，在平面图查看绿/红空位与清静邻座',
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
              // Venues (all 7 SHU venues)
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
                          this.selectedAreaIdx = v.id === 'studySpace' ? -1 : 0;
                          this.clearSelection();
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
                        this.clearSelection();
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
                        this.clearSelection();
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
                  Text('−')
                    .width(28)
                    .height(28)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .textAlign(TextAlign.Center)
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
                  Text('+')
                    .width(28)
                    .height(28)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .textAlign(TextAlign.Center)
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
                  Text('−')
                    .width(28)
                    .height(28)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .textAlign(TextAlign.Center)
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
                  Text('+')
                    .width(28)
                    .height(28)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .textAlign(TextAlign.Center)
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
                    .fontColor(this.isLiveMode
                      ? '#16A34A'
                      : (this.slotFailure === ShuYoThereFailure.NONE
                        ? this.store.colors.textTertiary
                        : this.store.colors.danger))
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.slotFailure === ShuYoThereFailure.WEBVPN_EXPIRED) {
                    Button('关 WebVPN')
                      .height(24)
                      .fontSize(11)
                      .fontColor(this.store.colors.onDanger)
                      .backgroundColor(this.store.colors.danger)
                      .borderRadius(12)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.store.setUseWebVpn(false);
                        this.reloadSeatAvailability();
                      })
                  }
                  if (!this.store.useWebVpn &&
                    (this.slotFailure === ShuYoThereFailure.UNREACHABLE ||
                      this.slotFailure === ShuYoThereFailure.UNCERTAIN)) {
                    Button('开 WebVPN')
                      .height(24)
                      .fontSize(11)
                      .fontColor(this.store.colors.accent)
                      .backgroundColor(this.store.colors.accentSoft)
                      .borderRadius(12)
                      .padding({ left: 10, right: 10 })
                      .onClick(() => {
                        this.store.setUseWebVpn(true);
                        this.reloadSeatAvailability();
                      })
                  }
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

              // Areas (+ Overview toggle for 24H Study Space)
              Scroll() {
                Row({ space: 8 }) {
                  if (this.isOverviewAvailable()) {
                    Button(this.getOverviewSummaryLabel())
                      .height(30)
                      .fontSize(12)
                      .fontColor(this.selectedAreaIdx < 0 ? this.store.colors.onSelectedFill : this.store.colors.textSecondary)
                      .backgroundColor(this.selectedAreaIdx < 0 ? this.store.colors.selectedFill : this.store.colors.chipFill)
                      .borderRadius(14)
                      .padding({ left: 12, right: 12 })
                      .onClick(() => {
                        if (this.selectedAreaIdx >= 0) {
                          this.selectedAreaIdx = -1;
                          this.clearSelection();
                          this.reloadSeatAvailability();
                        }
                      })
                  }
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
                          this.clearSelection();
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
                      Text(`空闲 ${this.getCurrentArea()!.freeCount} · 清静邻空 ${this.quietCount} · 占用 ${this.getOccupiedCount(this.getCurrentArea()!)}`)
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

                  // 3-way segmented filter strip: 全部 / 仅空闲 / ✨ 清静位(邻座空)
                  Row({ space: 6 }) {
                    Button('全部')
                      .layoutWeight(0.72)
                      .height(28)
                      .padding({ left: 6, right: 6 })
                      .fontSize(11)
                      .fontColor(this.getFilterText(0))
                      .backgroundColor(this.getFilterBg(0))
                      .borderRadius(10)
                      .onClick(() => {
                        this.filterMode = 0;
                        this.floorRevision++;
                      })
                    Button(`仅空闲 ${this.getCurrentArea()!.freeCount}`)
                      .layoutWeight(1.0)
                      .height(28)
                      .padding({ left: 6, right: 6 })
                      .fontSize(11)
                      .fontColor(this.getFilterText(1))
                      .backgroundColor(this.getFilterBg(1))
                      .borderRadius(10)
                      .onClick(() => {
                        this.filterMode = 1;
                        this.floorRevision++;
                      })
                    Button(`✨ 清静位 ${this.quietCount}`)
                      .layoutWeight(1.28)
                      .height(28)
                      .padding({ left: 6, right: 6 })
                      .fontSize(11)
                      .fontColor(this.getFilterText(2))
                      .backgroundColor(this.getFilterBg(2))
                      .borderRadius(10)
                      .onClick(() => {
                        this.filterMode = 2;
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
                      filterMode: this.filterMode,
                      dataRevision: this.floorRevision,
                      isFullScreen: false,
                      onSeatDetailTap: (pt: ShuYoFloorPlanPoint) => {
                        this.handlePointSelected(pt);
                      },
                      onRequestFullScreen: () => {
                        this.showFullScreenMapSheet = true;
                      }
                    })
                  } else {
                    Column({ space: 8 }) {
                      Row({ space: 10 }) {
                        Text('● 空闲')
                          .fontSize(11)
                          .fontColor('#16A34A')
                        Text('● 清静(邻空)')
                          .fontSize(11)
                          .fontColor('#059669')
                        Text('● 占用')
                          .fontSize(11)
                          .fontColor('#DC2626')
                        Text('● 已约')
                          .fontSize(11)
                          .fontColor('#2563EB')
                      }
                      .width('100%')

                      Grid() {
                        ForEach(this.getDisplayedListPoints(), (pt: ShuYoFloorPlanPoint) => {
                          GridItem() {
                            Column({ space: 2 }) {
                              Text(pt.normalizedCode)
                                .fontSize(11.5)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.getSeatCardText(pt.seat))
                              Text(pt.seat.isDisabled ? '停用' : (pt.seat.isBooked ? '已约' : (pt.seat.isBusy ? '占用' : (pt.isQuiet ? '清静' : '空闲'))))
                                .fontSize(9.5)
                                .fontColor(this.getSeatCardText(pt.seat))
                            }
                            .width('100%')
                            .height(50)
                            .borderRadius(10)
                            .backgroundColor(this.getSeatCardBg(pt))
                            .border({
                              width: pt.seat.id === this.selectedSeatId ? 2 : 1,
                              color: this.getSeatCardBorder(pt.seat)
                            })
                            .justifyContent(FlexAlign.Center)
                            .onClick(() => {
                              this.handleSeatSelectedFromList(pt.seat);
                            })
                          }
                        }, (pt: ShuYoFloorPlanPoint): string => `${pt.seat.id}-${pt.seat.isBusy}-${pt.seat.isBooked}-${pt.isQuiet}-${this.filterMode}-${this.floorRevision}`)
                      }
                      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
                      .columnsGap(8)
                      .rowsGap(8)
                      .width('100%')
                      .height(
                        Math.min(
                          320,
                          Math.max(110, Math.ceil(this.getDisplayedListPoints().length / 5) * 58)
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

              // Bottom Cinema-Ticket Selected Seat Bar
              if (this.selectedPoint !== undefined) {
                LibrarySeatTicketCard({
                  point: this.selectedPoint,
                  selectedDay: this.selectedDay,
                  selectedStartTime: this.selectedStartTime,
                  selectedEndTime: this.selectedEndTime,
                  isSubmitting: this.isSubmittingBooking,
                  compact: false,
                  onBookTap: () => {
                    this.confirmBookSelectedSeat();
                  }
                })
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
                      Button(this.cancellingBookingId === rec.id ? '取消中...' : '取消')
                        .height(32)
                        .fontSize(12)
                        .fontColor(this.store.colors.onDanger)
                        .backgroundColor(this.store.colors.danger)
                        .borderRadius(10)
                        .padding({ left: 12, right: 12 })
                        .enabled(this.cancellingBookingId.length === 0)
                        .onClick(() => {
                          this.cancelBookingRecord(rec);
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
      .linearGradient({
        angle: 165,
        colors: ShuYoGlass.ambientGradientColors(this.store.colors)
      })
      .bindSheet($$this.showFullScreenMapSheet, this.fullScreenMapSheetBuilder(), {
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
