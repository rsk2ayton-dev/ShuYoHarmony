import { ShuYoLibrarySeat } from '../models/ShuYoModels';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

export interface ShuYoSeatNeighborSummary {
  label: string;
  isFree: boolean;
  statusText: string;
}

export interface ShuYoFloorPlanPoint {
  seat: ShuYoLibrarySeat;
  normalizedCode: string;
  nx: number;
  ny: number;
  facingDeg: number;
  zoneHint: string;
  isQuiet: boolean;
  leftNeighbor?: ShuYoSeatNeighborSummary;
  rightNeighbor?: ShuYoSeatNeighborSummary;
  oppositeNeighbor?: ShuYoSeatNeighborSummary;
  isRealFloorPlan: boolean;
}

export interface ShuYoFloorPlanSegment {
  id: string;
  type: string;
  prefix: string;
  startNum: number;
  endNum: number;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  radius: number;
  startDeg: number;
  endDeg: number;
  facingMode: string;
  facingDeg: number;
  oppositePrefix: string;
  oppositeOffset: number;
  zoneHint: string;
}

export interface ShuYoFloorPlanConfig {
  venueId: string;
  imageAsset: string;
  imageWidth: number;
  imageHeight: number;
  ringCenterX: number;
  ringCenterY: number;
  segments: ShuYoFloorPlanSegment[];
}

interface ParsedSeatCode {
  prefix: string;
  num: number;
}

interface MappedSegmentSeat {
  pointIdx: number;
  num: number;
  deg: number;
  segment: ShuYoFloorPlanSegment;
}

/**
 * Loads JSON-calibrated real floor plans when available and computes cinema-style
 * seat coordinates + physical neighbor intelligence; otherwise falls back to an
 * honest sequential-number matrix layout without inventing fake physical tables.
 */
export class LibraryFloorPlanLayout {
  static readonly defaultStudyAsset: string = 'library_booking/floor_plans/study_space.json';

  private static readonly venueFloorPlanRegistry: Map<string, string> =
    LibraryFloorPlanLayout.buildRegistry();
  private static readonly configCache: Map<string, ShuYoFloorPlanConfig> =
    new Map<string, ShuYoFloorPlanConfig>();

  private static buildRegistry(): Map<string, string> {
    const reg = new Map<string, string>();
    reg.set('studySpace', LibraryFloorPlanLayout.defaultStudyAsset);
    return reg;
  }

  static registerVenueFloorPlan(venueId: string, rawAssetPath: string): void {
    LibraryFloorPlanLayout.venueFloorPlanRegistry.set(venueId, rawAssetPath);
    LibraryFloorPlanLayout.configCache.delete(venueId);
  }

