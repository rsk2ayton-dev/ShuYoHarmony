import {
  ShuYoCampusInfo,
  ShuYoCampusMapData,
  ShuYoCampusMapPlace,
  ShuYoMapFact
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
        backgroundColor: JsonHelpers.str(cObj, 'backgroundColor', '#EAEADF')
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
