import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoAcademicTerm,
  ShuYoCourseSession,
  ShuYoScheduleCollection,
  ShuYoScheduleData,
  ShuYoUntimedCourse
} from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

export interface ShuYoCalendarPreset {
  id: string;
  label: string;
  startDate: string;
  maxWeek: number;
}

interface GraduatePlacement {
  courseCode: string;
  classId: string;
  courseName: string;
  teacherName: string;
  location: string;
  weekday: number;
  weeks: number[];
  weekText: string;
  sectionSet: Set<number>;
}

export class ScheduleService {
  private static readonly yjsModulePath: string = '/gsapp/sys/wdkbapp';
  private static readonly yjsPortalUrl: string =
    'https://yjs.shu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do';
  private static readonly yjsUserInfoUrl: string =
    'https://yjs.shu.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do';
  private static readonly yjsModuleEntryUrl: string =
    'https://yjs.shu.edu.cn/gsapp/sys/wdkbapp/*default/index.do';

  static loadDemoSchedule(): ShuYoScheduleData {
    const raw = RawFileService.readText('demo/academic/schedule.raw.json');
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      return ScheduleService.emptySchedule();
    }
    const parsed = ScheduleService.parseJwxtPayload(obj);
    if (parsed.term.studentId.length === 0) {
      parsed.term.studentId = 'DEMO0001';
    }
    if (parsed.term.studentName.length === 0) {
      parsed.term.studentName = '演示同学';
    }
    return parsed;
  }

  static emptySchedule(studentId: string = ''): ShuYoScheduleData {
    return {
      term: {
        yearCode: '',
        termCode: '',
        academicYearName: '暂未同步学期',
        termName: '',
        studentName: '',
        studentId: studentId,
        className: ''
      },
      sessions: [],
      untimedCourses: [],
      fetchedAt: '',
      maxWeek: 18
    };
  }

  static readonly calendarPresets: ShuYoCalendarPreset[] = [
    { id: '2026-autumn', label: '2026-2027 秋季学期', startDate: '2026-09-14', maxWeek: 18 },
    { id: '2026-spring', label: '2026-2027 春季学期', startDate: '2027-02-22', maxWeek: 18 },
    { id: '2026-summer', label: '2026-2027 夏季实践', startDate: '2027-06-28', maxWeek: 4 },
    { id: '2027-autumn', label: '2027-2028 秋季学期', startDate: '2027-09-06', maxWeek: 18 }
  ];

  private static pad2(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }

  private static parseDateParts(dateStr: string): number[] | undefined {
    const m = new RegExp('^(\\d{4})-(\\d{1,2})-(\\d{1,2})$').exec(dateStr.trim());
    if (m === null) {
      return undefined;
    }
    const y = parseInt(m[1], 10);
    const mo = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (!Number.isFinite(y) || !Number.isFinite(mo) || !Number.isFinite(d) ||
      mo < 1 || mo > 12 || d < 1 || d > 31) {
      return undefined;
    }
    return [y, mo, d];
  }

  private static dateToUtcDay(dateStr: string): number {
    const parts = ScheduleService.parseDateParts(dateStr);
    if (parts === undefined) {
      return Number.NaN;
    }
    return Math.floor(Date.UTC(parts[0], parts[1] - 1, parts[2]) / 86400000);
  }

  private static utcDayToDateStr(utcDay: number): string {
    const d = new Date(utcDay * 86400000);
    return `${d.getUTCFullYear()}-${ScheduleService.pad2(d.getUTCMonth() + 1)}-${ScheduleService.pad2(d.getUTCDate())}`;
  }

  static makeDate(dateStr: string): Date {
    const parts = ScheduleService.parseDateParts(dateStr);
    if (parts === undefined) {
      return new Date(2026, 8, 14);
    }
    return new Date(parts[0], parts[1] - 1, parts[2]);
  }

  static getTodayDateStr(): string {
    const d = new Date();
    return `${d.getFullYear()}-${ScheduleService.pad2(d.getMonth() + 1)}-${ScheduleService.pad2(d.getDate())}`;
  }

  static alignToMonday(dateStr: string): string {
    const parts = ScheduleService.parseDateParts(dateStr);
    if (parts === undefined) {
      return '2026-09-14';
    }
    const d = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
    const utcDay = d.getUTCDay();
    const offset = utcDay === 0 ? 6 : utcDay - 1;
    d.setUTCDate(d.getUTCDate() - offset);
    return `${d.getUTCFullYear()}-${ScheduleService.pad2(d.getUTCMonth() + 1)}-${ScheduleService.pad2(d.getUTCDate())}`;
  }

  static addDaysToDateStr(dateStr: string, deltaDays: number): string {
    const dayNum = ScheduleService.dateToUtcDay(dateStr);
    if (!Number.isFinite(dayNum)) {
      return dateStr;
    }
    return ScheduleService.utcDayToDateStr(dayNum + deltaDays);
  }

  static computeWeekFromStart(startMondayStr: string, targetDateStr: string): number {
    const startDay = ScheduleService.dateToUtcDay(ScheduleService.alignToMonday(startMondayStr));
    const targetDay = ScheduleService.dateToUtcDay(ScheduleService.alignToMonday(targetDateStr));
    if (!Number.isFinite(startDay) || !Number.isFinite(targetDay)) {
      return 1;
    }
    return Math.floor((targetDay - startDay) / 7) + 1;
  }

  static computeStartMondayForActualWeek(weekNumber: number, todayStr: string): string {
    const safeWeek = weekNumber >= 1 ? weekNumber : 1;
    const thisMonday = ScheduleService.alignToMonday(todayStr);
    return ScheduleService.addDaysToDateStr(thisMonday, -(safeWeek - 1) * 7);
  }

  static formatMonthDay(dateStr: string): string {
    const parts = ScheduleService.parseDateParts(dateStr);
    if (parts === undefined) {
      return '';
    }
    return `${parts[1]}/${parts[2]}`;
  }

  static resolveDefaultCalendarPreset(term: ShuYoAcademicTerm): ShuYoCalendarPreset {
    const yearStr = term.academicYearName.trim();
    const termName = term.termName.trim();
    const termCode = term.termCode.trim();
    const is2026Year = yearStr.includes('2026-2027') || term.yearCode.trim() === '2026';
    const is2027Year = yearStr.includes('2027-2028') || term.yearCode.trim() === '2027';

    if (is2026Year) {
      if (termName.includes('秋') || termCode === '3') {
        return ScheduleService.calendarPresets[0];
      }
      if (termName.includes('春') || termCode === '16') {
        return ScheduleService.calendarPresets[1];
      }
      if (termName.includes('夏') || termCode === '32') {
        return ScheduleService.calendarPresets[2];
      }
    }
    if (is2027Year && (termName.includes('秋') || termCode === '3')) {
      return ScheduleService.calendarPresets[3];
    }

    const todayStr = ScheduleService.getTodayDateStr();
    if (todayStr < '2027-02-08') {
      return ScheduleService.calendarPresets[0];
    }
    if (todayStr <= '2027-06-27') {
      return ScheduleService.calendarPresets[1];
    }
    if (todayStr <= '2027-08-22') {
      return ScheduleService.calendarPresets[2];
    }
    return ScheduleService.calendarPresets[3];
  }

  private static indicatesSsoLogin(value: string): boolean {
    const lower = value.toLowerCase();
    return lower.includes('oauth2/login') ||
      lower.includes('newsso.shu.edu.cn') ||
      lower.includes('/oauth_shu/login') ||
      lower.includes('统一身份认证') ||
      lower.includes('login_slogin');
  }

  private static extractAttrValue(tag: string, attrName: string): string {
    const re = new RegExp(`\\b${attrName}\\s*=\\s*["']([^"']*)["']`, 'i');
    const m = re.exec(tag);
    return m !== null && m.length > 1 ? m[1].trim() : '';
  }

  private static extractSelectedTermValue(html: string, fieldId: string): string {
    const selectRe = new RegExp(`<select\\b[^>]*id\\s*=\\s*["']${fieldId}["'][^>]*>([\\s\\S]*?)<\\/select>`, 'i');
    const selectMatch = selectRe.exec(html);
    let firstNonEmpty = '';
    if (selectMatch !== null && selectMatch.length > 1) {
      const inner = selectMatch[1];
      const optionRe = new RegExp('<option\\b[^>]*>', 'gi');
      let optMatch = optionRe.exec(inner);
      while (optMatch !== null) {
        const optTag = optMatch[0];
        const val = ScheduleService.extractAttrValue(optTag, 'value');
        if (val.length > 0 && firstNonEmpty.length === 0) {
          firstNonEmpty = val;
        }
        if (new RegExp('\\bselected\\b', 'i').test(optTag) && val.length > 0) {
          return val;
        }
        optMatch = optionRe.exec(inner);
      }
    }

    const inputRe = new RegExp('<input\\b[^>]*>', 'gi');
    let inMatch = inputRe.exec(html);
    while (inMatch !== null) {
      const inTag = inMatch[0];
      const nameVal = ScheduleService.extractAttrValue(inTag, 'name');
      const idVal = ScheduleService.extractAttrValue(inTag, 'id');
      if (nameVal === fieldId || idVal === fieldId) {
        const val = ScheduleService.extractAttrValue(inTag, 'value');
        if (val.length > 0) {
          return val;
        }
      }
      inMatch = inputRe.exec(html);
    }

    return firstNonEmpty;
  }

  static async fetchLiveSchedule(): Promise<ShuYoScheduleData> {
    const indexUrl = `${ShuYoConstants.jwxtBaseUrl}${ShuYoConstants.jwxtScheduleIndexPath}`;
    const indexResp = await HttpClientService.getWithRedirects(indexUrl, 10, {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Referer': `${ShuYoConstants.jwxtBaseUrl}/jwglxt/xtgl/index_initMenu.html?jsdm=xs&echarts=1`
    });
    if (indexResp.statusCode === 401 ||
      indexResp.statusCode === 403 ||
      indexResp.statusCode === 901 ||
      indexResp.statusCode < 200 ||
      indexResp.statusCode >= 300 ||
      ScheduleService.indicatesSsoLogin(indexResp.location) ||
      ScheduleService.indicatesSsoLogin(indexResp.body)) {
      throw new Error('教务系统登录已失效，请重新登录');
    }

    const yearCode = ScheduleService.extractSelectedTermValue(indexResp.body, 'xnm');
    const termCode = ScheduleService.extractSelectedTermValue(indexResp.body, 'xqm');
    if (yearCode.length === 0 || termCode.length === 0) {
      throw new Error('未能识别当前学年学期，请重新登录');
    }

    const dataUrl = `${ShuYoConstants.jwxtBaseUrl}${ShuYoConstants.jwxtScheduleDataPath}`;
    const body = `xnm=${encodeURIComponent(yearCode)}&xqm=${encodeURIComponent(termCode)}&kzlx=ck&xsdm=&kclbdm=&kclxdm=`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'Accept': '*/*',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': indexUrl,
      'Origin': ShuYoConstants.jwxtBaseUrl
    };
    const resp = await HttpClientService.request(http.RequestMethod.POST, dataUrl, headers, body);
    if (resp.statusCode === 401 || resp.statusCode === 403 || resp.statusCode === 901) {
      throw new Error('教务系统登录已失效，请重新登录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`教务系统课表请求失败（HTTP ${resp.statusCode}）`);
    }
    if (resp.body.trimStart().startsWith('<') && ScheduleService.indicatesSsoLogin(resp.body)) {
      throw new Error('教务系统登录已失效，请重新登录');
    }

    const parsed = JsonHelpers.parseObject(resp.body);
    if (parsed === undefined ||
      !Array.isArray(parsed['kbList']) ||
      JsonHelpers.asObject(parsed['xsxx']) === undefined) {
      throw new Error('教务系统返回的课表数据格式无效');
    }
    const schedule = ScheduleService.parseJwxtPayload(parsed);
    if (schedule.term.studentId.length === 0) {
      throw new Error('教务系统返回课表缺少学号信息，请重新登录');
    }
    return schedule;
  }

  private static graduateActionUrl(action: string): string {
    return `${ShuYoConstants.yjsBaseUrl}${ScheduleService.yjsModulePath}/modules/xskcb/${action}.do`;
  }

  private static async postYjsJson(
    targetUrl: string,
    refererUrl: string,
    formBody?: string
  ): Promise<Record<string, Object>> {
    const headers: Record<string, string> = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Referer': refererUrl,
      'Origin': ShuYoConstants.yjsBaseUrl,
      'X-Requested-With': 'XMLHttpRequest'
    };
    if (formBody !== undefined && formBody.length > 0) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
    }
    const resp = await HttpClientService.request(http.RequestMethod.POST, targetUrl, headers, formBody);
    if (resp.statusCode === 401 ||
      resp.statusCode === 901 ||
      (resp.statusCode >= 300 && resp.statusCode < 400 && ScheduleService.indicatesSsoLogin(resp.location))) {
      throw new Error('研究生系统登录已失效，请重新登录');
    }
    if (resp.statusCode === 403) {
      throw new Error('研究生系统拒绝了课表请求，请稍后再试');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`研究生系统请求失败（HTTP ${resp.statusCode}）`);
    }
    if (resp.body.trimStart().startsWith('<') && ScheduleService.indicatesSsoLogin(resp.body)) {
      throw new Error('研究生系统登录已失效，请重新登录');
    }
    const json = JsonHelpers.parseObject(resp.body);
    if (json === undefined) {
      throw new Error('研究生系统返回的数据格式无法识别');
    }
    const code = JsonHelpers.str(json, 'code');
    if (code === '401' || code === '901') {
      throw new Error('研究生系统登录已失效，请重新登录');
    }
    if (code !== '0') {
      throw new Error('研究生系统未能返回课表数据');
    }
    return json;
  }

  private static mapGraduateTermCode(digit: string): string {
    if (digit === '1') {
      return '3';
    }
    if (digit === '2') {
      return '12';
    }
    if (digit === '3') {
      return '16';
    }
    if (digit === '4') {
      return '32';
    }
    return '';
  }

  private static mapGraduateTermName(digit: string): string {
    if (digit === '1') {
      return '秋';
    }
    if (digit === '2') {
      return '冬';
    }
    if (digit === '3') {
      return '春';
    }
    if (digit === '4') {
      return '夏';
    }
    return '';
  }

  static async fetchGraduateLiveSchedule(expectedStudentId: string): Promise<ShuYoScheduleData> {
    const userJson = await ScheduleService.postYjsJson(
      ScheduleService.yjsUserInfoUrl,
      ScheduleService.yjsPortalUrl
    );
    const userData = JsonHelpers.asObject(userJson['data']);
    const actualUserId = JsonHelpers.str(userData, 'userId').trim();
    if (actualUserId.length === 0 ||
      (expectedStudentId.length > 0 && actualUserId !== expectedStudentId)) {
      throw new Error('研究生系统登录账号不匹配或会话已失效，请重新登录');
    }
    const studentName = JsonHelpers.str(userData, 'userName').trim();

    const modResp = await HttpClientService.request(
      http.RequestMethod.GET,
      ScheduleService.yjsModuleEntryUrl,
      {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Referer': ScheduleService.yjsPortalUrl
      }
    );
    if (modResp.statusCode === 401 ||
      modResp.statusCode === 901 ||
      (modResp.statusCode >= 300 && modResp.statusCode < 400 && ScheduleService.indicatesSsoLogin(modResp.location)) ||
      (modResp.body.trimStart().startsWith('<') && ScheduleService.indicatesSsoLogin(modResp.body))) {
      throw new Error('研究生系统登录已失效，请重新登录');
    }
    if (modResp.statusCode < 200 || modResp.statusCode >= 300) {
      throw new Error(`无法打开研究生课表模块（HTTP ${modResp.statusCode}）`);
    }

    const catalogJson = await ScheduleService.postYjsJson(
      ScheduleService.graduateActionUrl('kfdxnxqcx'),
      ScheduleService.yjsModuleEntryUrl
    );
    const catDatas = JsonHelpers.asObject(catalogJson['datas']);
    const catTable = JsonHelpers.asObject(catDatas !== undefined ? catDatas['kfdxnxqcx'] : undefined);
    const catRows = JsonHelpers.asArray(catTable !== undefined ? catTable['rows'] : undefined);
    if (catRows.length === 0) {
      throw new Error('研究生系统未提供可查询的学期');
    }
    const firstTermRow = JsonHelpers.asObject(catRows[0]);
    const rawTerm = JsonHelpers.str(firstTermRow, 'XNXQDM').trim();
    if (!new RegExp('^\\d{4}[1-4]$').test(rawTerm)) {
      throw new Error('未能识别研究生系统当前学期');
    }
    const yearStr = rawTerm.substring(0, 4);
    const termDigit = rawTerm.substring(4);
    const yearNum = parseInt(yearStr, 10);
    const academicYearName = `${yearStr}-${yearNum + 1}`;
    const termCode = ScheduleService.mapGraduateTermCode(termDigit);
    const termName = ScheduleService.mapGraduateTermName(termDigit);

    const scheduleBody = `XNXQDM=${encodeURIComponent(rawTerm)}&*order=-ZCBH`;
    const schedJson = await ScheduleService.postYjsJson(
      ScheduleService.graduateActionUrl('xspkjgcx'),
      ScheduleService.yjsModuleEntryUrl,
      scheduleBody
    );
    const schedDatas = JsonHelpers.asObject(schedJson['datas']);
    const schedTable = JsonHelpers.asObject(schedDatas !== undefined ? schedDatas['xspkjgcx'] : undefined);
    const rows = JsonHelpers.asArray(schedTable !== undefined ? schedTable['rows'] : undefined);

    const groupKeys: string[] = [];
    const groupMap: Record<string, GraduatePlacement> = {};
    let maxFoundWeek = 16;

    for (let i = 0; i < rows.length; i++) {
      const row = JsonHelpers.asObject(rows[i]);
      if (row === undefined) {
        continue;
      }
      const start = JsonHelpers.num(row, 'KSJCDM', 0);
      const end = JsonHelpers.num(row, 'JSJCDM', 0);
      const weekday = JsonHelpers.num(row, 'XQ', 0);
      const courseName = JsonHelpers.str(row, 'KCMC').trim();
      const mask = JsonHelpers.str(row, 'ZCBH').trim();
      if (courseName.length === 0 || start < 1 || end < start || end > 12 || weekday < 1 || weekday > 7) {
        continue;
      }
      const weeks: number[] = [];
      for (let mIdx = 0; mIdx < mask.length; mIdx++) {
        if (mask.charAt(mIdx) === '1') {
          const wNum = mIdx + 1;
          weeks.push(wNum);
          if (wNum > maxFoundWeek) {
            maxFoundWeek = wNum;
          }
        }
      }
      if (weeks.length === 0) {
        continue;
      }
      const courseCode = JsonHelpers.str(row, 'KCDM').trim();
      const classId = JsonHelpers.str(row, 'BJDM').trim();
      const teacherName = JsonHelpers.str(row, 'JSXM').trim();
      const location = JsonHelpers.str(row, 'JASMC').trim();
      const weekStr = weeks.join(',');
      const slotKey = `${courseCode}|${classId}|${courseName}|${teacherName}|${location}|${weekday}|${weekStr}`;
      let placement = groupMap[slotKey];
      if (placement === undefined) {
        const weekText = JsonHelpers.str(row, 'ZCMC', `${weekStr}周`);
        placement = {
          courseCode: courseCode,
          classId: classId,
          courseName: courseName,
          teacherName: teacherName,
          location: location,
          weekday: weekday,
          weeks: weeks,
          weekText: weekText,
          sectionSet: new Set<number>()
        };
        groupMap[slotKey] = placement;
        groupKeys.push(slotKey);
      }
      for (let sec = start; sec <= end; sec++) {
        placement.sectionSet.add(sec);
      }
    }

    const sessions: ShuYoCourseSession[] = [];
    for (let g = 0; g < groupKeys.length; g++) {
      const p = groupMap[groupKeys[g]];
      const secs = Array.from(p.sectionSet);
      secs.sort((a: number, b: number): number => a - b);
      let first = 0;
      for (let last = 0; last < secs.length; last++) {
        if (last + 1 < secs.length && secs[last + 1] === secs[last] + 1) {
          continue;
        }
        const block = secs.slice(first, last + 1);
        sessions.push({
          id: `yjs-${g}-${first}-${p.weekday}-${block[0]}`,
          courseName: p.courseName,
          courseCode: p.courseCode,
          teachingClassId: p.classId,
          teacherName: p.teacherName,
          campus: '',
          location: p.location,
          weekday: p.weekday,
          startSection: block[0],
          endSection: block[block.length - 1],
          sections: block,
          weeks: p.weeks,
          weekText: p.weekText,
          credit: '',
          note: '',
          isManual: false
        });
        first = last + 1;
      }
    }

    sessions.sort((a: ShuYoCourseSession, b: ShuYoCourseSession): number => {
      if (a.weekday !== b.weekday) {
        return a.weekday - b.weekday;
      }
      return a.startSection - b.startSection;
    });

    return {
      term: {
        yearCode: yearStr,
        termCode: termCode,
        academicYearName: academicYearName,
        termName: termName,
        studentName: studentName,
        studentId: actualUserId,
        className: ''
      },
      sessions: sessions,
      untimedCourses: [],
      fetchedAt: new Date().toISOString(),
      maxWeek: Math.min(Math.max(maxFoundWeek, 4), 24)
    };
  }

  static parseJwxtPayload(json: Record<string, Object>): ShuYoScheduleData {
    const xsxx = JsonHelpers.asObject(json['xsxx']);
    const term: ShuYoAcademicTerm = {
      yearCode: JsonHelpers.str(xsxx, 'XNM', '2026'),
      termCode: JsonHelpers.str(xsxx, 'XQM', '3'),
      academicYearName: JsonHelpers.str(xsxx, 'XNMC', '2026-2027'),
      termName: JsonHelpers.str(xsxx, 'XQMMC', '秋'),
      studentName: JsonHelpers.str(xsxx, 'XM', ''),
      studentId: JsonHelpers.str(xsxx, 'XH', ''),
      className: JsonHelpers.str(xsxx, 'BJMC', '')
    };

    const kbList = JsonHelpers.asArray(json['kbList']);
    const sessions: ShuYoCourseSession[] = [];
    let maxFoundWeek = 16;

    for (let i = 0; i < kbList.length; i++) {
      const raw = JsonHelpers.asObject(kbList[i]);
      if (raw === undefined) {
        continue;
      }
      const sections = ScheduleService.parseSections(raw);
      const zcd = JsonHelpers.str(raw, 'zcd');
      const weeks = ScheduleService.parseWeeksWithMask(raw['oldzc'], zcd);
      for (let w = 0; w < weeks.length; w++) {
        if (weeks[w] > maxFoundWeek) {
          maxFoundWeek = weeks[w];
        }
      }
      const startSec = sections.length > 0 ? sections[0] : 1;
      const endSec = sections.length > 0 ? sections[sections.length - 1] : startSec;
      const jxbId = JsonHelpers.str(raw, 'jxb_id');
      const kchId = JsonHelpers.str(raw, 'kch_id', JsonHelpers.str(raw, 'kch'));
      const xqj = JsonHelpers.num(raw, 'xqj', 1);
      const jcs = JsonHelpers.str(raw, 'jcs', JsonHelpers.str(raw, 'jc'));
      sessions.push({
        id: `${jxbId.length > 0 ? jxbId : kchId}-${xqj}-${jcs}-${i}`,
        courseName: JsonHelpers.str(raw, 'kcmc'),
        courseCode: kchId,
        teachingClassId: jxbId,
        teacherName: JsonHelpers.str(raw, 'xm', JsonHelpers.str(raw, 'jsxm')),
        campus: JsonHelpers.str(raw, 'xqmc'),
        location: JsonHelpers.str(raw, 'cdmc'),
        weekday: xqj >= 1 && xqj <= 7 ? xqj : 1,
        startSection: startSec,
        endSection: endSec,
        sections: sections,
        weeks: weeks,
        weekText: zcd,
        credit: JsonHelpers.str(raw, 'xf'),
        note: JsonHelpers.str(raw, 'xkbz', JsonHelpers.str(raw, 'qqqh')),
        isManual: false
      });
    }

    const sjkList = JsonHelpers.asArray(json['sjkList']);
    const untimed: ShuYoUntimedCourse[] = [];
    for (let i = 0; i < sjkList.length; i++) {
      const raw = JsonHelpers.asObject(sjkList[i]);
      if (raw === undefined) {
        continue;
      }
      const weekText = JsonHelpers.str(raw, 'qsjsz', JsonHelpers.str(raw, 'zcd'));
      const weeks = ScheduleService.parseWeeksText(weekText);
      untimed.push({
        id: `untimed-${JsonHelpers.str(raw, 'kcmc')}-${i}`,
        courseName: JsonHelpers.str(raw, 'kcmc'),
        teacherName: JsonHelpers.str(raw, 'jsxm', JsonHelpers.str(raw, 'xm')),
        campus: JsonHelpers.str(raw, 'xqmc'),
        weeks: weeks,
        weekText: weekText,
        summary: JsonHelpers.str(raw, 'qtkcgs', JsonHelpers.str(raw, 'sjkcgs')),
        credit: JsonHelpers.str(raw, 'xf')
      });
    }

    return {
      term: term,
      sessions: sessions,
      untimedCourses: untimed,
      fetchedAt: new Date().toISOString(),
      maxWeek: Math.min(Math.max(maxFoundWeek, 4), 24)
    };
  }

  static parseBitmask(val: Object | undefined | null, maxBits: number): number[] {
    if (val === undefined || val === null) {
      return [];
    }
    const mask = typeof val === 'number' ? Math.floor(val) : parseInt(String(val), 10);
    if (!Number.isFinite(mask) || mask <= 0) {
      return [];
    }
    const result: number[] = [];
    for (let i = 0; i < maxBits; i++) {
      if ((mask & (1 << i)) !== 0) {
        result.push(i + 1);
      }
    }
    return result;
  }

  static parseWeeksWithMask(maskObj: Object | undefined | null, fallbackText: string): number[] {
    const byMask = ScheduleService.parseBitmask(maskObj, 30);
    if (byMask.length > 0) {
      return byMask;
    }
    return ScheduleService.parseWeeksText(fallbackText);
  }

  static parseWeeksText(text: string): number[] {
    const normalized = text
      .replace(new RegExp('，', 'g'), ',')
      .replace(new RegExp('、', 'g'), ',')
      .replace(new RegExp(' ', 'g'), '');
    if (normalized.length === 0) {
      return [];
    }
    const oddOnly = normalized.includes('单');
    const evenOnly = normalized.includes('双');
    const set = new Set<number>();

    const rangeRegex = new RegExp('(\\d+)\\s*-\\s*(\\d+)', 'g');
    let match = rangeRegex.exec(normalized);
    while (match !== null) {
      const start = parseInt(match[1], 10);
      const end = parseInt(match[2], 10);
      if (start > 0 && end >= start) {
        for (let w = start; w <= end; w++) {
          if (ScheduleService.matchesParity(w, oddOnly, evenOnly)) {
            set.add(w);
          }
        }
      }
      match = rangeRegex.exec(normalized);
    }

    const stripped = normalized.replace(new RegExp('\\d+\\s*-\\s*\\d+', 'g'), '');
    const numRegex = new RegExp('\\d+', 'g');
    let nMatch = numRegex.exec(stripped);
    while (nMatch !== null) {
      const w = parseInt(nMatch[0], 10);
      if (w > 0 && ScheduleService.matchesParity(w, oddOnly, evenOnly)) {
        set.add(w);
      }
      nMatch = numRegex.exec(stripped);
    }

    const list: number[] = Array.from(set);
    list.sort((a: number, b: number): number => a - b);
    return list;
  }

  private static matchesParity(week: number, oddOnly: boolean, evenOnly: boolean): boolean {
    if (oddOnly && week % 2 === 0) {
      return false;
    }
    if (evenOnly && week % 2 !== 0) {
      return false;
    }
    return true;
  }

  private static parseSections(raw: Record<string, Object>): number[] {
    const byMask = ScheduleService.parseBitmask(raw['oldjc'], 16);
    if (byMask.length > 0) {
      return byMask;
    }
    const text = JsonHelpers.str(raw, 'jcs', JsonHelpers.str(raw, 'jc'));
    const m = new RegExp('(\\d+)(?:\\s*-\\s*(\\d+))?').exec(text);
    if (m === null) {
      return [];
    }
    const start = parseInt(m[1], 10);
    const end = m[2] !== undefined && m[2].length > 0 ? parseInt(m[2], 10) : start;
    if (start <= 0 || end < start) {
      return [];
    }
    const out: number[] = [];
    for (let s = start; s <= end; s++) {
      out.push(s);
    }
    return out;
  }

  static exportScheduleCode(schedule: ShuYoScheduleData): string {
    return JSON.stringify(schedule);
  }

  static importScheduleCode(rawText: string): ShuYoScheduleData | undefined {
    const obj = JsonHelpers.parseObject(rawText.trim());
    if (obj === undefined) {
      return undefined;
    }
    if (obj['kbList'] !== undefined) {
      return ScheduleService.parseJwxtPayload(obj);
    }
    const termObj = JsonHelpers.asObject(obj['term']);
    const rawSessions = JsonHelpers.asArray(obj['sessions']);
    if (termObj === undefined && rawSessions.length === 0) {
      return undefined;
    }
    const term: ShuYoAcademicTerm = {
      yearCode: JsonHelpers.str(termObj, 'yearCode', '2026'),
      termCode: JsonHelpers.str(termObj, 'termCode', '3'),
      academicYearName: JsonHelpers.str(termObj, 'academicYearName', '2026-2027'),
      termName: JsonHelpers.str(termObj, 'termName', '秋'),
      studentName: JsonHelpers.str(termObj, 'studentName', ''),
      studentId: JsonHelpers.str(termObj, 'studentId', ''),
      className: JsonHelpers.str(termObj, 'className', '')
    };
    const sessions: ShuYoCourseSession[] = [];
    for (let i = 0; i < rawSessions.length; i++) {
      const sObj = JsonHelpers.asObject(rawSessions[i]);
      if (sObj === undefined) {
        continue;
      }
      const rawWeeks = JsonHelpers.asArray(sObj['weeks']);
      const weeks: number[] = [];
      for (let w = 0; w < rawWeeks.length; w++) {
        const wn = Number(rawWeeks[w]);
        if (Number.isFinite(wn) && wn > 0) {
          weeks.push(wn);
        }
      }
      const rawSecs = JsonHelpers.asArray(sObj['sections']);
      const secs: number[] = [];
      for (let sc = 0; sc < rawSecs.length; sc++) {
        const sn = Number(rawSecs[sc]);
        if (Number.isFinite(sn) && sn > 0) {
          secs.push(sn);
        }
      }
      sessions.push({
        id: JsonHelpers.str(sObj, 'id', `shared-${i}`),
        courseName: JsonHelpers.str(sObj, 'courseName', '未命名课程'),
        courseCode: JsonHelpers.str(sObj, 'courseCode'),
        teachingClassId: JsonHelpers.str(sObj, 'teachingClassId'),
        teacherName: JsonHelpers.str(sObj, 'teacherName'),
        campus: JsonHelpers.str(sObj, 'campus'),
        location: JsonHelpers.str(sObj, 'location'),
        weekday: JsonHelpers.num(sObj, 'weekday', 1),
        startSection: JsonHelpers.num(sObj, 'startSection', 1),
        endSection: JsonHelpers.num(sObj, 'endSection', 2),
        sections: secs,
        weeks: weeks,
        weekText: JsonHelpers.str(sObj, 'weekText', '1-16周'),
        credit: JsonHelpers.str(sObj, 'credit'),
        note: JsonHelpers.str(sObj, 'note'),
        isManual: JsonHelpers.bool(sObj, 'isManual', false)
      });
    }
    return {
      term: term,
      sessions: sessions,
      untimedCourses: [],
      fetchedAt: new Date().toISOString(),
      maxWeek: JsonHelpers.num(obj, 'maxWeek', 16)
    };
  }

  static createDefaultCollections(schedule: ShuYoScheduleData): ShuYoScheduleCollection[] {
    return [
      {
        id: 'col-primary',
        title: `${schedule.term.academicYearName} ${schedule.term.termName}`.trim(),
        schedule: schedule,
        isPrimary: true,
        updatedAt: schedule.fetchedAt
      }
    ];
  }
}