  static getFloorPlanConfig(venueId: string): ShuYoFloorPlanConfig | undefined {
    const cached = LibraryFloorPlanLayout.configCache.get(venueId);
    if (cached !== undefined) {
      return cached;
    }
    const assetPath = LibraryFloorPlanLayout.venueFloorPlanRegistry.get(venueId);
    if (assetPath === undefined || assetPath.length === 0) {
      return undefined;
    }
    const rawText = RawFileService.readText(assetPath);
    if (rawText.length === 0) {
      return undefined;
    }
    const root = JsonHelpers.parseObject(rawText);
    if (root === undefined) {
      return undefined;
    }
    const rawSegs = JsonHelpers.asArray(root['segments']);
    const segments: ShuYoFloorPlanSegment[] = [];
    for (let i = 0; i < rawSegs.length; i++) {
      const sObj = JsonHelpers.asObject(rawSegs[i]);
      if (sObj === undefined) {
        continue;
      }
      segments.push({
        id: JsonHelpers.str(sObj, 'id', ''),
        type: JsonHelpers.str(sObj, 'type', 'arc'),
        prefix: JsonHelpers.str(sObj, 'prefix', '').toUpperCase(),
        startNum: JsonHelpers.num(sObj, 'startNum', 1),
        endNum: JsonHelpers.num(sObj, 'endNum', 1),
        x1: JsonHelpers.num(sObj, 'x1', 0),
        y1: JsonHelpers.num(sObj, 'y1', 0),
        x2: JsonHelpers.num(sObj, 'x2', 0),
        y2: JsonHelpers.num(sObj, 'y2', 0),
        radius: JsonHelpers.num(sObj, 'radius', 0),
        startDeg: JsonHelpers.num(sObj, 'startDeg', 0),
        endDeg: JsonHelpers.num(sObj, 'endDeg', 0),
        facingMode: JsonHelpers.str(sObj, 'facingMode', ''),
        facingDeg: JsonHelpers.num(sObj, 'facingDeg', -90),
        oppositePrefix: JsonHelpers.str(sObj, 'oppositePrefix', '').toUpperCase(),
        oppositeOffset: JsonHelpers.num(sObj, 'oppositeOffset', 0),
        zoneHint: JsonHelpers.str(sObj, 'zoneHint', '')
      });
    }
    const cfg: ShuYoFloorPlanConfig = {
      venueId: JsonHelpers.str(root, 'venueId', venueId),
      imageAsset: JsonHelpers.str(root, 'imageAsset', 'library_booking/seats.jpg'),
      imageWidth: Math.max(1, JsonHelpers.num(root, 'imageWidth', 1680)),
      imageHeight: Math.max(1, JsonHelpers.num(root, 'imageHeight', 1188)),
      ringCenterX: JsonHelpers.num(root, 'ringCenterX', 776.6),
      ringCenterY: JsonHelpers.num(root, 'ringCenterY', 631.0),
      segments: segments
    };
    LibraryFloorPlanLayout.configCache.set(venueId, cfg);
    return cfg;
  }

  static getFloorPlanImageAsset(venueId: string): string {
    const cfg = LibraryFloorPlanLayout.getFloorPlanConfig(venueId);
    return cfg !== undefined ? cfg.imageAsset : '';
  }

  static getFloorPlanAspectRatio(venueId: string): number {
    const cfg = LibraryFloorPlanLayout.getFloorPlanConfig(venueId);
    if (cfg === undefined || cfg.imageHeight <= 0) {
      return 1680 / 1188;
    }
    return cfg.imageWidth / cfg.imageHeight;
  }

  private static extractZoneLetter(areaName: string): string {
    const upper = areaName.toUpperCase();
    const m = new RegExp('(?:^|[^A-Z])([ABC])(?:区|[^A-Z]|$)').exec(upper);
    return m !== null ? m[1] : '';
  }

  static normalizeSeatCode(seatLabel: string, areaName: string): ParsedSeatCode | undefined {
    const trimmed = seatLabel.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    const prefixed = new RegExp('^([ABC])-?(\\d{1,3})$', 'i').exec(trimmed) ??
      new RegExp('([ABC])-?(\\d{1,3})$', 'i').exec(trimmed);
    if (prefixed !== null) {
      const n = parseInt(prefixed[2], 10);
      if (Number.isFinite(n) && n > 0) {
        return { prefix: prefixed[1].toUpperCase(), num: n };
      }
      return undefined;
    }

    const digitsOnly = new RegExp('^0*(\\d{1,3})$').exec(trimmed);
    if (digitsOnly !== null) {
      const zoneLetter = LibraryFloorPlanLayout.extractZoneLetter(areaName);
      if (zoneLetter.length > 0) {
        const n = parseInt(digitsOnly[1], 10);
        if (Number.isFinite(n) && n > 0) {
          return { prefix: zoneLetter, num: n };
        }
      }
    }
    return undefined;
  }

  static formatNormalizedCode(prefix: string, num: number): string {
    let digits = `${num}`;
    while (digits.length < 3) {
      digits = `0${digits}`;
    }
    return `${prefix}${digits}`;
  }

  static isSeatFree(seat: ShuYoLibrarySeat): boolean {
    return !seat.isDisabled && !seat.isBusy && !seat.isBooked;
  }

