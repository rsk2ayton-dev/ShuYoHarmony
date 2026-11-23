import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoCampusSystem,
  ShuYoRateHomeData,
  ShuYoRateOption,
  ShuYoRateOptionStat,
  ShuYoRateQuestion,
  ShuYoRateQuestionStat,
  ShuYoRateRankingCategory,
  ShuYoRateReviewRecord,
  ShuYoRateUnitDetail,
  ShuYoRateUnitItem,
  ShuYoScheduleData
} from '../models/ShuYoModels';
import { AuthService } from './AuthService';
import { HttpClientService, ShuYoCookieJar, ShuYoHttpResult } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { SecureStorageService } from './SecureStorageService';

interface StoredRateStudentSession {
  studentId: string;
  token: string;
  expiresAtMs: number;
}

interface SchoolSessionProofPayload {
  source: string;
  cookie: string;
}

interface CreateSessionPayload {
  schoolSession: SchoolSessionProofPayload;
  expectedStudentId: string;
  deviceLabel: string;
  userInitiated: boolean;
}

interface SaveReviewPayload {
  overall: number;
  answers: Record<string, string[]>;
}

export class CourseReviewService {
  private static readonly studentTokenKey: string = 'shuyo_rate_student_token_v1';

  private static readonly defaultQuestions: ShuYoRateQuestion[] = [
    {
      key: 'overall',
      title: '总体评价',
      multiple: false,
      required: true,
      maxSelections: 1,
      options: [
        { key: '1', label: '不推荐' },
        { key: '2', label: '谨慎选择' },
        { key: '3', label: '中规中矩' },
        { key: '4', label: '值得一选' },
        { key: '5', label: '强烈推荐' }
      ]
    },
    {
      key: 'grading',
      title: '给分倾向',
      multiple: false,
      required: false,
      maxSelections: 1,
      options: [
        { key: 'strict', label: '要求严格' },
        { key: 'fair', label: '给分合理' },
        { key: 'generous', label: '给分宽松' }
      ]
    },
    {
      key: 'teaching',
      title: '课堂体验',
      multiple: true,
      required: false,
      maxSelections: 2,
      options: [
        { key: 'clear', label: '讲解清晰' },
        { key: 'interactive', label: '互动充分' },
        { key: 'practical', label: '注重实践' },
        { key: 'fast', label: '节奏较快' }
      ]
    }
  ];

  private static demoUnitsCache: ShuYoRateUnitItem[] = [];
  private static demoReviewsMap: Map<string, ShuYoRateReviewRecord[]> = new Map<string, ShuYoRateReviewRecord[]>();
  private static liveUnitsById: Map<string, ShuYoRateUnitItem> = new Map<string, ShuYoRateUnitItem>();
  private static liveQuestionsCache: ShuYoRateQuestion[] = [];

  static emptyHome(): ShuYoRateHomeData {
    return {
      recent: [],
      rankingTitle: '综合评分榜',
      rankingItems: [],
      rankings: [],
      colleges: [],
      questions: CourseReviewService.defaultQuestions
    };
  }

  static buildDemoHome(schedule: ShuYoScheduleData): ShuYoRateHomeData {
    if (CourseReviewService.demoUnitsCache.length === 0) {
      CourseReviewService.initDemoUnits(schedule);
    }
    const items = [...CourseReviewService.demoUnitsCache];
    const ranked = [...CourseReviewService.demoUnitsCache];
    ranked.sort((a: ShuYoRateUnitItem, b: ShuYoRateUnitItem): number => b.average - a.average);
    const demoCat: ShuYoRateRankingCategory = {
      key: 'demo-all',
      title: '综合评分榜',
      total: ranked.length,
      items: ranked
    };
    return {
      recent: items,
      rankingTitle: '综合评分榜',
      rankingItems: ranked,
      rankings: [demoCat],
      colleges: ['计算机学院', '公共基础教学部'],
      questions: CourseReviewService.defaultQuestions
    };
  }

