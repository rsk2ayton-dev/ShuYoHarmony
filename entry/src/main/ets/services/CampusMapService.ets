import {
  ShuYoCampusInfo,
  ShuYoCampusMapData,
  ShuYoCampusMapPlace,
  ShuYoMapCoordinate,
  ShuYoMapFact,
  ShuYoMapGeoTransform,
  ShuYoMapLocationPoint
} from '../models/ShuYoModels';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

export class CampusMapService {
  private static cachedData: ShuYoCampusMapData | undefined = undefined;

  static loadMapData(): ShuYoCampusMapData {
    if (CampusMapService.cachedData !== undefined) {
      return CampusMapService.cachedData;
    }
    const raw = RawFileService.readText('campus_map/map_data.json');
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      return { version: '0', campuses: [], places: [] };
    }

    const campuses: ShuYoCampusInfo[] = [];
    const rawCampuses = JsonHelpers.asArray(obj['campuses']);
    for (let i = 0; i < rawCampuses.length; i++) {
      const cObj = JsonHelpers.asObject(rawCampuses[i]);
      if (cObj === undefined) {
        continue;
      }
      const rawAsset = JsonHelpers.str(cObj, 'asset');
      const assetPath = rawAsset.startsWith('assets/') ? rawAsset.substring(7) : rawAsset;
      const vbRaw = JsonHelpers.asArray(cObj['viewBox']);
      const viewBox: number[] = [];
      for (let v = 0; v < vbRaw.length; v++) {
        viewBox.push(Number(vbRaw[v]) || 0);
      }
      const ivObj = JsonHelpers.asObject(cObj['initialView']);
      const centerObj = JsonHelpers.asObject(ivObj !== undefined ? ivObj['center'] : undefined);
      const gtObj = JsonHelpers.asObject(cObj['geoTransform']);
      const mpuObj = JsonHelpers.asObject(cObj['metersPerMapUnit']);
      const hasGeoTransform = gtObj !== undefined && mpuObj !== undefined;
      const geoTransform: ShuYoMapGeoTransform = {
        a: JsonHelpers.num(gtObj, 'a', 0),
        b: JsonHelpers.num(gtObj, 'b', 0),
        c: JsonHelpers.num(gtObj, 'c', 0),
        d: JsonHelpers.num(gtObj, 'd', 0),
        e: JsonHelpers.num(gtObj, 'e', 0),
        f: JsonHelpers.num(gtObj, 'f', 0)
      };
      const metersPerMapUnit = JsonHelpers.num(mpuObj, 'x', 1);

      campuses.push({
        id: JsonHelpers.str(cObj, 'id'),
        name: JsonHelpers.str(cObj, 'name'),
        assetPath: assetPath,
        viewBox: viewBox.length === 4 ? viewBox : [0, 0, 1000, 1000],
        initialView: {
          zoom: JsonHelpers.num(ivObj, 'zoom', 1.2),
          center: {
            x: JsonHelpers.num(centerObj, 'x', 450),
            y: JsonHelpers.num(centerObj, 'y', 450)
          }
        },
        backgroundColor: JsonHelpers.str(cObj, 'backgroundColor', '#EAEADF'),
        hasGeoTransform: hasGeoTransform && metersPerMapUnit > 0,
        geoTransform: geoTransform,
        metersPerMapUnit: metersPerMapUnit > 0 ? metersPerMapUnit : 1
      });
    }

    const places: ShuYoCampusMapPlace[] = [];
    const rawPlaces = JsonHelpers.asArray(obj['places']);
    for (let i = 0; i < rawPlaces.length; i++) {
      const pObj = JsonHelpers.asObject(rawPlaces[i]);
      if (pObj === undefined) {
        continue;
      }
      const factsRaw = JsonHelpers.asArray(pObj['facts']);
      const facts: ShuYoMapFact[] = [];
      for (let f = 0; f < factsRaw.length; f++) {
        const fObj = JsonHelpers.asObject(factsRaw[f]);
        if (fObj !== undefined) {
          facts.push({
            factLabel: JsonHelpers.str(fObj, 'label'),
            factValue: JsonHelpers.str(fObj, 'value')
          });
        }
      }
      const ptObj = JsonHelpers.asObject(pObj['point']);
      places.push({
        id: JsonHelpers.str(pObj, 'id'),
        campusId: JsonHelpers.str(pObj, 'campusId'),
        name: JsonHelpers.str(pObj, 'name'),
        kind: JsonHelpers.str(pObj, 'kind'),
        address: JsonHelpers.str(pObj, 'address'),
        description: JsonHelpers.str(pObj, 'description'),
        aliases: JsonHelpers.strList(pObj, 'aliases'),
        featureIds: JsonHelpers.strList(pObj, 'featureIds'),
        facts: facts,
        hasPoint: ptObj !== undefined,
        pointX: JsonHelpers.num(ptObj, 'x', 0),
        pointY: JsonHelpers.num(ptObj, 'y', 0)
      });
    }

