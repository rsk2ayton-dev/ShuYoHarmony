import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoRateHomeData,
  ShuYoRateOption,
  ShuYoRateOptionStat,
  ShuYoRateQuestion,
  ShuYoRateQuestionStat,
  ShuYoRateReviewRecord,
  ShuYoRateUnitItem,
  ShuYoScheduleData
} from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';

export class CourseReviewService {
  private static readonly defaultQuestions: ShuYoRateQuestion[] = [
    {
      key: 'overall',
      title: '总体评价',
      multiple: false,
      required: true,
      maxSelections: 1,
      options: [
        { key: '1', label: '不太推荐' },
        { key: '2', label: '有待改进' },
        { key: '3', label: '中规中矩' },
        { key: '4', label: '值得推荐' },
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

  static buildDemoHome(schedule: ShuYoScheduleData): ShuYoRateHomeData {
    if (CourseReviewService.demoUnitsCache.length === 0) {
      CourseReviewService.initDemoUnits(schedule);
    }
    const items = [...CourseReviewService.demoUnitsCache];
    const ranked = [...CourseReviewService.demoUnitsCache];
    ranked.sort((a: ShuYoRateUnitItem, b: ShuYoRateUnitItem): number => b.average - a.average);
    return {
      recent: items,
      rankingTitle: '综合评分榜',
      rankingItems: ranked,
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

    // Recompute unit average
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

  static async fetchLiveHome(): Promise<ShuYoRateHomeData | undefined> {
    try {
      const resp = await HttpClientService.request(
        http.RequestMethod.GET,
        `${ShuYoConstants.clientBackendBaseUrl}/api/v1/rate/home`
      );
      if (resp.statusCode !== 200) {
        return undefined;
      }
      const json = JsonHelpers.parseObject(resp.body);
      if (json === undefined) {
        return undefined;
      }
      const data = JsonHelpers.asObject(json['data']) ?? json;
      const recentRaw = JsonHelpers.asArray(data['recent']);
      const recent: ShuYoRateUnitItem[] = [];
      for (let i = 0; i < recentRaw.length; i++) {
        const uObj = JsonHelpers.asObject(recentRaw[i]);
        if (uObj !== undefined) {
          recent.push(CourseReviewService.parseUnit(uObj));
        }
      }
      if (recent.length === 0) {
        return undefined;
      }
      const rankingsRaw = JsonHelpers.asArray(data['rankings']);
      const rankingItems: ShuYoRateUnitItem[] = [];
      let rankingTitle = '综合评分榜';
      if (rankingsRaw.length > 0) {
        const rObj = JsonHelpers.asObject(rankingsRaw[0]);
        rankingTitle = JsonHelpers.str(rObj, 'title', '综合评分榜');
        const rItems = JsonHelpers.asArray(rObj !== undefined ? rObj['items'] : undefined);
        for (let i = 0; i < rItems.length; i++) {
          const uObj = JsonHelpers.asObject(rItems[i]);
          if (uObj !== undefined) {
            rankingItems.push(CourseReviewService.parseUnit(uObj));
          }
        }
      }
      return {
        recent: recent,
        rankingTitle: rankingTitle,
        rankingItems: rankingItems.length > 0 ? rankingItems : recent,
        colleges: [],
        questions: CourseReviewService.defaultQuestions
      };
    } catch (_err) {
      return undefined;
    }
  }

  private static parseUnit(obj: Record<string, Object>): ShuYoRateUnitItem {
    const course = JsonHelpers.asObject(obj['course']);
    const teacher = JsonHelpers.asObject(obj['teacher']);
    return {
      id: JsonHelpers.str(obj, 'id'),
      courseId: JsonHelpers.str(course, 'id'),
      courseName: JsonHelpers.str(course, 'name', '未知课程'),
      college: JsonHelpers.str(course, 'college'),
      credits: JsonHelpers.str(course, 'credits'),
      teacherId: JsonHelpers.str(teacher, 'id'),
      teacherName: JsonHelpers.str(teacher, 'name', '未知教师'),
      reviewCount: JsonHelpers.num(obj, 'reviewCount', 0),
      average: Number(JsonHelpers.num(obj, 'average', 8.5).toFixed(1)),
      lastReviewedText: JsonHelpers.str(obj, 'lastReviewedAt', '近期'),
      tags: []
    };
  }
}
