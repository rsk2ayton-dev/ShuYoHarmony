import { ShuYoLibrarySeat } from '../models/ShuYoModels';
import {
  LibraryFloorPlanLayout,
  ShuYoFloorPlanPoint
} from '../services/LibraryFloorPlanLayout';
import { ShuYoAppStore } from '../store/ShuYoAppStore';

interface RenderedSeatHit {
  point: ShuYoFloorPlanPoint;
  sx: number;
  sy: number;
  halfSize: number;
}

interface LabelBox {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

/**
 * Cinema-style vector floor plan renderer:
 * - Free seat: Green (#16A34A)
 * - Quiet free seat (neighbors also free): Deep emerald (#059669) + mint halo (#6EE7B7)
 * - Occupied seat: Red (#DC2626)
 * - Booked by current user: Blue (#2563EB)
 * - Disabled seat: Gray (#9CA3AF)
 * Canvas always renders at 1:1 native pixels with explicit zoom/pan projection
 * so chair icons and seat codes stay razor-sharp at 1.0x–5.0x zoom.
 */
@ComponentV2
export struct LibraryFloorPlanView {
  @Param venueId: string = '';
  @Param areaName: string = '';
  @Param seats: ShuYoLibrarySeat[] = [];
  @Param selectedSeatId: string = '';
  @Param filterMode: number = 0; // 0 = 全部, 1 = 仅空闲, 2 = 仅清静位(邻座皆空)
  @Param dataRevision: number = 0;
  @Param isFullScreen: boolean = false;
  @Param onSeatDetailTap: (pt: ShuYoFloorPlanPoint) => void = () => {};
  @Param onRequestFullScreen: () => void = () => {};

  @Local zoomScale: number = 1.0;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local viewportW: number = 320;
  @Local viewportH: number = 300;
  @Local activeRealFloorPlan: boolean = false;

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private pinchStartScale: number = 1.0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastVenueAreaKey: string = '';
  private renderedHits: RenderedSeatHit[] = [];
  private cachedPointsKey: string = '';
  private cachedPoints: ShuYoFloorPlanPoint[] = [];
  private lastFrameRedrawMs: number = 0;

  private static readonly colorFree: string = '#16A34A';
  private static readonly colorQuiet: string = '#059669';
  private static readonly colorQuietHalo: string = '#6EE7B7';
  private static readonly colorBusy: string = '#DC2626';
  private static readonly colorBooked: string = '#2563EB';
  private static readonly colorDisabled: string = '#9CA3AF';
  private static readonly colorFaintGhost: string = '#CBD5E1';
  private static readonly colorSelectedHalo: string = '#FACC15';

  aboutToAppear(): void {
    this.syncPointsCache();
  }

  @Monitor('seats', 'selectedSeatId', 'filterMode', 'venueId', 'areaName', 'dataRevision')
  onFloorInputsChanged(): void {
    const key = `${this.venueId}|${this.areaName}`;
    if (this.lastVenueAreaKey !== key) {
      this.lastVenueAreaKey = key;
      this.zoomScale = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
    }
    this.cachedPointsKey = '';
    this.syncPointsCache();
    this.redrawCanvas();
  }

  private syncPointsCache(): ShuYoFloorPlanPoint[] {
    const cacheKey = `${this.venueId}|${this.areaName}|${this.seats.length}|${this.dataRevision}`;
    if (this.cachedPointsKey === cacheKey) {
      return this.cachedPoints;
    }
    this.cachedPointsKey = cacheKey;
    const pts = LibraryFloorPlanLayout.buildFloorPlanPoints(this.venueId, this.areaName, this.seats);
    this.cachedPoints = pts;
    this.activeRealFloorPlan = pts.length > 0 && pts[0].isRealFloorPlan;
    return pts;
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
    const maxOffsetX = (this.zoomScale - 1.0) * this.viewportW * 0.56;
    const maxOffsetY = (this.zoomScale - 1.0) * this.viewportH * 0.56;
    this.offsetX = this.clamp(this.offsetX, -maxOffsetX, maxOffsetX);
    this.offsetY = this.clamp(this.offsetY, -maxOffsetY, maxOffsetY);
  }