  private static summarizeSeat(seat: ShuYoLibrarySeat, displayLabel: string): ShuYoSeatNeighborSummary {
    const isFree = LibraryFloorPlanLayout.isSeatFree(seat);
    let statusText = '空闲';
    if (seat.isDisabled) {
      statusText = '停用';
    } else if (seat.isBooked) {
      statusText = '已约';
    } else if (seat.isBusy) {
      statusText = '已占';
    }
    return {
      label: displayLabel,
      isFree: isFree,
      statusText: statusText
    };
  }

  static hasRealFloorPlan(venueId: string, areaName: string, seats: ShuYoLibrarySeat[]): boolean {
    const cfg = LibraryFloorPlanLayout.getFloorPlanConfig(venueId);
    if (cfg === undefined || cfg.segments.length === 0 || seats.length === 0) {
      return false;
    }
    let matched = 0;
    for (let i = 0; i < seats.length; i++) {
      const parsed = LibraryFloorPlanLayout.normalizeSeatCode(seats[i].seatLabel, areaName);
      if (parsed !== undefined && LibraryFloorPlanLayout.findSegment(cfg, parsed.prefix, parsed.num) !== undefined) {
        matched++;
      }
    }
    return matched * 10 >= seats.length * 7;
  }

  private static findSegment(
    cfg: ShuYoFloorPlanConfig,
    prefix: string,
    num: number
  ): ShuYoFloorPlanSegment | undefined {
    for (let i = 0; i < cfg.segments.length; i++) {
      const seg = cfg.segments[i];
      if (seg.prefix === prefix && num >= seg.startNum && num <= seg.endNum) {
        return seg;
      }
    }
    return undefined;
  }

  private static shortestAngleDiff(degA: number, degB: number): number {
    let diff = (degA - degB) % 360;
    if (diff > 180) {
      diff -= 360;
    }
    if (diff < -180) {
      diff += 360;
    }
    return Math.abs(diff);
  }

