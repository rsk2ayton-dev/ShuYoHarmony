import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoClassroomBuilding,
  ShuYoClassroomCourseSlot,
  ShuYoClassroomRoom,
  ShuYoClassroomSection
} from '../models/ShuYoModels';
import { HttpClientService, ShuYoHttpResult } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';
import { ShuYoWebVpnFailure, WebVpnAuthService } from './WebVpnAuthService';
import { WebVpnProtocol } from './WebVpnProtocol';

export interface ShuYoClassroomOptions {
  buildings: ShuYoClassroomBuilding[];
  sections: ShuYoClassroomSection[];
}

export class ClassroomService {
  static loadDemoOptions(): ShuYoClassroomOptions {
    const optRaw = RawFileService.readText('demo/classroom/options.json');
    const secRaw = RawFileService.readText('demo/classroom/sections.json');
    const optObj = JsonHelpers.parseObject(optRaw);
    const secObj = JsonHelpers.parseObject(secRaw);
    return ClassroomService.parseOptions(optObj, secObj);
  }

  static loadDemoRooms(buildingId: number): ShuYoClassroomRoom[] {
    const filePath = buildingId === 303
      ? 'demo/classroom/schedule-a-2026-09-01.json'
      : 'demo/classroom/schedule-2026-09-01.json';
    const raw = RawFileService.readText(filePath);
    const obj = JsonHelpers.parseObject(raw);
    return ClassroomService.parseRooms(obj);
  }

  private static isWebVpnAuthRejection(useWebVpn: boolean, resp: ShuYoHttpResult): boolean {
    if (!useWebVpn) {
      return false;
    }
    return resp.statusCode === 401 ||
      resp.statusCode === 403 ||
      WebVpnProtocol.isWebVpnPortalRedirect(resp.statusCode, resp.location);
  }

  private static async postWithWebVpnRecovery(
    url: string,
    headers: Record<string, string>,
    body: string | undefined,
    useWebVpn: boolean
  ): Promise<ShuYoHttpResult> {
    if (useWebVpn) {
      const vpn = await WebVpnAuthService.ensureSession();
      if (vpn.failure !== ShuYoWebVpnFailure.NONE) {
        throw new Error(vpn.message);
      }
    }
    let resp = await HttpClientService.request(http.RequestMethod.POST, url, headers, body);
    if (ClassroomService.isWebVpnAuthRejection(useWebVpn, resp)) {
      WebVpnAuthService.clearSession();
      const retryVpn = await WebVpnAuthService.ensureSession();
      if (retryVpn.failure !== ShuYoWebVpnFailure.NONE) {
        throw new Error(retryVpn.message);
      }
      resp = await HttpClientService.request(http.RequestMethod.POST, url, headers, body);
    }
    return resp;
  }