  private adjustZoom(delta: number): void {
    this.zoomScale = this.clamp(Number((this.zoomScale + delta).toFixed(2)), 1.0, 5.0);
    this.clampViewportOffsets();
    this.redrawCanvas();
  }

  private resetZoom(): void {
    this.zoomScale = 1.0;
    this.offsetX = 0;
    this.offsetY = 0;
    this.redrawCanvas();
  }

  private requestThrottledRedraw(): void {
    const now = Date.now();
    if (now - this.lastFrameRedrawMs >= 16) {
      this.lastFrameRedrawMs = now;
      this.redrawCanvas();
    }
  }

  private getMapViewportHeight(): number {
    return this.isFullScreen ? 460 : 300;
  }

  private matchesFilter(pt: ShuYoFloorPlanPoint): boolean {
    if (pt.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0) {
      return true;
    }
    if (this.filterMode === 1) {
      return LibraryFloorPlanLayout.isSeatFree(pt.seat);
    }
    if (this.filterMode === 2) {
      return pt.isQuiet;
    }
    return true;
  }

  private resolveSeatFill(pt: ShuYoFloorPlanPoint): string {
    const seat = pt.seat;
    if (seat.isDisabled) {
      return LibraryFloorPlanView.colorDisabled;
    }
    if (seat.isBooked) {
      return LibraryFloorPlanView.colorBooked;
    }
    if (seat.isBusy) {
      return LibraryFloorPlanView.colorBusy;
    }
    return pt.isQuiet ? LibraryFloorPlanView.colorQuiet : LibraryFloorPlanView.colorFree;
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
    let bestHit: RenderedSeatHit | undefined = undefined;
    let bestDistSq = Number.MAX_VALUE;
    const minDist = Math.max(16.0, 22.0);
    const minDistSq = minDist * minDist;

    for (let i = 0; i < this.renderedHits.length; i++) {
      const hit = this.renderedHits[i];
      if (!this.matchesFilter(hit.point)) {
        continue;
      }
      const dx = screenX - hit.sx;
      const dy = screenY - hit.sy;
      const dSq = dx * dx + dy * dy;
      const seatLimit = Math.max(minDistSq, (hit.halfSize + 10) * (hit.halfSize + 10));
      if (dSq <= seatLimit && dSq < bestDistSq) {
        bestDistSq = dSq;
        bestHit = hit;
      }
    }

    if (bestHit !== undefined) {
      this.onSeatDetailTap(bestHit.point);
    }
  }

  private redrawCanvas(): void {
    if (!this.canvasReady || this.viewportW <= 10 || this.viewportH <= 10) {
      return;
    }
    this.ctx.clearRect(0, 0, this.viewportW, this.viewportH);
    this.renderedHits = [];

    const pts = this.syncPointsCache();
    if (pts.length === 0) {
      return;
    }

    if (pts[0].isRealFloorPlan) {
      this.drawRealFloorPlanVectors(pts);
    } else {
      this.drawSequentialMatrixVectors(pts);
    }
  }

