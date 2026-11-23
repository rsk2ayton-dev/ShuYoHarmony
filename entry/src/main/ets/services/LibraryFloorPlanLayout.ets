import { ShuYoLibrarySeat } from '../models/ShuYoModels';

export interface ShuYoFloorPlanPoint {
  seat: ShuYoLibrarySeat;
  nx: number;
  ny: number;
  zoneHint: string;
}

export interface ShuYoReadingDeskRect {
  x: number;
  y: number;
  w: number;
  h: number;
  label: string;
}

export interface ShuYoReadingRoomLayout {
  aspectRatio: number;
  desks: ShuYoReadingDeskRect[];
  points: ShuYoFloorPlanPoint[];
}

interface ParsedSeatCode {
  prefix: string;
  num: number;
}

/**
 * Computes calibrated floor-plan coordinates for:
 * 1) 24H Study Space circular floor plan (rawfile/library_booking/seats.jpg, 1680x1188)
 * 2) Architectural reading-room table clusters for all other venues.
 */
export class LibraryFloorPlanLayout {
  static readonly studyMapWidth: number = 1680;
  static readonly studyMapHeight: number = 1188;
  static readonly studyMapAspectRatio: number = 1680 / 1188;
  private static readonly ringCenterX: number = 778;
  private static readonly ringCenterY: number = 622;

  private static parseCircularCode(label: string): ParsedSeatCode | undefined {
    const trimmed = label.trim();
    const m = new RegExp('^([ABC])-?(\\d{1,3})$', 'i').exec(trimmed) ??
      new RegExp('([ABC])-?(\\d{1,3})$', 'i').exec(trimmed);
    if (m === null) {
      return undefined;
    }
    const num = parseInt(m[2], 10);
    if (!Number.isFinite(num) || num <= 0) {
      return undefined;
    }
    return {
      prefix: m[1].toUpperCase(),
      num: num
    };
  }

  static isCircularStudySeatLabel(label: string): boolean {
    return LibraryFloorPlanLayout.parseCircularCode(label) !== undefined;
  }

  static canUseCircularStudyMap(venueId: string, seats: ShuYoLibrarySeat[]): boolean {
    if (venueId !== 'studySpace' || seats.length === 0) {
      return false;
    }
    let matched = 0;
    for (let i = 0; i < seats.length; i++) {
      if (LibraryFloorPlanLayout.isCircularStudySeatLabel(seats[i].seatLabel)) {
        matched++;
      }
    }
    return matched * 10 >= seats.length * 7;
  }

  private static polarPoint(
    seat: ShuYoLibrarySeat,
    radius: number,
    deg: number,
    zoneHint: string
  ): ShuYoFloorPlanPoint {
    const rad = deg * Math.PI / 180.0;
    const px = LibraryFloorPlanLayout.ringCenterX + radius * Math.cos(rad);
    const py = LibraryFloorPlanLayout.ringCenterY + radius * Math.sin(rad);
    return {
      seat: seat,
      nx: px / LibraryFloorPlanLayout.studyMapWidth,
      ny: py / LibraryFloorPlanLayout.studyMapHeight,
      zoneHint: zoneHint
    };
  }

  private static lerpArc(
    seat: ShuYoLibrarySeat,
    num: number,
    startNum: number,
    endNum: number,
    radius: number,
    startDeg: number,
    endDeg: number,
    zoneHint: string
  ): ShuYoFloorPlanPoint {
    const span = Math.max(1, endNum - startNum);
    const t = Math.max(0, Math.min(1, (num - startNum) / span));
    const deg = startDeg + (endDeg - startDeg) * t;
    return LibraryFloorPlanLayout.polarPoint(seat, radius, deg, zoneHint);
  }