  static async fetchLiveOptions(useWebVpn: boolean): Promise<ShuYoClassroomOptions> {
    const base = useWebVpn ? ShuYoConstants.classroomWebVpnBase : ShuYoConstants.classroomDirectBase;
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Referer': `${base}/`
    };
    const formResp = await ClassroomService.postWithWebVpnRecovery(
      `${base}/build/findSearchRoomSearchForm`,
      headers,
      undefined,
      useWebVpn
    );
    const secResp = await ClassroomService.postWithWebVpnRecovery(
      `${base}/course/findSection`,
      headers,
      undefined,
      useWebVpn
    );
    if (formResp.statusCode < 200 || formResp.statusCode >= 300) {
      throw new Error(`空教室请求失败 (${formResp.statusCode})`);
    }
    const formObj = JsonHelpers.parseObject(formResp.body);
    const secObj = JsonHelpers.parseObject(secResp.body);
    if (formObj === undefined) {
      throw new Error(useWebVpn ? 'WebVPN 会话未登录或已失效' : '无法连接到空教室系统');
    }
    return ClassroomService.parseOptions(formObj, secObj);
  }

  static async fetchLiveRooms(
    buildingId: number,
    dateStr: string,
    useWebVpn: boolean
  ): Promise<ShuYoClassroomRoom[]> {
    const base = useWebVpn ? ShuYoConstants.classroomWebVpnBase : ShuYoConstants.classroomDirectBase;
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'Accept': 'application/json',
      'Referer': `${base}/`
    };
    const body = `buildId=${encodeURIComponent(String(buildingId))}&courseDate=${encodeURIComponent(dateStr)}`;
    const resp = await ClassroomService.postWithWebVpnRecovery(
      `${base}/build/findBuildRoomType`,
      headers,
      body,
      useWebVpn
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`空教室查询请求失败 (${resp.statusCode})`);
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined) {
      throw new Error(useWebVpn ? 'WebVPN 会话未登录或已失效' : '空教室查询返回数据无效');
    }
    return ClassroomService.parseRooms(obj);
  }

  private static parseOptions(
    optObj: Record<string, Object> | undefined,
    secObj: Record<string, Object> | undefined
  ): ShuYoClassroomOptions {
    const buildings: ShuYoClassroomBuilding[] = [];
    const optData = JsonHelpers.asObject(optObj !== undefined ? optObj['data'] : undefined);
    const rawBuilds = JsonHelpers.asArray(optData !== undefined ? optData['buildList'] : undefined);
    for (let i = 0; i < rawBuilds.length; i++) {
      const b = JsonHelpers.asObject(rawBuilds[i]);
      if (b === undefined) {
        continue;
      }
      const id = JsonHelpers.num(b, 'id', 0);
      const name = JsonHelpers.str(b, 'name', JsonHelpers.str(b, 'text'));
      const fullName = JsonHelpers.str(b, 'fullName');
      if (id > 0 && name.length > 0) {
        const campus = ClassroomService.extractCampusName(fullName);
        buildings.push({
          id: id,
          name: name,
          fullName: fullName,
          campusName: campus
        });
      }
    }

    const sections: ShuYoClassroomSection[] = [];
    const secData = JsonHelpers.asObject(secObj !== undefined ? secObj['data'] : undefined);
    const rawSecs = JsonHelpers.asArray(secData !== undefined ? secData['section'] : undefined);
    for (let i = 0; i < rawSecs.length; i++) {
      const s = JsonHelpers.asObject(rawSecs[i]);
      if (s === undefined) {
        continue;
      }
      const idx = JsonHelpers.num(s, 'sectionIndex', 0);
      if (idx > 0) {
        sections.push({
          index: idx,
          startTime: JsonHelpers.str(s, 'startTime'),
          endTime: JsonHelpers.str(s, 'endTime')
        });
      }
    }
    sections.sort((a: ShuYoClassroomSection, b: ShuYoClassroomSection): number => a.index - b.index);
    return { buildings: buildings, sections: sections };
  }

  private static parseRooms(obj: Record<string, Object> | undefined): ShuYoClassroomRoom[] {
    const rooms: ShuYoClassroomRoom[] = [];
    const data = JsonHelpers.asObject(obj !== undefined ? obj['data'] : undefined);
    const floorList = JsonHelpers.asArray(data !== undefined ? data['floorList'] : undefined);
    for (let i = 0; i < floorList.length; i++) {
      const floor = JsonHelpers.asObject(floorList[i]);
      if (floor === undefined) {
        continue;
      }
      const floorName = JsonHelpers.str(floor, 'name', JsonHelpers.str(floor, 'text', '楼层'));
      const children = JsonHelpers.asArray(floor['children']);
      for (let j = 0; j < children.length; j++) {
        const roomObj = JsonHelpers.asObject(children[j]);
        if (roomObj === undefined) {
          continue;
        }
        const roomId = JsonHelpers.num(roomObj, 'id', j + 1);
        const roomName = JsonHelpers.str(roomObj, 'name', JsonHelpers.str(roomObj, 'text'));
        const slotsRaw = JsonHelpers.asArray(roomObj['roomCourseList']);
        const slots: ShuYoClassroomCourseSlot[] = [];
        for (let k = 0; k < slotsRaw.length; k++) {
          const sl = JsonHelpers.asObject(slotsRaw[k]);
          if (sl === undefined) {
            continue;
          }
          slots.push({
            courseName: JsonHelpers.str(sl, 'courseName'),
            teacherName: JsonHelpers.str(sl, 'teacherName'),
            startSection: JsonHelpers.num(sl, 'startSection', 0),
            endSection: JsonHelpers.num(sl, 'endSection', 0)
          });
        }
        if (roomName.length > 0) {
          rooms.push({
            id: roomId,
            name: roomName,
            floorName: floorName,
            courseSlots: slots
          });
        }
      }
    }
    return rooms;
  }

  static isRoomFreeForSections(room: ShuYoClassroomRoom, selectedSections: number[]): boolean {
    if (selectedSections.length === 0) {
      return room.courseSlots.length === 0;
    }
    for (let i = 0; i < selectedSections.length; i++) {
      const sec = selectedSections[i];
      for (let j = 0; j < room.courseSlots.length; j++) {
        const slot = room.courseSlots[j];
        if (sec >= slot.startSection && sec <= slot.endSection) {
          return false;
        }
      }
    }
    return true;
  }

  private static extractCampusName(fullName: string): string {
    if (fullName.includes('嘉定')) {
      return '嘉定校区';
    }
    if (fullName.includes('延长')) {
      return '延长校区';
    }
    return '宝山校区';
  }
}