  private drawCinemaChair(
    sx: number,
    sy: number,
    halfSize: number,
    facingDeg: number,
    fill: string,
    strokeColor: string,
    strokeWidth: number,
    isDimmed: boolean,
    showQuietRing: boolean,
    isSelected: boolean
  ): void {
    if (isSelected) {
      this.ctx.beginPath();
      this.ctx.arc(sx, sy, halfSize + 4.2, 0, Math.PI * 2);
      this.ctx.fillStyle = LibraryFloorPlanView.colorSelectedHalo;
      this.ctx.fill();
    } else if (showQuietRing && !isDimmed) {
      this.ctx.beginPath();
      this.ctx.arc(sx, sy, halfSize + 2.6, 0, Math.PI * 2);
      this.ctx.fillStyle = LibraryFloorPlanView.colorQuietHalo;
      this.ctx.fill();
    }

    this.ctx.save();
    this.ctx.translate(sx, sy);
    this.ctx.rotate(facingDeg * Math.PI / 180.0);

    if (halfSize < 5.2) {
      const r = halfSize;
      this.ctx.beginPath();
      this.ctx.roundRect(-r * 0.85, -r * 0.88, r * 1.7, r * 1.76, Math.max(1.5, r * 0.42));
      this.ctx.fillStyle = fill;
      this.ctx.fill();
      this.ctx.lineWidth = strokeWidth;
      this.ctx.strokeStyle = strokeColor;
      this.ctx.stroke();

      // Thin backrest bar on -X side (opposite to facing direction)
      this.ctx.beginPath();
      this.ctx.roundRect(-r * 1.02, -r * 0.72, Math.max(1.4, r * 0.36), r * 1.44, Math.max(0.8, r * 0.18));
      this.ctx.fillStyle = strokeColor;
      this.ctx.fill();
    } else {
      const cushionW = halfSize * 1.38;
      const cushionH = halfSize * 1.56;
      const backW = Math.max(2.2, halfSize * 0.42);
      const backH = halfSize * 1.72;
      const cornerR = Math.max(2.0, halfSize * 0.36);

      // Chair cushion (+X side faces the desk / front)
      this.ctx.beginPath();
      this.ctx.roundRect(-halfSize * 0.48, -cushionH / 2.0, cushionW, cushionH, cornerR);
      this.ctx.fillStyle = fill;
      this.ctx.fill();
      this.ctx.lineWidth = strokeWidth;
      this.ctx.strokeStyle = strokeColor;
      this.ctx.stroke();

      // Chair backrest (-X side)
      this.ctx.beginPath();
      this.ctx.roundRect(-halfSize * 0.98, -backH / 2.0, backW, backH, Math.max(1.5, backW * 0.45));
      this.ctx.fillStyle = isSelected ? '#1E3A8A' : (isDimmed ? '#94A3B8' : fill);
      this.ctx.fill();
      this.ctx.lineWidth = Math.max(0.8, strokeWidth * 0.85);
      this.ctx.strokeStyle = isSelected ? '#1E3A8A' : '#FFFFFF';
      this.ctx.stroke();
    }

    if (showQuietRing && !isDimmed && !isSelected) {
      this.ctx.beginPath();
      this.ctx.arc(halfSize * 0.2, 0, Math.max(1.3, halfSize * 0.24), 0, Math.PI * 2);
      this.ctx.fillStyle = '#FFFFFF';
      this.ctx.fill();
    }

    this.ctx.restore();
  }

  private overlapsAnyBox(box: LabelBox, placed: LabelBox[]): boolean {
    for (let i = 0; i < placed.length; i++) {
      const o = placed[i];
      const noOverlap = box.right < o.left || box.left > o.right || box.bottom < o.top || box.top > o.bottom;
      if (!noOverlap) {
        return true;
      }
    }
    return false;
  }