  static mapStudySpaceSeat(seat: ShuYoLibrarySeat, fallbackIndex: number = 0): ShuYoFloorPlanPoint {
    const parsed = LibraryFloorPlanLayout.parseCircularCode(seat.seatLabel);
    if (parsed !== undefined) {
      const p = parsed.prefix;
      const n = parsed.num;
      if (p === 'A') {
        if (n >= 1 && n <= 7) {
          const t = (n - 1) / 6.0;
          const px = 1360 + (1115 - 1360) * t;
          const py = 232 + (368 - 232) * t;
          return {
            seat: seat,
            nx: px / LibraryFloorPlanLayout.studyMapWidth,
            ny: py / LibraryFloorPlanLayout.studyMapHeight,
            zoneHint: 'A区 · 2号门走廊'
          };
        }
        if (n >= 8 && n <= 18) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 8, 18, 376, 38, 124, 'A区 · 南侧外环');
        }
      } else if (p === 'B') {
        if (n >= 1 && n <= 43) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 1, 43, 376, -37, -180, 'B区 · 北侧最外环');
        }
        if (n >= 44 && n <= 51) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 44, 51, 319, -35, -68, 'B区 · 东北中环外侧');
        }
        if (n >= 52 && n <= 59) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 52, 59, 319, -74, -106, 'B区 · 正北中环外侧');
        }
        if (n >= 60 && n <= 67) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 60, 67, 319, -112.5, -144, 'B区 · 西北中环外侧');
        }
        if (n >= 68 && n <= 77) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 68, 77, 319, -149.5, -185.5, 'B区 · 西侧中环外侧');
        }
        if (n >= 78 && n <= 97) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 78, 97, 322, 133, 53, 'B区 · 南侧中环外侧');
        }
        if (n >= 98 && n <= 107) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 98, 107, 320, 10, -26.5, 'B区 · 东侧中环外侧');
        }
        if (n >= 108 && n <= 115) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 108, 115, 292, -35, -68, 'B区 · 东北中环内侧');
        }
        if (n >= 116 && n <= 123) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 116, 123, 292, -74, -106, 'B区 · 正北中环内侧');
        }
        if (n >= 124 && n <= 131) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 124, 131, 292, -112, -144, 'B区 · 西北中环内侧');
        }
        if (n >= 132 && n <= 141) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 132, 141, 292, -150, -185, 'B区 · 西侧中环内侧');
        }
        if (n >= 142 && n <= 161) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 142, 161, 294, 132, 52.6, 'B区 · 南侧中环内侧');
        }
        if (n >= 162 && n <= 171) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 162, 171, 291, 10, -25.7, 'B区 · 东侧中环内侧');
        }
      } else if (p === 'C') {
        if (n >= 1 && n <= 54) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 1, 54, 180, -17.5, -357.4, 'C区 · 内圈外环');
        }
        if (n >= 55 && n <= 94) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 55, 94, 134, -16.5, -354.9, 'C区 · 内圈中环');
        }
        if (n >= 95 && n <= 108) {
          return LibraryFloorPlanLayout.lerpArc(seat, n, 95, 108, 73, -36, -309.4, 'C区 · 核心内环');
        }
        if (n === 109) {
          return LibraryFloorPlanLayout.polarPoint(seat, 26, -31, 'C区 · 中心圆台');
        }
      }
    }

    const col = fallbackIndex % 8;
    const row = Math.floor(fallbackIndex / 8);
    return {
      seat: seat,
      nx: 0.08 + col * 0.045,
      ny: 0.86 + (row % 3) * 0.04,
      zoneHint: '24H学习空间 · 附加席位'
    };
  }

  static buildStudySpacePoints(seats: ShuYoLibrarySeat[]): ShuYoFloorPlanPoint[] {
    const out: ShuYoFloorPlanPoint[] = [];
    for (let i = 0; i < seats.length; i++) {
      out.push(LibraryFloorPlanLayout.mapStudySpaceSeat(seats[i], i));
    }
    return out;
  }

  static buildReadingRoomLayout(seats: ShuYoLibrarySeat[]): ShuYoReadingRoomLayout {
    const total = seats.length;
    if (total === 0) {
      return {
        aspectRatio: 1.35,
        desks: [],
        points: []
      };
    }

    const cols = total <= 16 ? 2 : (total <= 36 ? 3 : (total <= 64 ? 4 : 5));
    const deskCount = Math.ceil(total / 4);
    const rows = Math.max(1, Math.ceil(deskCount / cols));

    const sideMargin = 0.07;
    const topMargin = 0.15;
    const bottomMargin = 0.14;
    const usableW = 1.0 - sideMargin * 2;
    const usableH = 1.0 - topMargin - bottomMargin;
    const cellW = usableW / cols;
    const cellH = usableH / rows;

    const desks: ShuYoReadingDeskRect[] = [];
    const points: ShuYoFloorPlanPoint[] = [];

    for (let d = 0; d < deskCount; d++) {
      const col = d % cols;
      const row = Math.floor(d / cols);
      const cx = sideMargin + (col + 0.5) * cellW;
      const cy = topMargin + (row + 0.5) * cellH;
      const deskW = cellW * 0.74;
      const deskH = cellH * 0.28;
      desks.push({
        x: cx - deskW / 2,
        y: cy - deskH / 2,
        w: deskW,
        h: deskH,
        label: `桌${d + 1}`
      });

      const baseSeatIdx = d * 4;
      const slotOffsetsX: number[] = [-deskW * 0.26, deskW * 0.26, -deskW * 0.26, deskW * 0.26];
      const slotOffsetsY: number[] = [-deskH * 0.96, -deskH * 0.96, deskH * 0.96, deskH * 0.96];
      const slotHints: string[] = ['靠北上侧位', '靠北上侧位', '靠南下侧位', '靠南下侧位'];
      for (let s = 0; s < 4; s++) {
        const seatIdx = baseSeatIdx + s;
        if (seatIdx >= total) {
          break;
        }
        points.push({
          seat: seats[seatIdx],
          nx: cx + slotOffsetsX[s],
          ny: cy + slotOffsetsY[s],
          zoneHint: `第${row + 1}排 · 桌${d + 1}（${slotHints[s]}）`
        });
      }
    }

    const aspectRatio = Math.min(1.42, Math.max(0.8, (cols * 1.1) / Math.max(1.25, rows * 1.05)));
    return {
      aspectRatio: aspectRatio,
      desks: desks,
      points: points
    };
  }
}