  static buildRealFloorPlanPoints(
    venueId: string,
    areaName: string,
    seats: ShuYoLibrarySeat[]
  ): ShuYoFloorPlanPoint[] {
    const cfg = LibraryFloorPlanLayout.getFloorPlanConfig(venueId);
    if (cfg === undefined) {
      return LibraryFloorPlanLayout.buildSequentialMatrixPoints(areaName, seats);
    }

    const out: ShuYoFloorPlanPoint[] = [];
    const codeToIdx = new Map<string, number>();
    const mappedList: MappedSegmentSeat[] = [];
    const cOuterIndices: MappedSegmentSeat[] = [];
    const cInnerIndices: MappedSegmentSeat[] = [];
    let unmappedFallbackIdx = 0;

    for (let i = 0; i < seats.length; i++) {
      const seat = seats[i];
      const parsed = LibraryFloorPlanLayout.normalizeSeatCode(seat.seatLabel, areaName);
      const seg = parsed !== undefined
        ? LibraryFloorPlanLayout.findSegment(cfg, parsed.prefix, parsed.num)
        : undefined;

      if (parsed !== undefined && seg !== undefined) {
        const span = Math.max(1, seg.endNum - seg.startNum);
        const t = seg.endNum === seg.startNum
          ? 0.0
          : Math.max(0.0, Math.min(1.0, (parsed.num - seg.startNum) / span));

        let px = seg.x1;
        let py = seg.y1;
        let facingDeg = seg.facingDeg;
        let deg = 0;

        if (seg.type === 'line') {
          px = seg.x1 + (seg.x2 - seg.x1) * t;
          py = seg.y1 + (seg.y2 - seg.y1) * t;
          deg = Math.atan2(py - cfg.ringCenterY, px - cfg.ringCenterX) * 180.0 / Math.PI;
        } else if (seg.type === 'arc') {
          deg = seg.startDeg + (seg.endDeg - seg.startDeg) * t;
          const rad = deg * Math.PI / 180.0;
          px = cfg.ringCenterX + seg.radius * Math.cos(rad);
          py = cfg.ringCenterY + seg.radius * Math.sin(rad);
          if (seg.facingMode === 'outward') {
            facingDeg = deg;
          } else if (seg.facingMode === 'inward') {
            facingDeg = deg + 180.0;
          }
        } else {
          deg = Math.atan2(py - cfg.ringCenterY, px - cfg.ringCenterX) * 180.0 / Math.PI;
        }

        const code = LibraryFloorPlanLayout.formatNormalizedCode(parsed.prefix, parsed.num);
        const pointIdx = out.length;
        out.push({
          seat: seat,
          normalizedCode: code,
          nx: px / cfg.imageWidth,
          ny: py / cfg.imageHeight,
          facingDeg: facingDeg,
          zoneHint: seg.zoneHint,
          isQuiet: LibraryFloorPlanLayout.isSeatFree(seat),
          isRealFloorPlan: true
        });
        codeToIdx.set(code, pointIdx);

        const mapped: MappedSegmentSeat = {
          pointIdx: pointIdx,
          num: parsed.num,
          deg: deg,
          segment: seg
        };
        mappedList.push(mapped);
        if (seg.id.startsWith('C-out-')) {
          cOuterIndices.push(mapped);
        } else if (seg.id.startsWith('C-in-')) {
          cInnerIndices.push(mapped);
        }
      } else {
        const col = unmappedFallbackIdx % 8;
        const row = Math.floor(unmappedFallbackIdx / 8);
        unmappedFallbackIdx++;
        out.push({
          seat: seat,
          normalizedCode: seat.seatLabel,
          nx: 0.08 + col * 0.045,
          ny: 0.86 + (row % 3) * 0.04,
          facingDeg: -90,
          zoneHint: areaName.length > 0 ? `${areaName} · 附加席位` : '附加席位',
          isQuiet: LibraryFloorPlanLayout.isSeatFree(seat),
          isRealFloorPlan: true
        });
      }
    }

    // Populate physical left/right neighbors strictly within same segment & opposite neighbors
    for (let i = 0; i < mappedList.length; i++) {
      const item = mappedList[i];
      const pt = out[item.pointIdx];
      const seg = item.segment;

      if (item.num - 1 >= seg.startNum) {
        const leftCode = LibraryFloorPlanLayout.formatNormalizedCode(seg.prefix, item.num - 1);
        const leftIdx = codeToIdx.get(leftCode);
        if (leftIdx !== undefined) {
          pt.leftNeighbor = LibraryFloorPlanLayout.summarizeSeat(out[leftIdx].seat, out[leftIdx].normalizedCode);
        }
      }
      if (item.num + 1 <= seg.endNum) {
        const rightCode = LibraryFloorPlanLayout.formatNormalizedCode(seg.prefix, item.num + 1);
        const rightIdx = codeToIdx.get(rightCode);
        if (rightIdx !== undefined) {
          pt.rightNeighbor = LibraryFloorPlanLayout.summarizeSeat(out[rightIdx].seat, out[rightIdx].normalizedCode);
        }
      }

      if (seg.oppositePrefix.length > 0 && seg.oppositeOffset !== 0) {
        const oppCode = LibraryFloorPlanLayout.formatNormalizedCode(
          seg.oppositePrefix,
          item.num + seg.oppositeOffset
        );
        const oppIdx = codeToIdx.get(oppCode);
        if (oppIdx !== undefined) {
          pt.oppositeNeighbor = LibraryFloorPlanLayout.summarizeSeat(out[oppIdx].seat, out[oppIdx].normalizedCode);
        }
      } else if (seg.id.startsWith('C-out-') && cInnerIndices.length > 0) {
        let bestOpp: MappedSegmentSeat | undefined = undefined;
        let bestDiff = 22.0;
        for (let k = 0; k < cInnerIndices.length; k++) {
          const cand = cInnerIndices[k];
          const diff = LibraryFloorPlanLayout.shortestAngleDiff(item.deg, cand.deg);
          if (diff < bestDiff) {
            bestDiff = diff;
            bestOpp = cand;
          }
        }
        if (bestOpp !== undefined) {
          const oppPt = out[bestOpp.pointIdx];
          pt.oppositeNeighbor = LibraryFloorPlanLayout.summarizeSeat(oppPt.seat, oppPt.normalizedCode);
        }
      } else if (seg.id.startsWith('C-in-') && cOuterIndices.length > 0) {
        let bestOpp: MappedSegmentSeat | undefined = undefined;
        let bestDiff = 22.0;
        for (let k = 0; k < cOuterIndices.length; k++) {
          const cand = cOuterIndices[k];
          const diff = LibraryFloorPlanLayout.shortestAngleDiff(item.deg, cand.deg);
          if (diff < bestDiff) {
            bestDiff = diff;
            bestOpp = cand;
          }
        }
        if (bestOpp !== undefined) {
          const oppPt = out[bestOpp.pointIdx];
          pt.oppositeNeighbor = LibraryFloorPlanLayout.summarizeSeat(oppPt.seat, oppPt.normalizedCode);
        }
      }

      const selfFree = LibraryFloorPlanLayout.isSeatFree(pt.seat);
      const leftOk = pt.leftNeighbor === undefined || pt.leftNeighbor.isFree;
      const rightOk = pt.rightNeighbor === undefined || pt.rightNeighbor.isFree;
      pt.isQuiet = selfFree && leftOk && rightOk;
    }

    return out;
  }