  private drawRealFloorPlanVectors(pts: ShuYoFloorPlanPoint[]): void {
    const imgAspect = LibraryFloorPlanLayout.getFloorPlanAspectRatio(this.venueId);
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
    const cx = this.viewportW / 2.0;
    const cy = this.viewportH / 2.0;
    const baseScale = imgW / 320.0;

    let baseHalf = 3.6 * baseScale;
    if (pts.length <= 24) {
      baseHalf = 6.2 * baseScale;
    } else if (pts.length <= 120) {
      baseHalf = 4.2 * baseScale;
    }
    // Gentle sub-linear icon growth on zoom so zoomed view gains breathing room between adjacent seats
    const zoomedHalf = this.clamp(baseHalf * Math.pow(this.zoomScale, 0.72), 3.4, 15.0);

    // Draw dimmed non-matching seats first, then active seats, then selected seat on top
    const passOrder: number[] = [];
    let selectedIdx = -1;
    for (let i = 0; i < pts.length; i++) {
      if (pts[i].seat.id === this.selectedSeatId && this.selectedSeatId.length > 0) {
        selectedIdx = i;
      } else if (!this.matchesFilter(pts[i])) {
        passOrder.push(i);
      }
    }
    for (let i = 0; i < pts.length; i++) {
      if (i !== selectedIdx && this.matchesFilter(pts[i])) {
        passOrder.push(i);
      }
    }
    if (selectedIdx >= 0) {
      passOrder.push(selectedIdx);
    }

    const labelCandidates: RenderedSeatHit[] = [];
    const marginCull = zoomedHalf + 24;

    for (let p = 0; p < passOrder.length; p++) {
      const pt = pts[passOrder[p]];
      const baseX = imgX + pt.nx * imgW;
      const baseY = imgY + pt.ny * imgH;
      const sx = (baseX - cx) * this.zoomScale + cx + this.offsetX;
      const sy = (baseY - cy) * this.zoomScale + cy + this.offsetY;

      const isSelected = pt.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0;
      const isMatch = this.matchesFilter(pt);
      const isDimmed = this.filterMode !== 0 && !isMatch && !isSelected;

      const halfSize = isSelected
        ? zoomedHalf * 1.25
        : (isDimmed ? Math.max(2.2, zoomedHalf * 0.58) : zoomedHalf);

      const hit: RenderedSeatHit = {
        point: pt,
        sx: sx,
        sy: sy,
        halfSize: halfSize
      };
      this.renderedHits.push(hit);

      if (sx < -marginCull || sx > this.viewportW + marginCull ||
        sy < -marginCull || sy > this.viewportH + marginCull) {
        continue;
      }

      const fill = isDimmed ? LibraryFloorPlanView.colorFaintGhost : this.resolveSeatFill(pt);
      const strokeColor = isSelected ? '#1E3A8A' : (isDimmed ? '#E2E8F0' : '#FFFFFF');
      const strokeW = isSelected ? 1.8 : 0.95;

      this.drawCinemaChair(
        sx,
        sy,
        halfSize,
        pt.facingDeg,
        fill,
        strokeColor,
        strokeW,
        isDimmed,
        pt.isQuiet,
        isSelected
      );

      if (!isDimmed && (pts.length <= 24 || isSelected || this.zoomScale >= 2.2)) {
        labelCandidates.push(hit);
      }
    }

    // Crisp non-overlapping seat code labels (selected seat always wins)
    const placed: LabelBox[] = [];
    const fontSize = Math.round(this.clamp(8.5 + (this.zoomScale - 1.0) * 0.8, 8.5, 11.5));
    this.ctx.font = `bold ${fontSize}vp sans-serif`;
    this.ctx.textAlign = 'center';
    this.ctx.textBaseline = 'bottom';

    for (let i = labelCandidates.length - 1; i >= 0; i--) {
      const hit = labelCandidates[i];
      const text = hit.point.normalizedCode;
      const isSelected = hit.point.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0;
      const textW = text.length * (fontSize * 0.62) + 6;
      const textH = fontSize + 4;
      const ly = hit.sy - hit.halfSize - 3;
      const box: LabelBox = {
        left: hit.sx - textW / 2.0,
        right: hit.sx + textW / 2.0,
        top: ly - textH,
        bottom: ly
      };
      if (!isSelected && this.overlapsAnyBox(box, placed)) {
        continue;
      }
      placed.push(box);

      // Subtle white pill behind label for maximum contrast over map lines
      this.ctx.beginPath();
      this.ctx.roundRect(box.left, box.top + 1, textW, textH - 1, 4);
      this.ctx.fillStyle = isSelected ? '#1E3A8A' : 'rgba(255,255,255,0.88)';
      this.ctx.fill();

      this.ctx.fillStyle = isSelected ? '#FFFFFF' : '#0F172A';
      this.ctx.fillText(text, hit.sx, ly);
    }
  }