    const result: ShuYoCampusMapData = {
      version: JsonHelpers.str(obj, 'version', '1.0'),
      campuses: campuses,
      places: places
    };
    CampusMapService.cachedData = result;
    return result;
  }

  static readCampusSvg(assetPath: string): string {
    return RawFileService.readText(assetPath);
  }

  /**
   * Matches upstream SHUMap / ShuYo WGS-84 -> GCJ-02 conversion before applying SVG affine matrix.
   */
  static wgs84ToGcj02(longitude: number, latitude: number): ShuYoMapCoordinate {
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude) ||
      Math.abs(longitude) > 180 || Math.abs(latitude) > 90) {
      return { longitude: longitude, latitude: latitude };
    }
    if (longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271) {
      return { longitude: longitude, latitude: latitude };
    }
    const a = 6378245.0;
    const ee = 0.006693421622965943;
    const x = longitude - 105.0;
    const y = latitude - 35.0;
    const common = (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    let dLat = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    let dLng = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    dLat += common +
      (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0 +
      (160.0 * Math.sin(y / 12.0 * Math.PI) + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
    dLng += common +
      (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0 +
      (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
    const radLat = latitude / 180.0 * Math.PI;
    const magic = 1.0 - ee * Math.pow(Math.sin(radLat), 2);
    const sqrtMagic = Math.sqrt(magic);
    dLat = dLat * 180.0 / ((a * (1.0 - ee)) / (magic * sqrtMagic) * Math.PI);
    dLng = dLng * 180.0 / (a / sqrtMagic * Math.cos(radLat) * Math.PI);
    return {
      longitude: longitude + dLng,
      latitude: latitude + dLat
    };
  }

  static projectWgs84ToCampus(
    campus: ShuYoCampusInfo,
    longitude: number,
    latitude: number,
    accuracyMeters: number
  ): ShuYoMapLocationPoint | undefined {
    if (!campus.hasGeoTransform || campus.viewBox.length < 4) {
      return undefined;
    }
    const gcj = CampusMapService.wgs84ToGcj02(longitude, latitude);
    const t = campus.geoTransform;
    const px = t.a * gcj.longitude + t.b * gcj.latitude + t.c;
    const py = t.d * gcj.longitude + t.e * gcj.latitude + t.f;
    const minX = campus.viewBox[0];
    const minY = campus.viewBox[1];
    const maxX = minX + campus.viewBox[2];
    const maxY = minY + campus.viewBox[3];
    if (px < minX || px > maxX || py < minY || py > maxY) {
      return undefined;
    }
    const acc = Number.isFinite(accuracyMeters) && accuracyMeters > 0 && campus.metersPerMapUnit > 0
      ? accuracyMeters / campus.metersPerMapUnit
      : 0;
    return {
      x: px,
      y: py,
      accuracy: acc
    };
  }

  static findCampusAtWgs84(
    campuses: ShuYoCampusInfo[],
    longitude: number,
    latitude: number
  ): ShuYoCampusInfo | undefined {
    for (let i = 0; i < campuses.length; i++) {
      const pt = CampusMapService.projectWgs84ToCampus(campuses[i], longitude, latitude, 0);
      if (pt !== undefined) {
        return campuses[i];
      }
    }
    return undefined;
  }

  static searchPlaces(
    places: ShuYoCampusMapPlace[],
    campusId: string,
    query: string
  ): ShuYoCampusMapPlace[] {
    const q = query.trim().toLowerCase();
    const out: ShuYoCampusMapPlace[] = [];
    for (let i = 0; i < places.length; i++) {
      const p = places[i];
      if (p.campusId !== campusId) {
        continue;
      }
      if (q.length === 0) {
        out.push(p);
        continue;
      }
      const hay = `${p.name} ${p.kind} ${p.address} ${p.description} ${p.aliases.join(' ')}`.toLowerCase();
      if (hay.includes(q)) {
        out.push(p);
      }
    }
    return out;
  }
}