  private static initDemoUnits(schedule: ShuYoScheduleData): void {
    const seen = new Set<string>();
    const list: ShuYoRateUnitItem[] = [];
    const baseScores: number[] = [9.4, 9.1, 8.8, 9.6, 8.5, 9.0, 9.3, 8.9];
    const sampleTags: string[][] = [
      ['讲解清晰', '给分合理'],
      ['注重实践', '互动充分'],
      ['给分宽松', '讲解清晰'],
      ['干货满满', '推荐选修'],
      ['节奏较快', '收获大']
    ];
    for (let i = 0; i < schedule.sessions.length; i++) {
      const s = schedule.sessions[i];
      const tName = s.teacherName.length > 0 ? s.teacherName : '授课教师';
      const unitId = `${s.courseCode}:${tName}`;
      if (seen.has(unitId) || s.courseName.length === 0) {
        continue;
      }
      seen.add(unitId);
      const isCs = s.courseCode.startsWith('JBK') || s.courseCode.startsWith('BBK');
      const idx = list.length;
      const avg = baseScores[idx % baseScores.length];
      list.push({
        id: unitId,
        courseId: s.courseCode,
        courseName: s.courseName,
        college: isCs ? '计算机学院' : '公共基础教学部',
        credits: s.credit,
        teacherId: `teacher-${idx}`,
        teacherName: tName,
        reviewCount: 4 + (idx % 5),
        average: avg,
        lastReviewedText: `${idx + 1}小时前`,
        tags: sampleTags[idx % sampleTags.length]
      });

      const sampleReviews: ShuYoRateReviewRecord[] = [
        {
          id: `rev-${idx}-1`,
          unitId: unitId,
          overall: 5,
          answers: { 'grading': ['fair'], 'teaching': ['clear', 'practical'] },
          comment: '老师讲课条理很清晰，平时作业和考试难度匹配，非常推荐！',
          updatedAt: '2026-09-12'
        },
        {
          id: `rev-${idx}-2`,
          unitId: unitId,
          overall: 4,
          answers: { 'grading': ['generous'], 'teaching': ['interactive'] },
          comment: '课堂氛围活跃，给分比较友好，认真完成实验就能拿不错绩点。',
          updatedAt: '2026-09-05'
        }
      ];
      CourseReviewService.demoReviewsMap.set(unitId, sampleReviews);
    }

    if (list.length === 0) {
      list.push({
        id: 'GBK0102001:教师A',
        courseId: 'GBK0102001',
        courseName: '概率论与数理统计A',
        college: '公共基础教学部',
        credits: '4.0',
        teacherId: 'teacher-0',
        teacherName: '教师A',
        reviewCount: 6,
        average: 9.2,
        lastReviewedText: '2小时前',
        tags: ['讲解清晰', '给分合理']
      });
    }
    CourseReviewService.demoUnitsCache = list;
  }

  static getUnitById(unitId: string): ShuYoRateUnitItem | undefined {
    const live = CourseReviewService.liveUnitsById.get(unitId);
    if (live !== undefined) {
      return live;
    }
    for (let i = 0; i < CourseReviewService.demoUnitsCache.length; i++) {
      if (CourseReviewService.demoUnitsCache[i].id === unitId) {
        return CourseReviewService.demoUnitsCache[i];
      }
    }
    return undefined;
  }

  static getReviewsForUnit(unitId: string): ShuYoRateReviewRecord[] {
    return CourseReviewService.demoReviewsMap.get(unitId) ?? [];
  }

