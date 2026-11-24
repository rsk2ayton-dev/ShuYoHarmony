import { AnimatorOptions, AnimatorResult, LengthMetrics } from '@kit.ArkUI';
import { ShuYoGlass, ShuYoMotion } from '../core/ShuYoMotionGlass';
import { ShuYoLibrarySeat } from '../models/ShuYoModels';
import {
  LibraryFloorPlanLayout,
  ShuYoFloorPlanPoint,
  ShuYoSeatNeighborSummary
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
  private zoomAnimator: AnimatorResult | undefined = undefined;

  private static readonly colorFree: string = '#16A34A';
  private static readonly colorQuiet: string = '#059669';
  private static readonly colorQuietHalo: string = '#6EE7B7';
  private static readonly colorBusy: string = '#DC2626';
  private static readonly colorBooked: string = '#2563EB';
  private static readonly colorDisabled: string = '#9CA3AF';
  private static readonly colorFaintGhost: string = '#CBD5E1';
  private static readonly colorSelectedHalo: string = '#FACC15';

  aboutToAppear(): void {
    this.lastVenueAreaKey = `${this.venueId}|${this.areaName}`;
    this.syncPointsCache();
  }

  aboutToDisappear(): void {
    this.cancelZoomAnimation();
  }

  @Monitor('seats', 'selectedSeatId', 'filterMode', 'venueId', 'areaName', 'dataRevision')
  onFloorInputsChanged(): void {
    const key = `${this.venueId}|${this.areaName}`;
    if (this.lastVenueAreaKey !== key) {
      this.cancelZoomAnimation();
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

  private cancelZoomAnimation(): void {
    const anim = this.zoomAnimator;
    if (anim !== undefined) {
      anim.cancel();
      this.zoomAnimator = undefined;
    }
  }

  private animateZoomTo(targetScale: number, targetX?: number, targetY?: number): void {
    this.cancelZoomAnimation();
    const startScale = this.zoomScale;
    const startX = this.offsetX;
    const startY = this.offsetY;
    const clampedEndScale = this.clamp(Math.round(targetScale * 100) / 100, 1.0, 5.0);
    let rawEndX = 0;
    let rawEndY = 0;
    if (clampedEndScale > 1.02) {
      const ratio = startScale > 0 ? clampedEndScale / startScale : 1.0;
      const maxX = (clampedEndScale - 1.0) * this.viewportW * 0.56;
      const maxY = (clampedEndScale - 1.0) * this.viewportH * 0.56;
      rawEndX = this.clamp(targetX !== undefined ? targetX : startX * ratio, -maxX, maxX);
      rawEndY = this.clamp(targetY !== undefined ? targetY : startY * ratio, -maxY, maxY);
    }
    if (Math.abs(clampedEndScale - startScale) < 0.01 &&
      Math.abs(rawEndX - startX) < 0.5 &&
      Math.abs(rawEndY - startY) < 0.5) {
      this.zoomScale = clampedEndScale;
      this.offsetX = rawEndX;
      this.offsetY = rawEndY;
      this.clampViewportOffsets();
      this.redrawCanvas();
      return;
    }
    const uiCtx = this.getUIContext();
    if (uiCtx === undefined) {
      this.zoomScale = clampedEndScale;
      this.offsetX = rawEndX;
      this.offsetY = rawEndY;
      this.clampViewportOffsets();
      this.redrawCanvas();
      return;
    }
    const opts: AnimatorOptions = {
      duration: 240,
      easing: 'fast-out-slow-in',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: 0,
      end: 1
    };
    const animator = uiCtx.createAnimator(opts);
    animator.onFrame = (t: number) => {
      this.zoomScale = startScale + (clampedEndScale - startScale) * t;
      this.offsetX = startX + (rawEndX - startX) * t;
      this.offsetY = startY + (rawEndY - startY) * t;
      this.clampViewportOffsets();
      this.redrawCanvas();
    };
    animator.onFinish = () => {
      this.zoomScale = clampedEndScale;
      this.offsetX = rawEndX;
      this.offsetY = rawEndY;
      this.clampViewportOffsets();
      this.redrawCanvas();
      this.zoomAnimator = undefined;
    };
    this.zoomAnimator = animator;
    animator.play();
  }

  private adjustZoom(delta: number): void {
    const nextScale = Math.round((this.zoomScale + delta) * 100) / 100;
    this.animateZoomTo(nextScale);
  }

  private toggleQuickZoom(): void {
    if (this.zoomScale >= 2.2) {
      this.resetZoom();
    } else {
      this.animateZoomTo(2.5);
    }
  }

  private resetZoom(): void {
    this.animateZoomTo(1.0, 0, 0);
  }

  private requestThrottledRedraw(): void {
    const now = Date.now();
    if (now - this.lastFrameRedrawMs >= 16) {
      this.lastFrameRedrawMs = now;
      this.redrawCanvas();
    }
  }

  private getMapViewportHeight(): number {
    if (this.activeRealFloorPlan) {
      return this.isFullScreen ? 360 : 252;
    }
    return this.isFullScreen ? 420 : 300;
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
      this.ctx.arc(sx, sy, halfSize + Math.max(1.2, halfSize * 0.34), 0, Math.PI * 2);
      this.ctx.lineWidth = Math.max(1.2, halfSize * 0.28);
      this.ctx.strokeStyle = LibraryFloorPlanView.colorQuietHalo;
      this.ctx.stroke();
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
            .clickEffect(ShuYoMotion.snappyClick)
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
        Row({ space: 6 }) {
          Text('−')
            .width(32)
            .height(28)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(8)
            .border({ width: 1, color: this.store.colors.border })
            .clickEffect(ShuYoMotion.snappyClick)
            .onClick(() => {
              this.adjustZoom(-0.6);
            })
          Text(`${this.zoomScale.toFixed(1)}×`)
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textSecondary)
            .width(36)
            .textAlign(TextAlign.Center)
          Text('+')
            .width(32)
            .height(28)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surfaceAlt)
            .borderRadius(8)
            .border({ width: 1, color: this.store.colors.border })
            .clickEffect(ShuYoMotion.snappyClick)
            .onClick(() => {
              this.adjustZoom(0.6);
            })
          Text(this.zoomScale >= 2.2 ? '还原' : '2.5×')
            .height(28)
            .padding({ left: 9, right: 9 })
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .fontColor(this.store.colors.accent)
            .backgroundColor(this.store.colors.accentSoft)
            .borderRadius(8)
            .clickEffect(ShuYoMotion.snappyClick)
            .onClick(() => {
              this.toggleQuickZoom();
            })
          if (this.zoomScale > 1.02 && this.zoomScale < 2.2) {
            Text('重置')
              .height(28)
              .padding({ left: 8, right: 8 })
              .fontSize(11)
              .textAlign(TextAlign.Center)
              .fontColor(this.store.colors.textSecondary)
              .backgroundColor(this.store.colors.surfaceAlt)
              .borderRadius(8)
              .border({ width: 1, color: this.store.colors.border })
              .clickEffect(ShuYoMotion.snappyClick)
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
              Text('暂无实测平面图 · 仅按连号展示空/占（非真实桌位）')
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#92400E')
                .maxLines(2)
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
            this.cancelZoomAnimation();
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

/**
 * Reactive cinema-style bottom ticket card for the selected seat.
 * Isolated as a @ComponentV2 struct so re-selecting or booking a seat immediately
 * refreshes status badge, action button, and neighbor states.
 */
@ComponentV2
export struct LibrarySeatTicketCard {
  @Param point: ShuYoFloorPlanPoint | undefined = undefined;
  @Param selectedDay: string = '';
  @Param selectedStartTime: string = '';
  @Param selectedEndTime: string = '';
  @Param isSubmitting: boolean = false;
  @Param compact: boolean = false;
  @Param onBookTap: () => void = () => {};

  private store: ShuYoAppStore = ShuYoAppStore.instance();

  private isSeatBookable(seat: ShuYoLibrarySeat): boolean {
    return !seat.isDisabled && !seat.isBusy && !seat.isBooked;
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

  private getSeatCardBorder(seat: ShuYoLibrarySeat): string {
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

  private getShortDayLabel(): string {
    if (this.selectedDay.length >= 10) {
      return this.selectedDay.substring(5);
    }
    return this.selectedDay;
  }

  private getActionButtonLabel(seat: ShuYoLibrarySeat): string {
    if (this.isSubmitting) {
      return '提交中...';
    }
    if (this.isSeatBookable(seat)) {
      return '预约此座';
    }
    return seat.isBooked ? '已预约' : '不可预约';
  }

  private getActionButtonFontColor(seat: ShuYoLibrarySeat): string {
    if (this.isSeatBookable(seat)) {
      return '#FFFFFF';
    }
    return seat.isBooked ? '#1D4ED8' : this.store.colors.textSecondary;
  }

  private getActionButtonBgColor(seat: ShuYoLibrarySeat): string {
    if (this.isSeatBookable(seat)) {
      return '#16A34A';
    }
    return seat.isBooked ? '#DBEAFE' : this.store.colors.surfaceAlt;
  }

  private getActionButtonBorderColor(seat: ShuYoLibrarySeat): string {
    return seat.isBooked ? '#93C5FD' : this.store.colors.border;
  }

  private buildMatrixNeighborText(pt: ShuYoFloorPlanPoint): string {
    const parts: string[] = [];
    if (pt.leftNeighbor !== undefined) {
      parts.push(`连号前位 ${pt.leftNeighbor.label} ${pt.leftNeighbor.statusText}`);
    }
    if (pt.rightNeighbor !== undefined) {
      parts.push(`连号后位 ${pt.rightNeighbor.label} ${pt.rightNeighbor.statusText}`);
    }
    if (parts.length === 0) {
      return '暂无连号相邻席位信息（以现场桌位为准）';
    }
    return `${parts.join(' · ')}（以现场桌位为准）`;
  }

  private formatNeighborText(prefix: string, summary: ShuYoSeatNeighborSummary): string {
    return `${prefix} ${summary.label} ${summary.statusText}`;
  }

  build() {
    Column() {
      if (this.point !== undefined) {
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(this.point.normalizedCode)
                  .fontSize(this.compact ? 16 : 17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)

                if (this.point.isQuiet) {
                  Text('✨ 邻座皆空')
                    .fontSize(10.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#065F46')
                    .backgroundColor('#D1FAE5')
                    .borderRadius(8)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                } else if (this.isSeatBookable(this.point.seat) &&
                  (this.point.leftNeighbor !== undefined || this.point.rightNeighbor !== undefined)) {
                  Text('邻座有人')
                    .fontSize(10.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#92400E')
                    .backgroundColor('#FEF3C7')
                    .borderRadius(8)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                }

                Text(this.getSeatStatusLabel(this.point.seat))
                  .fontSize(10.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getSeatCardText(this.point.seat))
              }

              Text(`${this.point.zoneHint} · ${this.getShortDayLabel()} ${this.selectedStartTime}-${this.selectedEndTime}`)
                .fontSize(11.5)
                .fontColor(this.store.colors.textTertiary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(this.getActionButtonLabel(this.point.seat))
              .height(36)
              .fontSize(13)
              .enabled(this.isSeatBookable(this.point.seat) && !this.isSubmitting)
              .fontColor(this.getActionButtonFontColor(this.point.seat))
              .backgroundColor(this.getActionButtonBgColor(this.point.seat))
              .border(this.isSeatBookable(this.point.seat)
                ? { width: 0 }
                : { width: 1, color: this.getActionButtonBorderColor(this.point.seat) })
              .borderRadius(10)
              .padding({ left: 14, right: 14 })
              .clickEffect(ShuYoMotion.lightClick)
              .onClick(() => {
                this.onBookTap();
              })
          }
          .width('100%')

          if (this.point.isRealFloorPlan) {
            if (this.point.leftNeighbor !== undefined ||
              this.point.rightNeighbor !== undefined ||
              this.point.oppositeNeighbor !== undefined) {
              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
                if (this.point.leftNeighbor !== undefined) {
                  Text(this.formatNeighborText('左邻', this.point.leftNeighbor))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.point.leftNeighbor.isFree ? '#15803D' : '#B91C1C')
                    .backgroundColor(this.point.leftNeighbor.isFree ? '#DCFCE7' : '#FEE2E2')
                    .borderRadius(8)
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                }
                if (this.point.rightNeighbor !== undefined) {
                  Text(this.formatNeighborText('右邻', this.point.rightNeighbor))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.point.rightNeighbor.isFree ? '#15803D' : '#B91C1C')
                    .backgroundColor(this.point.rightNeighbor.isFree ? '#DCFCE7' : '#FEE2E2')
                    .borderRadius(8)
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                }
                if (this.point.oppositeNeighbor !== undefined) {
                  Text(this.formatNeighborText('对面', this.point.oppositeNeighbor))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.point.oppositeNeighbor.isFree ? '#15803D' : '#B91C1C')
                    .backgroundColor(this.point.oppositeNeighbor.isFree ? '#DCFCE7' : '#FEE2E2')
                    .borderRadius(8)
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                }
              }
              .width('100%')
            } else {
              Text('独立圆台席位 · 无贴靠邻座')
                .fontSize(11)
                .fontColor('#059669')
            }
          } else {
            Text(this.buildMatrixNeighborText(this.point))
              .fontSize(11)
              .fontColor(this.store.colors.textSecondary)
          }
        }
        .width('100%')
        .padding(this.compact ? 12 : 14)
        .borderRadius(16)
        .backgroundColor(this.compact ? this.store.colors.surfaceAlt : Color.Transparent)
        .backgroundEffect(this.compact ? { radius: 0 } : ShuYoGlass.floatingCardBlur(this.store.colors.isDark))
        .border({ width: 1.4, color: this.getSeatCardBorder(this.point.seat) })
        .shadow(this.compact ? ShadowStyle.OUTER_DEFAULT_XS : ShadowStyle.OUTER_DEFAULT_SM)
        .transition(ShuYoMotion.sheetCardTransition())
      }
    }
    .width('100%')
  }
}
