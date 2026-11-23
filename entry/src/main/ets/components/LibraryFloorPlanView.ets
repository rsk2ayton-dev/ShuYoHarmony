import { ShuYoLibrarySeat } from '../models/ShuYoModels';
import {
  LibraryFloorPlanLayout,
  ShuYoFloorPlanPoint,
  ShuYoReadingDeskRect
} from '../services/LibraryFloorPlanLayout';
import { ShuYoAppStore } from '../store/ShuYoAppStore';

interface RenderedSeatHit {
  seat: ShuYoLibrarySeat;
  x: number;
  y: number;
  radius: number;
  zoneHint: string;
}

/**
 * Interactive floor plan renderer:
 * - Free seat: Green (#16A34A)
 * - Occupied seat: Red (#DC2626)
 * - Booked by current user: Blue (#2563EB)
 * - Disabled seat: Gray (#9CA3AF)
 * Supports pinch-to-zoom, pan when zoomed, and tap selection.
 */
@ComponentV2
export struct LibraryFloorPlanView {
  @Param venueId: string = '';
  @Param areaName: string = '';
  @Param seats: ShuYoLibrarySeat[] = [];
  @Param selectedSeatId: string = '';
  @Param onlyShowAvailable: boolean = false;
  @Param dataRevision: number = 0;
  @Param isFullScreen: boolean = false;
  @Param onSeatTap: (seat: ShuYoLibrarySeat, zoneHint: string) => void = () => {};
  @Param onRequestFullScreen: () => void = () => {};

  @Local zoomScale: number = 1.0;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local viewportW: number = 320;
  @Local viewportH: number = 250;

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private pinchStartScale: number = 1.0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastVenueAreaKey: string = '';
  private renderedHits: RenderedSeatHit[] = [];

  private static readonly colorFree: string = '#16A34A';
  private static readonly colorBusy: string = '#DC2626';
  private static readonly colorBooked: string = '#2563EB';
  private static readonly colorDisabled: string = '#9CA3AF';
  private static readonly colorFaintGhost: string = '#CBD5E1';
  private static readonly colorSelectedHalo: string = '#FACC15';

  @Monitor('seats', 'selectedSeatId', 'onlyShowAvailable', 'venueId', 'areaName', 'dataRevision')
  onFloorInputsChanged(): void {
    const key = `${this.venueId}|${this.areaName}`;
    if (this.lastVenueAreaKey !== key) {
      this.lastVenueAreaKey = key;
      this.zoomScale = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
    }
    this.redrawCanvas();
  }

  private clamp(val: number, minVal: number, maxVal: number): number {
    if (val < minVal) {
      return minVal;
    }
    if (val > maxVal) {
      return maxVal;
    }
    return val;
  }

  private clampViewportOffsets(): void {
    if (this.zoomScale <= 1.02) {
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    const maxOffsetX = (this.zoomScale - 1.0) * this.viewportW * 0.52;
    const maxOffsetY = (this.zoomScale - 1.0) * this.viewportH * 0.52;
    this.offsetX = this.clamp(this.offsetX, -maxOffsetX, maxOffsetX);
    this.offsetY = this.clamp(this.offsetY, -maxOffsetY, maxOffsetY);
  }

  private adjustZoom(delta: number): void {
    const prevShowLabels = this.zoomScale >= 2.0;
    this.zoomScale = this.clamp(Number((this.zoomScale + delta).toFixed(2)), 1.0, 4.0);
    this.clampViewportOffsets();
    const nextShowLabels = this.zoomScale >= 2.0;
    if (prevShowLabels !== nextShowLabels || this.zoomScale >= 2.0) {
      this.redrawCanvas();
    }
  }

  private resetZoom(): void {
    const wasZoomed = this.zoomScale >= 2.0;
    this.zoomScale = 1.0;
    this.offsetX = 0;
    this.offsetY = 0;
    if (wasZoomed) {
      this.redrawCanvas();
    }
  }

  private isCircularStudyMap(): boolean {
    return LibraryFloorPlanLayout.canUseCircularStudyMap(this.venueId, this.seats);
  }

  private getMapViewportHeight(): number {
    if (this.isFullScreen) {
      return this.isCircularStudyMap() ? 420 : 460;
    }
    return this.isCircularStudyMap() ? 248 : 292;
  }

  private resolveSeatFill(seat: ShuYoLibrarySeat): string {
    if (seat.isDisabled) {
      return LibraryFloorPlanView.colorDisabled;
    }
    if (seat.isBooked) {
      return LibraryFloorPlanView.colorBooked;
    }
    if (seat.isBusy) {
      return LibraryFloorPlanView.colorBusy;
    }
    return LibraryFloorPlanView.colorFree;
  }

  private isSeatFree(seat: ShuYoLibrarySeat): boolean {
    return !seat.isDisabled && !seat.isBusy && !seat.isBooked;
  }

  private handleViewportAreaChange(newArea: Area): void {
    const w = Number(newArea.width);
    const h = Number(newArea.height);
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 80 || h < 80) {
      return;
    }
    if (Math.abs(w - this.viewportW) < 0.5 && Math.abs(h - this.viewportH) < 0.5) {
      return;
    }
    this.viewportW = w;
    this.viewportH = h;
    this.clampViewportOffsets();
    this.redrawCanvas();
  }