  static buildSequentialMatrixPoints(
    areaName: string,
    seats: ShuYoLibrarySeat[]
  ): ShuYoFloorPlanPoint[] {
    const total = seats.length;
    if (total === 0) {
      return [];
    }
    const cols = total <= 24 ? 8 : 10;
    const rows = Math.max(1, Math.ceil(total / cols));

    const leftPad = 0.08;
    const rightPad = 0.06;
    const topPad = 0.16;
    const bottomPad = 0.08;
    const usableW = 1.0 - leftPad - rightPad;
    const usableH = 1.0 - topPad - bottomPad;
    const cellW = usableW / cols;
    const cellH = usableH / rows;

    const out: ShuYoFloorPlanPoint[] = [];
    for (let i = 0; i < total; i++) {
      const seat = seats[i];
      const row = Math.floor(i / cols);
      const col = i % cols;
      const nx = leftPad + (col + 0.5) * cellW;
      const ny = topPad + (row + 0.5) * cellH;
      const zoneLabel = areaName.length > 0 ? areaName : '阅览室';

      const pt: ShuYoFloorPlanPoint = {
        seat: seat,
        normalizedCode: seat.seatLabel,
        nx: nx,
        ny: ny,
        facingDeg: -90,
        zoneHint: `${zoneLabel} · 第${row + 1}排 第${col + 1}列（连号排列）`,
        isQuiet: LibraryFloorPlanLayout.isSeatFree(seat),
        isRealFloorPlan: false
      };
      out.push(pt);
    }

    for (let i = 0; i < out.length; i++) {
      const pt = out[i];
      const row = Math.floor(i / cols);
      if (i - 1 >= 0 && Math.floor((i - 1) / cols) === row) {
        pt.leftNeighbor = LibraryFloorPlanLayout.summarizeSeat(out[i - 1].seat, out[i - 1].normalizedCode);
      }
      if (i + 1 < out.length && Math.floor((i + 1) / cols) === row) {
        pt.rightNeighbor = LibraryFloorPlanLayout.summarizeSeat(out[i + 1].seat, out[i + 1].normalizedCode);
      }
      const selfFree = LibraryFloorPlanLayout.isSeatFree(pt.seat);
      const leftOk = pt.leftNeighbor === undefined || pt.leftNeighbor.isFree;
      const rightOk = pt.rightNeighbor === undefined || pt.rightNeighbor.isFree;
      pt.isQuiet = selfFree && leftOk && rightOk;
    }

    return out;
  }

  static buildFloorPlanPoints(
    venueId: string,
    areaName: string,
    seats: ShuYoLibrarySeat[]
  ): ShuYoFloorPlanPoint[] {
    if (LibraryFloorPlanLayout.hasRealFloorPlan(venueId, areaName, seats)) {
      return LibraryFloorPlanLayout.buildRealFloorPlanPoints(venueId, areaName, seats);
    }
    return LibraryFloorPlanLayout.buildSequentialMatrixPoints(areaName, seats);
  }
}