  private drawSequentialMatrixVectors(pts: ShuYoFloorPlanPoint[]): void {
    const cx = this.viewportW / 2.0;
    const cy = this.viewportH / 2.0;
    const total = pts.length;
    const cols = total <= 24 ? 8 : 10;
    const rows = Math.max(1, Math.ceil(total / cols));

    const pad = 8;
    const roomW = this.viewportW - pad * 2;
    const roomH = this.viewportH - pad * 2;

    const minDim = Math.min(roomW / cols, (roomH * 0.76) / rows);
    const baseHalf = this.clamp(minDim * 0.34, 8.5, 14.5);
    const zoomedHalf = this.clamp(baseHalf * Math.pow(this.zoomScale, 0.72), 8.5, 22.0);

    // Draw subtle row guides at scaled positions
    this.ctx.fillStyle = '#64748B';
    this.ctx.font = 'bold 9vp sans-serif';
    this.ctx.textAlign = 'left';
    this.ctx.textBaseline = 'middle';
    for (let r = 0; r < rows; r++) {
      const idx = r * cols;
      if (idx >= pts.length) {
        break;
      }
      const baseY = pad + pts[idx].ny * roomH;
      const sy = (baseY - cy) * this.zoomScale + cy + this.offsetY;
      if (sy >= 34 && sy <= this.viewportH - 8) {
        this.ctx.fillText(`${r + 1}排`, 8, sy);
      }
    }

    const fontSize = Math.round(this.clamp(zoomedHalf * 0.68, 7.5, 11.0));
    for (let i = 0; i < pts.length; i++) {
      const pt = pts[i];
      const baseX = pad + pt.nx * roomW;
      const baseY = pad + pt.ny * roomH;
      const sx = (baseX - cx) * this.zoomScale + cx + this.offsetX;
      const sy = (baseY - cy) * this.zoomScale + cy + this.offsetY;

      const isSelected = pt.seat.id === this.selectedSeatId && this.selectedSeatId.length > 0;
      const isMatch = this.matchesFilter(pt);
      const isDimmed = this.filterMode !== 0 && !isMatch && !isSelected;
      const halfSize = isSelected ? zoomedHalf * 1.12 : zoomedHalf;

      this.renderedHits.push({
        point: pt,
        sx: sx,
        sy: sy,
        halfSize: halfSize
      });

      if (sx < -halfSize - 10 || sx > this.viewportW + halfSize + 10 ||
        sy < -halfSize - 10 || sy > this.viewportH + halfSize + 10) {
        continue;
      }

      const fill = isDimmed ? '#E2E8F0' : this.resolveSeatFill(pt);
      const strokeColor = isSelected ? '#1E3A8A' : (isDimmed ? '#CBD5E1' : '#FFFFFF');
      const strokeW = isSelected ? 1.8 : 1.0;

      this.drawCinemaChair(
        sx,
        sy,
        halfSize,
        pt.facingDeg,
        fill,
        strokeColor,
        strokeW,
        isDimmed,
        false,
        isSelected
      );
      if (pt.isQuiet && !isDimmed && !isSelected) {
        this.ctx.beginPath();
        this.ctx.arc(sx, sy, halfSize + 2.4, 0, Math.PI * 2);
        this.ctx.lineWidth = 1.4;
        this.ctx.strokeStyle = LibraryFloorPlanView.colorQuietHalo;
        this.ctx.stroke();
      }

      this.ctx.fillStyle = isDimmed ? '#94A3B8' : '#FFFFFF';
      this.ctx.font = `bold ${fontSize}vp sans-serif`;
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      this.ctx.fillText(pt.seat.seatLabel, sx, sy + halfSize * 0.12);
    }
  }

  @Builder
  private legendDot(dotColor: string, label: string, haloColor: string = '') {
    Row({ space: 4 }) {
      Column()
        .width(9)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(dotColor)
        .border(haloColor.length > 0 ? { width: 1.5, color: haloColor } : { width: 0 })
      Text(label)
        .fontSize(10.5)
        .fontColor(this.store.colors.textSecondary)
    }
  }