  private handleCanvasTap(screenX: number, screenY: number): void {
    if (this.renderedHits.length === 0) {
      return;
    }
    const cx = this.viewportW / 2.0;
    const cy = this.viewportH / 2.0;
    const mapX = (screenX - this.offsetX - cx) / this.zoomScale + cx;
    const mapY = (screenY - this.offsetY - cy) / this.zoomScale + cy;

    let bestHit: RenderedSeatHit | undefined = undefined;
    let bestDistSq = Number.MAX_VALUE;
    const maxHitDist = Math.max(18.0, 26.0 / Math.sqrt(this.zoomScale));
    const maxDistSq = maxHitDist * maxHitDist;

    for (let i = 0; i < this.renderedHits.length; i++) {
      const hit = this.renderedHits[i];
      if (this.onlyShowAvailable && !this.isSeatFree(hit.seat) && hit.seat.id !== this.selectedSeatId) {
        continue;
      }
      const dx = mapX - hit.x;
      const dy = mapY - hit.y;
      const dSq = dx * dx + dy * dy;
      const seatLimit = Math.max(maxDistSq, (hit.radius + 10) * (hit.radius + 10));
      if (dSq <= seatLimit && dSq < bestDistSq) {
        bestDistSq = dSq;
        bestHit = hit;
      }
    }

    if (bestHit !== undefined) {
      this.onSeatTap(bestHit.seat, bestHit.zoneHint);
    }
  }

  private redrawCanvas(): void {
    if (!this.canvasReady || this.viewportW <= 10 || this.viewportH <= 10) {
      return;
    }
    this.ctx.clearRect(0, 0, this.viewportW, this.viewportH);
    this.renderedHits = [];

    if (this.seats.length === 0) {
      return;
    }

    if (this.isCircularStudyMap()) {
      this.drawCircularStudySpaceOverlay();
    } else {
      this.drawArchitecturalReadingRoom();
    }
  }

  private drawCircularStudySpaceOverlay(): void {
    const imgAspect = LibraryFloorPlanLayout.studyMapAspectRatio;
    const viewAspect = this.viewportW / this.viewportH;
    let imgW = this.viewportW;
    let imgH = this.viewportH;
    if (viewAspect >= imgAspect) {
      imgH = this.viewportH;
      imgW = imgH * imgAspect;
    } else {
      imgW = this.viewportW;
      imgH = imgW / imgAspect;
    }
    const imgX = (this.viewportW - imgW) / 2.0;
    const imgY = (this.viewportH - imgH) / 2.0;
    const scaleFactor = imgW / 320.0;

    let baseRadius = 3.5 * scaleFactor;
    if (this.seats.length <= 24) {
      baseRadius = 6.2 * scaleFactor;
    } else if (this.seats.length <= 120) {
      baseRadius = 4.1 * scaleFactor;
    }
    if (this.zoomScale >= 2.2) {
      baseRadius *= 0.85;
    }

    const pts: ShuYoFloorPlanPoint[] = LibraryFloorPlanLayout.buildStudySpacePoints(this.seats);
    for (let i = 0; i < pts.length; i++) {
      const pt = pts[i];
      const px = imgX + pt.nx * imgW;
      const py = imgY + pt.ny * imgH;
      const isSelected = pt.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0;
      const free = this.isSeatFree(pt.seat);

      let drawR = isSelected ? baseRadius * 1.45 : baseRadius;
      let fill = this.resolveSeatFill(pt.seat);
      if (this.onlyShowAvailable && !free && !isSelected) {
        drawR = Math.max(1.8, baseRadius * 0.55);
        fill = LibraryFloorPlanView.colorFaintGhost;
      }

      if (isSelected) {
        this.ctx.beginPath();
        this.ctx.arc(px, py, drawR + 3.2, 0, Math.PI * 2);
        this.ctx.fillStyle = LibraryFloorPlanView.colorSelectedHalo;
        this.ctx.fill();
      }

      this.ctx.beginPath();
      this.ctx.arc(px, py, drawR, 0, Math.PI * 2);
      this.ctx.fillStyle = fill;
      this.ctx.fill();
      this.ctx.lineWidth = isSelected ? 1.8 : 1.0;
      this.ctx.strokeStyle = isSelected ? '#1E3A8A' : '#FFFFFF';
      this.ctx.stroke();

      if (this.seats.length <= 24 || isSelected || this.zoomScale >= 2.0) {
        this.ctx.fillStyle = '#111827';
        this.ctx.font = `bold ${Math.max(7, Math.round(8.5 * scaleFactor))}vp sans-serif`;
        this.ctx.textAlign = 'center';
        this.ctx.textBaseline = 'bottom';
        this.ctx.fillText(pt.seat.seatLabel, px, py - drawR - 2);
      }

      this.renderedHits.push({
        seat: pt.seat,
        x: px,
        y: py,
        radius: drawR,
        zoneHint: pt.zoneHint
      });
    }
  }