  static computeQuestionStats(unitId: string): ShuYoRateQuestionStat[] {
    const reviews = CourseReviewService.getReviewsForUnit(unitId);
    const stats: ShuYoRateQuestionStat[] = [];
    for (let qIdx = 0; qIdx < CourseReviewService.defaultQuestions.length; qIdx++) {
      const q = CourseReviewService.defaultQuestions[qIdx];
      const counts = new Map<string, number>();
      for (let o = 0; o < q.options.length; o++) {
        counts.set(q.options[o].key, 0);
      }
      let answered = 0;
      for (let r = 0; r < reviews.length; r++) {
        const rev = reviews[r];
        if (q.key === 'overall') {
          answered++;
          const k = String(rev.overall);
          counts.set(k, (counts.get(k) ?? 0) + 1);
        } else {
          const arr = rev.answers[q.key];
          if (arr !== undefined && arr.length > 0) {
            answered++;
            for (let a = 0; a < arr.length; a++) {
              const key = arr[a];
              counts.set(key, (counts.get(key) ?? 0) + 1);
            }
          }
        }
      }
      let maxCount = 0;
      for (let o = 0; o < q.options.length; o++) {
        const c = counts.get(q.options[o].key) ?? 0;
        if (c > maxCount) {
          maxCount = c;
        }
      }
      const optStats: ShuYoRateOptionStat[] = [];
      for (let o = 0; o < q.options.length; o++) {
        const opt = q.options[o];
        const c = counts.get(opt.key) ?? 0;
        const pct = answered > 0 ? Math.round((c * 100) / answered) : 0;
        optStats.push({
          key: opt.key,
          label: opt.label,
          count: c,
          percent: pct,
          isTop: maxCount > 0 && c === maxCount
        });
      }
      stats.push({
        key: q.key,
        title: q.title,
        answered: answered,
        options: optStats
      });
    }
    return stats;
  }

  static submitDemoReview(
    unitId: string,
    overall: number,
    gradingKey: string,
    teachingKeys: string[],
    comment: string
  ): void {
    const existing = CourseReviewService.demoReviewsMap.get(unitId) ?? [];
    const answers: Record<string, string[]> = {};
    if (gradingKey.length > 0) {
      answers['grading'] = [gradingKey];
    }
    if (teachingKeys.length > 0) {
      answers['teaching'] = teachingKeys;
    }
    const newRec: ShuYoRateReviewRecord = {
      id: `rev-${Date.now()}`,
      unitId: unitId,
      overall: overall,
      answers: answers,
      comment: comment.trim().length > 0 ? comment.trim() : '已提交课程评价',
      updatedAt: '刚刚'
    };
    const nextList: ShuYoRateReviewRecord[] = [newRec];
    for (let i = 0; i < existing.length; i++) {
      nextList.push(existing[i]);
    }
    CourseReviewService.demoReviewsMap.set(unitId, nextList);

    for (let i = 0; i < CourseReviewService.demoUnitsCache.length; i++) {
      const u = CourseReviewService.demoUnitsCache[i];
      if (u.id === unitId) {
        let sum = 0;
        for (let r = 0; r < nextList.length; r++) {
          sum += nextList[r].overall + 5;
        }
        const avg = Number((sum / nextList.length).toFixed(1));
        CourseReviewService.demoUnitsCache[i] = {
          id: u.id,
          courseId: u.courseId,
          courseName: u.courseName,
          college: u.college,
          credits: u.credits,
          teacherId: u.teacherId,
          teacherName: u.teacherName,
          reviewCount: nextList.length,
          average: avg,
          lastReviewedText: '刚刚',
          tags: u.tags
        };
        break;
      }
    }
  }

  static clearStudentToken(): void {
    SecureStorageService.remove(CourseReviewService.studentTokenKey);
  }