  build() {
    Column({ space: 8 }) {
      // Legend row + zoom toolbar row (never squeezed on narrow phones)
      Row({ space: 8 }) {
        Row({ space: 8 }) {
          this.legendDot(LibraryFloorPlanView.colorFree, '空闲')
          this.legendDot(LibraryFloorPlanView.colorQuiet, '清静', LibraryFloorPlanView.colorQuietHalo)
          this.legendDot(LibraryFloorPlanView.colorBusy, '占用')
          this.legendDot(LibraryFloorPlanView.colorBooked, '已约')
          this.legendDot(LibraryFloorPlanView.colorDisabled, '停用')
        }
        .layoutWeight(1)

        if (!this.isFullScreen) {
          Button('全屏选座')
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
      .width('100%')

      Row({ space: 6 }) {
        Text(this.activeRealFloorPlan ? '实景平面图选座' : '连号矩阵视图')
          .fontSize(11)
          .fontColor(this.store.colors.textTertiary)
        Blank()
        Row({ space: 4 }) {
          Button('-')
            .width(24)
            .height(24)
            .padding(0)
            .fontSize(13)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(7)
            .onClick(() => {
              this.adjustZoom(-0.6);
            })
          Text(`${this.zoomScale.toFixed(1)}×`)
            .fontSize(11)
            .fontColor(this.store.colors.textSecondary)
            .width(34)
            .textAlign(TextAlign.Center)
          Button('+')
            .width(24)
            .height(24)
            .padding(0)
            .fontSize(13)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(7)
            .onClick(() => {
              this.adjustZoom(0.6);
            })
          if (this.zoomScale > 1.02) {
            Button('重置')
              .height(24)
              .fontSize(10.5)
              .fontColor(this.store.colors.textSecondary)
              .backgroundColor(this.store.colors.surfaceAlt)
              .borderRadius(7)
              .padding({ left: 7, right: 7 })
              .onClick(() => {
                this.resetZoom();
              })
          }
        }
      }
      .width('100%')

      // Interactive map viewport
      Stack({ alignContent: Alignment.Top }) {
        if (this.seats.length === 0) {
          Column() {
            Text('暂无该时段座位数据')
              .fontSize(13)
              .fontColor(this.store.colors.textMuted)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            // Scaled & panned floor plan image layer (when real map exists)
            if (this.activeRealFloorPlan) {
              Stack({ alignContent: Alignment.TopStart }) {
                Image($rawfile('library_booking/seats.jpg'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
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

            // 1:1 native-pixel vector Canvas layer (never CSS-scaled so icons & numbers remain sharp)
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

          if (!this.activeRealFloorPlan) {
            Row({ space: 6 }) {
              Text('暂无该馆实测平面图 · 按座位连号展示空/占（非真实桌位排布）')
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#92400E')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#FEF3C7')
            .border({ width: { bottom: 1 }, color: '#FDE68A' })
            .hitTestBehavior(HitTestMode.None)
          }
        }
      }
      .width('100%')
      .height(this.getMapViewportHeight())
      .clip(true)
      .borderRadius(12)
      .backgroundColor(this.activeRealFloorPlan ? '#FFFFFF' : '#F8FAFC')
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
            this.zoomScale = this.clamp(this.pinchStartScale * event.scale, 1.0, 5.0);
            this.clampViewportOffsets();
            this.requestThrottledRedraw();
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
            this.requestThrottledRedraw();
          })
          .onActionEnd(() => {
            this.redrawCanvas();
          })
      )

      Text(this.activeRealFloorPlan
        ? (this.zoomScale >= 2.2
          ? '已放大展示清晰座号：单指拖动，点击任意座椅查看左右/对面邻座情况'
          : '双指捏合或点“+”放大至 2.2× 以上可清晰查看座号，带浅绿光圈表示左右皆空')
        : '点击任意座椅可查看该座位及前后连号空闲状态（非实际桌位排布）')
        .fontSize(11)
        .fontColor(this.store.colors.textTertiary)
    }
    .width('100%')
  }
}