  private drawArchitecturalReadingRoom(): void {
    const pad = 8;
    const roomW = this.viewportW - pad * 2;
    const roomH = this.viewportH - pad * 2;

    // Room floor plate
    this.ctx.beginPath();
    this.ctx.roundRect(pad, pad, roomW, roomH, 12);
    this.ctx.fillStyle = '#F8FAFC';
    this.ctx.fill();
    this.ctx.lineWidth = 1.4;
    this.ctx.strokeStyle = '#CBD5E1';
    this.ctx.stroke();

    // North window wall strip
    const winW = roomW * 0.62;
    const winX = pad + (roomW - winW) / 2.0;
    this.ctx.beginPath();
    this.ctx.roundRect(winX, pad + 4, winW, 16, 6);
    this.ctx.fillStyle = '#DBEAFE';
    this.ctx.fill();
    this.ctx.fillStyle = '#1D4ED8';
    this.ctx.font = 'bold 9vp sans-serif';
    this.ctx.textAlign = 'center';
    this.ctx.textBaseline = 'middle';
    this.ctx.fillText(`${this.areaName.length > 0 ? this.areaName : '阅览室'} · 靠窗采光区`, pad + roomW / 2.0, pad + 12);

    // South entrance door indicator
    const doorW = Math.min(92, roomW * 0.34);
    const doorX = pad + (roomW - doorW) / 2.0;
    this.ctx.beginPath();
    this.ctx.roundRect(doorX, pad + roomH - 18, doorW, 14, 5);
    this.ctx.fillStyle = '#E2E8F0';
    this.ctx.fill();
    this.ctx.fillStyle = '#475569';
    this.ctx.font = 'bold 9vp sans-serif';
    this.ctx.fillText('入口 / 主通道', pad + roomW / 2.0, pad + roomH - 11);

    const layout = LibraryFloorPlanLayout.buildReadingRoomLayout(this.seats);
    // Study desks
    for (let i = 0; i < layout.desks.length; i++) {
      const desk: ShuYoReadingDeskRect = layout.desks[i];
      const dx = pad + desk.x * roomW;
      const dy = pad + desk.y * roomH;
      const dw = desk.w * roomW;
      const dh = desk.h * roomH;

      this.ctx.beginPath();
      this.ctx.roundRect(dx, dy, dw, dh, 5);
      this.ctx.fillStyle = '#EFE6D8';
      this.ctx.fill();
      this.ctx.lineWidth = 1.0;
      this.ctx.strokeStyle = '#C7B8A1';
      this.ctx.stroke();

      this.ctx.fillStyle = '#786652';
      this.ctx.font = '8vp sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      this.ctx.fillText(desk.label, dx + dw / 2.0, dy + dh / 2.0);
    }

    // Seats
    const seatRadius = this.clamp(
      Math.min(roomW, roomH) / (this.seats.length <= 24 ? 19 : 27),
      7.5,
      14.5
    );

    for (let i = 0; i < layout.points.length; i++) {
      const pt = layout.points[i];
      const sx = pad + pt.nx * roomW;
      const sy = pad + pt.ny * roomH;
      const isSelected = pt.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0;
      const free = this.isSeatFree(pt.seat);

      const drawR = isSelected ? seatRadius * 1.18 : seatRadius;
      let fill = this.resolveSeatFill(pt.seat);
      if (this.onlyShowAvailable && !free && !isSelected) {
        fill = '#E2E8F0';
      }

      if (isSelected) {
        this.ctx.beginPath();
        this.ctx.arc(sx, sy, drawR + 3.0, 0, Math.PI * 2);
        this.ctx.fillStyle = LibraryFloorPlanView.colorSelectedHalo;
        this.ctx.fill();
      }

      this.ctx.beginPath();
      this.ctx.arc(sx, sy, drawR, 0, Math.PI * 2);
      this.ctx.fillStyle = fill;
      this.ctx.fill();
      this.ctx.lineWidth = isSelected ? 1.8 : 1.0;
      this.ctx.strokeStyle = isSelected ? '#1E3A8A' : '#FFFFFF';
      this.ctx.stroke();

      this.ctx.fillStyle = (this.onlyShowAvailable && !free && !isSelected) ? '#94A3B8' : '#FFFFFF';
      this.ctx.font = `bold ${drawR >= 10.5 ? 9 : 8}vp sans-serif`;
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      this.ctx.fillText(pt.seat.seatLabel, sx, sy);

      this.renderedHits.push({
        seat: pt.seat,
        x: sx,
        y: sy,
        radius: drawR,
        zoneHint: pt.zoneHint
      });
    }
  }