  static async fetchLiveHome(): Promise<ShuYoRateHomeData> {
    const data = await CourseReviewService.getApiData('/api/v1/rate/home', '课评首页加载失败');
    const recentRaw = JsonHelpers.asArray(data['recent']);
    const recent: ShuYoRateUnitItem[] = [];
    for (let i = 0; i < recentRaw.length; i++) {
      const uObj = JsonHelpers.asObject(recentRaw[i]);
      if (uObj !== undefined) {
        const unit = CourseReviewService.parseUnit(uObj);
        CourseReviewService.cacheLiveUnit(unit);
        recent.push(unit);
      }
    }

    const rankingsRaw = JsonHelpers.asArray(data['rankings']);
    const rankings: ShuYoRateRankingCategory[] = [];
    for (let i = 0; i < rankingsRaw.length; i++) {
      const rObj = JsonHelpers.asObject(rankingsRaw[i]);
      if (rObj === undefined) {
        continue;
      }
      const rItemsRaw = JsonHelpers.asArray(rObj['items']);
      const items: ShuYoRateUnitItem[] = [];
      for (let j = 0; j < rItemsRaw.length; j++) {
        const uObj = JsonHelpers.asObject(rItemsRaw[j]);
        if (uObj !== undefined) {
          const unit = CourseReviewService.parseUnit(uObj);
          CourseReviewService.cacheLiveUnit(unit);
          items.push(unit);
        }
      }
      rankings.push({
        key: JsonHelpers.str(rObj, 'key', `rank-${i}`),
        title: JsonHelpers.str(rObj, 'title', '榜单'),
        total: JsonHelpers.num(rObj, 'total', items.length),
        items: items
      });
    }

    const collegesRaw = JsonHelpers.asArray(data['colleges']);
    const colleges: string[] = [];
    for (let i = 0; i < collegesRaw.length; i++) {
      const cObj = JsonHelpers.asObject(collegesRaw[i]);
      if (cObj !== undefined) {
        const cName = JsonHelpers.str(cObj, 'name', '').trim();
        if (cName.length > 0) {
          colleges.push(cName);
        }
      } else if (typeof collegesRaw[i] === 'string') {
        const s = String(collegesRaw[i]).trim();
        if (s.length > 0) {
          colleges.push(s);
        }
      }
    }

    const firstRankTitle = rankings.length > 0 ? rankings[0].title : '综合评分榜';
    const firstRankItems = rankings.length > 0 && rankings[0].items.length > 0
      ? rankings[0].items
      : recent;

    return {
      recent: recent,
      rankingTitle: firstRankTitle,
      rankingItems: firstRankItems,
      rankings: rankings,
      colleges: colleges,
      questions: CourseReviewService.liveQuestionsCache.length > 0
        ? CourseReviewService.liveQuestionsCache
        : CourseReviewService.defaultQuestions
    };
  }

  static async searchLive(query: string): Promise<ShuYoRateUnitItem[]> {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      return [];
    }
    const data = await CourseReviewService.getApiData(
      `/api/v1/rate/search?q=${encodeURIComponent(trimmed)}`,
      '课程评价搜索失败'
    );
    const unitsOut: ShuYoRateUnitItem[] = [];
    const seen = new Set<string>();

    const unitsRaw = JsonHelpers.asArray(data['units']);
    for (let i = 0; i < unitsRaw.length; i++) {
      const uObj = JsonHelpers.asObject(unitsRaw[i]);
      if (uObj !== undefined) {
        const unit = CourseReviewService.parseUnit(uObj);
        if (unit.id.length > 0 && !seen.has(unit.id)) {
          seen.add(unit.id);
          CourseReviewService.cacheLiveUnit(unit);
          unitsOut.push(unit);
        }
      }
    }

    if (unitsOut.length > 0) {
      return unitsOut;
    }

    // When search returns courses or teachers directly, fetch their reviewable units
    const coursesRaw = JsonHelpers.asArray(data['courses']);
    const courseIds: string[] = [];
    for (let i = 0; i < coursesRaw.length && courseIds.length < 3; i++) {
      const cObj = JsonHelpers.asObject(coursesRaw[i]);
      const cId = JsonHelpers.str(cObj, 'id', '').trim();
      if (cId.length > 0) {
        courseIds.push(cId);
      }
    }
    if (courseIds.length > 0) {
      const fetchedLists = await Promise.all(
        courseIds.map((cId: string): Promise<ShuYoRateUnitItem[]> =>
          CourseReviewService.fetchUnitsFromPathSafe(
            `/api/v1/rate/courses/${encodeURIComponent(cId)}`,
            '加载课程详情失败'
          )
        )
      );
      for (let i = 0; i < fetchedLists.length; i++) {
        const list = fetchedLists[i];
        for (let j = 0; j < list.length; j++) {
          const u = list[j];
          if (u.id.length > 0 && !seen.has(u.id)) {
            seen.add(u.id);
            unitsOut.push(u);
          }
        }
      }
      if (unitsOut.length > 0) {
        return unitsOut;
      }
    }

    const teachersRaw = JsonHelpers.asArray(data['teachers']);
    const teacherIds: string[] = [];
    for (let i = 0; i < teachersRaw.length && teacherIds.length < 2; i++) {
      const tObj = JsonHelpers.asObject(teachersRaw[i]);
      const tId = JsonHelpers.str(tObj, 'id', '').trim();
      if (tId.length > 0) {
        teacherIds.push(tId);
      }
    }
    if (teacherIds.length > 0) {
      const fetchedLists = await Promise.all(
        teacherIds.map((tId: string): Promise<ShuYoRateUnitItem[]> =>
          CourseReviewService.fetchUnitsFromPathSafe(
            `/api/v1/rate/teachers/${encodeURIComponent(tId)}`,
            '加载教师授课详情失败'
          )
        )
      );
      for (let i = 0; i < fetchedLists.length; i++) {
        const list = fetchedLists[i];
        for (let j = 0; j < list.length; j++) {
          const u = list[j];
          if (u.id.length > 0 && !seen.has(u.id)) {
            seen.add(u.id);
            unitsOut.push(u);
          }
        }
      }
    }

    return unitsOut;
  }

  private static async fetchUnitsFromPathSafe(path: string, errMsg: string): Promise<ShuYoRateUnitItem[]> {
    try {
      const data = await CourseReviewService.getApiData(path, errMsg);
      const rawUnits = JsonHelpers.asArray(data['units']);
      const out: ShuYoRateUnitItem[] = [];
      for (let i = 0; i < rawUnits.length; i++) {
        const uObj = JsonHelpers.asObject(rawUnits[i]);
        if (uObj !== undefined) {
          const unit = CourseReviewService.parseUnit(uObj);
          CourseReviewService.cacheLiveUnit(unit);
          out.push(unit);
        }
      }
      return out;
    } catch (_err) {
      return [];
    }
  }

  static async fetchLiveUnitDetail(unitId: string): Promise<ShuYoRateUnitDetail> {
    const data = await CourseReviewService.getApiData(
      `/api/v1/rate/units/${encodeURIComponent(unitId)}`,
      '课程评价详情加载失败'
    );
    const unit = CourseReviewService.parseUnit(data);
    CourseReviewService.cacheLiveUnit(unit);
    const statsRaw = JsonHelpers.asArray(data['stats']);
    const stats: ShuYoRateQuestionStat[] = [];
    for (let i = 0; i < statsRaw.length; i++) {
      const sObj = JsonHelpers.asObject(statsRaw[i]);
      if (sObj === undefined) {
        continue;
      }
      const optsRaw = JsonHelpers.asArray(sObj['options']);
      const opts: ShuYoRateOptionStat[] = [];
      for (let j = 0; j < optsRaw.length; j++) {
        const oObj = JsonHelpers.asObject(optsRaw[j]);
        if (oObj === undefined) {
          continue;
        }
        opts.push({
          key: JsonHelpers.str(oObj, 'key', ''),
          label: JsonHelpers.str(oObj, 'label', ''),
          count: JsonHelpers.num(oObj, 'count', 0),
          percent: JsonHelpers.num(oObj, 'percent', 0),
          isTop: JsonHelpers.bool(oObj, 'top', false)
        });
      }
      stats.push({
        key: JsonHelpers.str(sObj, 'key', `stat-${i}`),
        title: JsonHelpers.str(sObj, 'title', ''),
        answered: JsonHelpers.num(sObj, 'answered', 0),
        options: opts
      });
    }
    return {
      unit: unit,
      stats: stats
    };
  }

  static async fetchLiveQuestions(): Promise<ShuYoRateQuestion[]> {
    try {
      const data = await CourseReviewService.getApiData(
        '/api/v1/rate/questions',
        '评课问卷配置加载失败'
      );
      const qRaw = JsonHelpers.asArray(data['questions']);
      const questions: ShuYoRateQuestion[] = [];
      for (let i = 0; i < qRaw.length; i++) {
        const qObj = JsonHelpers.asObject(qRaw[i]);
        if (qObj === undefined) {
          continue;
        }
        const optsRaw = JsonHelpers.asArray(qObj['options']);
        const opts: ShuYoRateOption[] = [];
        for (let j = 0; j < optsRaw.length; j++) {
          const oObj = JsonHelpers.asObject(optsRaw[j]);
          if (oObj !== undefined) {
            opts.push({
              key: JsonHelpers.str(oObj, 'key', ''),
              label: JsonHelpers.str(oObj, 'label', '')
            });
          }
        }
        const maxSel = JsonHelpers.num(qObj, 'maxSelections', 0);
        const multiple = JsonHelpers.bool(qObj, 'multiple', false);
        questions.push({
          key: JsonHelpers.str(qObj, 'key', ''),
          title: JsonHelpers.str(qObj, 'title', ''),
          multiple: multiple,
          required: JsonHelpers.bool(qObj, 'required', false),
          maxSelections: maxSel > 0 ? maxSel : (multiple ? opts.length : 1),
          options: opts
        });
      }
      if (questions.length > 0) {
        CourseReviewService.liveQuestionsCache = questions;
        return questions;
      }
      return CourseReviewService.defaultQuestions;
    } catch (_err) {
      return CourseReviewService.liveQuestionsCache.length > 0
        ? CourseReviewService.liveQuestionsCache
        : CourseReviewService.defaultQuestions;
    }
  }

  static async submitLiveReview(
    studentId: string,
    campusSystem: ShuYoCampusSystem,
    unitId: string,
    overall: number,
    answers: Record<string, string[]>
  ): Promise<void> {
    const trimmedStu = studentId.trim();
    if (trimmedStu.length === 0) {
      throw new Error('请先登录上海大学统一身份认证账号后再提交评价');
    }
    let token = await CourseReviewService.ensureStudentToken(trimmedStu, campusSystem, false);
    const payload: SaveReviewPayload = {
      overall: overall,
      answers: answers
    };
    const path = `/api/v1/student/rate/reviews/${encodeURIComponent(unitId)}`;
    const firstResp = await CourseReviewService.sendApi(
      http.RequestMethod.PUT,
      path,
      token,
      JSON.stringify(payload)
    );
    if (firstResp.statusCode === 401) {
      CourseReviewService.clearStudentToken();
      token = await CourseReviewService.ensureStudentToken(trimmedStu, campusSystem, true);
      const retryResp = await CourseReviewService.sendApi(
        http.RequestMethod.PUT,
        path,
        token,
        JSON.stringify(payload)
      );
      CourseReviewService.ensureJsonSuccess(retryResp.statusCode, retryResp.body, '提交课程评价失败');
      return;
    }
    CourseReviewService.ensureJsonSuccess(firstResp.statusCode, firstResp.body, '提交课程评价失败');
  }

  private static async ensureStudentToken(
    studentId: string,
    campusSystem: ShuYoCampusSystem,
    forceRefresh: boolean
  ): Promise<string> {
    if (!forceRefresh) {
      const saved = CourseReviewService.loadStoredStudentSession(studentId);
      if (saved !== undefined) {
        return saved.token;
      }
    }

    let cookieStr = CourseReviewService.buildSchoolProofCookie(campusSystem);
    if (cookieStr.length === 0 && campusSystem === ShuYoCampusSystem.UNDERGRADUATE) {
      const reauthed = await AuthService.trySilentAcademicReauth();
      if (reauthed) {
        cookieStr = CourseReviewService.buildSchoolProofCookie(campusSystem);
      }
    }
    if (cookieStr.length === 0) {
      throw new Error('当前学校会话不可用，请重新登录校园账号后再提交评价');
    }

    const proof: SchoolSessionProofPayload = {
      source: campusSystem === ShuYoCampusSystem.GRADUATE ? 'yjs' : 'jwxt',
      cookie: cookieStr
    };
    const reqBody: CreateSessionPayload = {
      schoolSession: proof,
      expectedStudentId: studentId,
      deviceLabel: 'HarmonyOS',
      userInitiated: true
    };
    const resp = await CourseReviewService.sendApi(
      http.RequestMethod.POST,
      '/api/v1/student/sessions',
      '',
      JSON.stringify(reqBody)
    );
    const decoded = CourseReviewService.ensureJsonSuccess(resp.statusCode, resp.body, '学生身份核验失败');
    const data = JsonHelpers.asObject(decoded['data']);
    const token = JsonHelpers.str(data, 'token', '').trim();
    const expiresStr = JsonHelpers.str(data, 'expiresAt', '').trim();
    const parsedExp = Date.parse(expiresStr);
    const expiresAtMs = Number.isFinite(parsedExp) && parsedExp > Date.now()
      ? parsedExp
      : Date.now() + 7 * 86400000;
    if (token.length === 0) {
      throw new Error('评课服务未返回有效的学生身份凭证');
    }
    CourseReviewService.saveStudentSession({
      studentId: studentId.toUpperCase(),
      token: token,
      expiresAtMs: expiresAtMs
    });
    return token;
  }

  private static buildSchoolProofCookie(campusSystem: ShuYoCampusSystem): string {
    if (campusSystem === ShuYoCampusSystem.GRADUATE) {
      const gsVal = ShuYoCookieJar.getCookieValue(`${ShuYoConstants.yjsBaseUrl}/gsapp/`, 'GS_SESSIONID');
      return gsVal.length > 0 ? `GS_SESSIONID=${gsVal}` : '';
    }
    const rawHeader = ShuYoCookieJar.headerFor(`${ShuYoConstants.jwxtBaseUrl}/jwglxt/`);
    if (rawHeader.length === 0) {
      return '';
    }
    const parts = rawHeader.split(';');
    const kept: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      const eqIdx = part.indexOf('=');
      if (eqIdx <= 0 || eqIdx >= part.length - 1) {
        continue;
      }
      const nameLower = part.substring(0, eqIdx).trim().toLowerCase();
      if (nameLower === 'shu_oauth2' || nameLower === 'webvpn-token' || nameLower === 'gs_sessionid') {
        continue;
      }
      kept.push(part);
    }
    return kept.join('; ');
  }

  private static loadStoredStudentSession(studentId: string): StoredRateStudentSession | undefined {
    const raw = SecureStorageService.getString(CourseReviewService.studentTokenKey, '');
    if (raw.length === 0) {
      return undefined;
    }
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const savedStu = JsonHelpers.str(obj, 'studentId', '').trim().toUpperCase();
    const token = JsonHelpers.str(obj, 'token', '').trim();
    const expiresAtMs = JsonHelpers.num(obj, 'expiresAtMs', 0);
    if (savedStu !== studentId.trim().toUpperCase() || token.length === 0 || Date.now() >= expiresAtMs) {
      return undefined;
    }
    return {
      studentId: savedStu,
      token: token,
      expiresAtMs: expiresAtMs
    };
  }

  private static saveStudentSession(session: StoredRateStudentSession): void {
    SecureStorageService.setString(CourseReviewService.studentTokenKey, JSON.stringify(session));
  }

  private static async getApiData(path: string, fallbackErr: string): Promise<Record<string, Object>> {
    const resp = await CourseReviewService.sendApi(http.RequestMethod.GET, path, '', undefined);
    const decoded = CourseReviewService.ensureJsonSuccess(resp.statusCode, resp.body, fallbackErr);
    const data = JsonHelpers.asObject(decoded['data']);
    if (data !== undefined) {
      return data;
    }
    return decoded;
  }

  private static async sendApi(
    method: http.RequestMethod,
    path: string,
    bearerToken: string,
    body?: string
  ): Promise<ShuYoHttpResult> {
    const headers: Record<string, string> = {
      'accept': 'application/json'
    };
    if (bearerToken.length > 0) {
      headers['authorization'] = `Bearer ${bearerToken}`;
    }
    if (body !== undefined) {
      headers['content-type'] = 'application/json; charset=utf-8';
    }
    return HttpClientService.request(
      method,
      `${ShuYoConstants.clientBackendBaseUrl}${path}`,
      headers,
      body
    );
  }

  private static ensureJsonSuccess(
    statusCode: number,
    body: string,
    fallbackErr: string
  ): Record<string, Object> {
    if (statusCode === 204) {
      return {};
    }
    const decoded = JsonHelpers.parseObject(body);
    const serverErr = decoded !== undefined ? JsonHelpers.str(decoded, 'error', '').trim() : '';
    if (statusCode === 429) {
      throw new Error(serverErr.length > 0 ? serverErr : '操作过于频繁，请稍后再试');
    }
    if (statusCode < 200 || statusCode >= 300 || decoded === undefined || decoded['success'] === false) {
      throw new Error(serverErr.length > 0 ? serverErr : `${fallbackErr} (${statusCode})`);
    }
    return decoded;
  }

  private static cacheLiveUnit(unit: ShuYoRateUnitItem): void {
    if (unit.id.length > 0) {
      CourseReviewService.liveUnitsById.set(unit.id, unit);
    }
  }

  private static parseUnit(obj: Record<string, Object>): ShuYoRateUnitItem {
    const course = JsonHelpers.asObject(obj['course']);
    const teacher = JsonHelpers.asObject(obj['teacher']);
    const rawAvg = obj['average'];
    let average = 0;
    if (typeof rawAvg === 'number' && Number.isFinite(rawAvg) && rawAvg > 0) {
      average = Number(rawAvg.toFixed(1));
    }
    const reviewCount = Math.max(0, JsonHelpers.num(obj, 'reviewCount', 0));
    const baseTeacher = JsonHelpers.str(teacher, 'name', '未知教师');
    const duplicate = JsonHelpers.bool(teacher, 'duplicateName', false);
    const teacherCollege = JsonHelpers.str(teacher, 'college', '');
    const teacherTitle = JsonHelpers.str(teacher, 'title', '');
    let displayTeacher = baseTeacher;
    if (duplicate) {
      const hint = teacherCollege.length > 0 ? teacherCollege : teacherTitle;
      if (hint.length > 0) {
        displayTeacher = `${baseTeacher}（${hint}）`;
      }
    }
    const rawDate = JsonHelpers.str(obj, 'lastReviewedAt', '');
    const dateLabel = rawDate.length >= 10
      ? rawDate.substring(0, 10)
      : (reviewCount > 0 ? '近期' : '暂无评价');

    return {
      id: JsonHelpers.str(obj, 'id', ''),
      courseId: JsonHelpers.str(course, 'id', ''),
      courseName: JsonHelpers.str(course, 'name', '未知课程'),
      college: JsonHelpers.str(course, 'college', ''),
      credits: JsonHelpers.str(course, 'credits', ''),
      teacherId: JsonHelpers.str(teacher, 'id', ''),
      teacherName: displayTeacher,
      reviewCount: reviewCount,
      average: average,
      lastReviewedText: dateLabel,
      tags: []
    };
  }
}