  @Builder
  private legendDot(dotColor: string, label: string) {
    Row({ space: 4 }) {
      Column()
        .width(9)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(dotColor)
      Text(label)
        .fontSize(11)
        .fontColor(this.store.colors.textSecondary)
    }
  }

  build() {
    Column({ space: 8 }) {
      // Legend + zoom toolbar
      Row({ space: 8 }) {
        this.legendDot(LibraryFloorPlanView.colorFree, '空闲')
        this.legendDot(LibraryFloorPlanView.colorBusy, '占用')
        this.legendDot(LibraryFloorPlanView.colorBooked, '已约')
        this.legendDot(LibraryFloorPlanView.colorDisabled, '停用')
        Blank()

        Row({ space: 4 }) {
          Button('-')
            .width(24)
            .height(24)
            .padding(0)
            .fontSize(13)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(8)
            .onClick(() => {
              this.adjustZoom(-0.5);
            })
          Text(`${this.zoomScale.toFixed(1)}×`)
            .fontSize(11)
            .fontColor(this.store.colors.textSecondary)
            .width(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.resetZoom();
            })
          Button('+')
            .width(24)
            .height(24)
            .padding(0)
            .fontSize(13)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(8)
            .onClick(() => {
              this.adjustZoom(0.5);
            })

          if (!this.isFullScreen) {
            Button('放大')
              .height(24)
              .fontSize(11)
              .fontColor(this.store.colors.accent)
              .backgroundColor(this.store.colors.accentSoft)
              .borderRadius(8)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.onRequestFullScreen();
              })
          }
        }
      }
      .width('100%')

      // Interactive map viewport
      Stack({ alignContent: Alignment.Center }) {
        if (this.seats.length === 0) {
          Text('暂无该时段座位数据')
            .fontSize(13)
            .fontColor(this.store.colors.textMuted)
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            Stack({ alignContent: Alignment.TopStart }) {
              if (this.isCircularStudyMap()) {
                Image($rawfile('library_booking/seats.jpg'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              }

              Canvas(this.ctx)
                .width('100%')
                .height('100%')
                .onReady(() => {
                  this.canvasReady = true;
                  this.redrawCanvas();
                })
            }
            .width('100%')
            .height('100%')
            .scale({
              x: this.zoomScale,
              y: this.zoomScale,
              centerX: '50%',
              centerY: '50%'
            })
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.offsetX, y: this.offsetY })
        }
      }
      .width('100%')
      .height(this.getMapViewportHeight())
      .clip(true)
      .borderRadius(12)
      .backgroundColor(this.isCircularStudyMap() ? '#FFFFFF' : '#F8FAFC')
      .border({ width: 1, color: this.store.colors.border })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.handleViewportAreaChange(newArea);
      })
      .onClick((event: ClickEvent) => {
        this.handleCanvasTap(event.x, event.y);
      })
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.pinchStartScale = this.zoomScale;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.zoomScale = this.clamp(this.pinchStartScale * event.scale, 1.0, 4.0);
            this.clampViewportOffsets();
          })
          .onActionEnd(() => {
            this.redrawCanvas();
          })
      )
      .parallelGesture(
        PanGesture({
          fingers: 1,
          direction: this.zoomScale > 1.02 ? PanDirection.All : PanDirection.None
        })
          .onActionStart(() => {
            this.panStartX = this.offsetX;
            this.panStartY = this.offsetY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.zoomScale <= 1.02) {
              return;
            }
            this.offsetX = this.panStartX + event.offsetX;
            this.offsetY = this.panStartY + event.offsetY;
            this.clampViewportOffsets();
          })
      )

      Text(this.zoomScale > 1.02
        ? '提示：单指可拖动平面图，点击任意绿/红圆点查看并选中座位'
        : '提示：双指或点击“+/-”缩放查看密集席位，轻触座位圆点即可选座')
        .fontSize(11)
        .fontColor(this.store.colors.textTertiary)
    }
    .width('100%')
  }
}
