import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoProgressCourse,
  ShuYoProgressNode,
  ShuYoProgressSummary,
  ShuYoRankingInfo
} from '../models/ShuYoModels';
import { AnnouncementService } from './AnnouncementService';
import { AuthService } from './AuthService';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';

interface ParsedNodeShell {
  id: string;
  parentId: string;
  name: string;
  requiredCredits: number;
  earnedCredits: number;
  passed: boolean;
  courseKind: string;
  isLeaf: boolean;
}

interface ParsedProgressIndex {
  studentId: string;
  gpa: string;
  plannedCourses: number;
  passedCourses: number;
  ongoingCourses: number;
  notTakenCourses: number;
  formValues: Record<string, string>;
  nodes: ParsedNodeShell[];
}

export class AcademicProgressService {
  private static readonly authRequiredPrefix: string = 'AUTH_REQUIRED:';
  private static readonly progressIndexPath: string =
    '/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?echarts=1&gnmkdm=N105515&layout=default';
  private static readonly coursePath: string =
    '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html?gnmkdm=N105515';
  private static readonly otherCoursePath: string =
    '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqFKcxx.html?gnmkdm=N105515';
  private static readonly rankingIndexPath: string =
    '/jwglxt/cjpmtj/cjpmtj_cxLnCjpmcxIndex.html?gnmkdm=N309107&layout=default';
  private static readonly rankingQueryPath: string =
    '/jwglxt/cjpmtj/cjpmtj_cxLnCjpmcxIndex.html?doType=query&gnmkdm=N309107';

  static isAuthRequiredError(msg: string): boolean {
    return msg.startsWith(AcademicProgressService.authRequiredPrefix);
  }

  static stripErrorPrefix(msg: string): string {
    if (msg.startsWith(AcademicProgressService.authRequiredPrefix)) {
      return msg.substring(AcademicProgressService.authRequiredPrefix.length);
    }
    return msg;
  }

  static emptyRanking(): ShuYoRankingInfo {
    return {
      academicYear: '',
      term: '',
      collegeName: '',
      majorName: '',
      collegeRank: 0,
      collegeCount: 0,
      majorRank: 0,
      majorCount: 0
    };
  }

  static emptyProgress(studentId: string = ''): ShuYoProgressSummary {
    return {
      studentId: studentId,
      gpa: '--',
      plannedCourses: 0,
      passedCourses: 0,
      ongoingCourses: 0,
      notTakenCourses: 0,
      nodes: [],
      ranking: AcademicProgressService.emptyRanking(),
      isLoaded: false
    };
  }

  static loadDemoProgress(): ShuYoProgressSummary {
    const basicCourses: ShuYoProgressCourse[] = [
      {
        id: 'GBK0102001',
        code: 'GBK0102001',
        name: '概率论与数理统计A',
        status: '1',
        statusLabel: '在修',
        credits: '4.0',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '学科基础课',
        hours: '理论(64)'
      },
      {
        id: 'GBK0600003',
        code: 'GBK0600003',
        name: '大学英语A(3)',
        status: '1',
        statusLabel: '在修',
        credits: '2.0',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '公共基础课',
        hours: '理论(32)'
      },
      {
        id: 'GBK2000005',
        code: 'GBK2000005',
        name: '马克思主义基本原理',
        status: '1',
        statusLabel: '在修',
        credits: '3.0',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '思想政治课',
        hours: '理论(48)'
      },
      {
        id: 'DEMO101',
        code: 'DEMO101',
        name: '大学英语A(2)',
        status: '4',
        statusLabel: '已修',
        credits: '2.0',
        grade: '88',
        gradePoint: '3.7',
        academicYear: '2025-2026',
        term: '春',
        nature: '公共基础课',
        hours: '理论(32)'
      },
      {
        id: 'DEMO104',
        code: 'DEMO104',
        name: '高等数学A(2)',
        status: '4',
        statusLabel: '已修',
        credits: '6.0',
        grade: '92',
        gradePoint: '4.0',
        academicYear: '2025-2026',
        term: '春',
        nature: '公共基础课',
        hours: '理论(96)'
      },
      {
        id: 'DEMO105',
        code: 'DEMO105',
        name: '线性代数',
        status: '4',
        statusLabel: '已修',
        credits: '4.0',
        grade: '85',
        gradePoint: '3.3',
        academicYear: '2025-2026',
        term: '秋',
        nature: '公共基础课',
        hours: '理论(64)'
      }
    ];

    const majorCourses: ShuYoProgressCourse[] = [
      {
        id: 'JBK1235001',
        code: 'JBK1235001',
        name: '面向对象程序设计',
        status: '1',
        statusLabel: '在修',
        credits: '3.5',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '专业核心课',
        hours: '理论(40)-上机(32)'
      },
      {
        id: 'JBK1235002',
        code: 'JBK1235002',
        name: '离散数学',
        status: '1',
        statusLabel: '在修',
        credits: '4.0',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '专业基础课',
        hours: '理论(64)'
      },
      {
        id: 'BBK1235002',
        code: 'BBK1235002',
        name: '数字逻辑实验',
        status: '1',
        statusLabel: '在修',
        credits: '1.0',
        grade: '',
        gradePoint: '',
        academicYear: '2026-2027',
        term: '秋',
        nature: '专业实验课',
        hours: '实验(32)'
      },
      {
        id: 'DEMO201',
        code: 'DEMO201',
        name: '程序设计基础',
        status: '4',
        statusLabel: '已修',
        credits: '4.0',
        grade: '94',
        gradePoint: '4.0',
        academicYear: '2025-2026',
        term: '秋',
        nature: '专业基础课',
        hours: '理论(40)-上机(32)'
      },
      {
        id: 'DEMO202',
        code: 'DEMO202',
        name: '数据结构与算法',
        status: '4',
        statusLabel: '已修',
        credits: '4.5',
        grade: '90',
        gradePoint: '3.7',
        academicYear: '2025-2026',
        term: '春',
        nature: '专业核心课',
        hours: '理论(56)-上机(32)'
      },
      {
        id: 'DEMO203',
        code: 'DEMO203',
        name: '操作系统',
        status: '3',
        statusLabel: '未修',
        credits: '4.0',
        grade: '',
        gradePoint: '',
        academicYear: '',
        term: '',
        nature: '专业核心课',
        hours: '理论(48)-实验(16)'
      },
      {
        id: 'DEMO204',
        code: 'DEMO204',
        name: '计算机网络',
        status: '3',
        statusLabel: '未修',
        credits: '3.5',
        grade: '',
        gradePoint: '',
        academicYear: '',
        term: '',
        nature: '专业核心课',
        hours: '理论(48)-实验(16)'
      }
    ];

    const nodes: ShuYoProgressNode[] = [
      {
        id: 'demo-basic',
        parentId: '',
        name: '公共基础课程',
        requiredCredits: 72,
        earnedCredits: 38,
        passed: false,
        courseKind: '1',
        isLeaf: true,
        courses: basicCourses
      },
      {
        id: 'demo-major',
        parentId: '',
        name: '专业核心与实践课程',
        requiredCredits: 88,
        earnedCredits: 24,
        passed: false,
        courseKind: '1',
        isLeaf: true,
        courses: majorCourses
      }
    ];

    return {
      studentId: 'DEMO0001',
      gpa: '3.65',
      plannedCourses: 40,
      passedCourses: 16,
      ongoingCourses: 6,
      notTakenCourses: 18,
      nodes: nodes,
      ranking: {
        academicYear: '2026-2027',
        term: '秋',
        collegeName: '计算机工程与科学学院',
        majorName: '计算机科学与技术',
        collegeRank: 42,
        collegeCount: 260,
        majorRank: 12,
        majorCount: 80
      },
      isLoaded: true
    };
  }

  private static resolveJwxtBaseUrl(useWebVpn: boolean): string {
    return useWebVpn
      ? 'https://https-jwxt-shu-edu-cn-443.webvpn.shu.edu.cn'
      : ShuYoConstants.jwxtBaseUrl;
  }

  private static indicatesAuthExpired(statusCode: number, body: string, location: string = ''): boolean {
    if (statusCode === 401 || statusCode === 403 || statusCode === 901) {
      return true;
    }
    const lowerLoc = location.toLowerCase();
    if (lowerLoc.includes('/oauth2/login') || lowerLoc.includes('newsso.shu.edu.cn')) {
      return true;
    }
    const lower = body.toLowerCase();
    return lower.includes('/oauth2/login') ||
      lower.includes('newsso.shu.edu.cn') ||
      lower.includes('jwglxt/xtgl/login_slogin') ||
      lower.includes('name="yhm"');
  }

  static async fetchLiveProgress(
    expectedStudentId: string,
    useWebVpn: boolean = false
  ): Promise<ShuYoProgressSummary> {
    const jwxtBase = AcademicProgressService.resolveJwxtBaseUrl(useWebVpn);
    const indexUrl = `${jwxtBase}${AcademicProgressService.progressIndexPath}`;

    let indexResp = await HttpClientService.getWithRedirects(indexUrl, 10, {
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    });
    if (AcademicProgressService.indicatesAuthExpired(indexResp.statusCode, indexResp.body, indexResp.location)) {
      const reauthed = await AuthService.trySilentAcademicReauth();
      if (reauthed) {
        indexResp = await HttpClientService.getWithRedirects(indexUrl, 10, {
          'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        });
      }
    }
    if (AcademicProgressService.indicatesAuthExpired(indexResp.statusCode, indexResp.body, indexResp.location)) {
      throw new Error(`${AcademicProgressService.authRequiredPrefix}教务系统登录已失效，请重新登录`);
    }
    if (indexResp.statusCode < 200 || indexResp.statusCode >= 300) {
      throw new Error(`教务系统学业请求失败（HTTP ${indexResp.statusCode}）`);
    }

    const index = AcademicProgressService.parseIndexHtml(indexResp.body, expectedStudentId);
    const resolvedNodes: ShuYoProgressNode[] = [];
    for (let i = 0; i < index.nodes.length; i++) {
      const s = index.nodes[i];
      resolvedNodes.push({
        id: s.id,
        parentId: s.parentId,
        name: s.name,
        requiredCredits: s.requiredCredits,
        earnedCredits: s.earnedCredits,
        passed: s.passed,
        courseKind: s.courseKind,
        isLeaf: s.isLeaf,
        courses: []
      });
    }

    const leafIndices: number[] = [];
    for (let i = 0; i < resolvedNodes.length; i++) {
      if (resolvedNodes[i].isLeaf && resolvedNodes[i].id !== 'zgzsxx') {
        leafIndices.push(i);
      }
    }

    for (let start = 0; start < leafIndices.length; start += 4) {
      const batchIndices = leafIndices.slice(start, start + 4);
      const batchCourses: ShuYoProgressCourse[][] = await Promise.all(
        batchIndices.map((idx: number): Promise<ShuYoProgressCourse[]> =>
          AcademicProgressService.fetchNodeCourses(
            jwxtBase,
            indexUrl,
            resolvedNodes[idx],
            index.studentId,
            index.formValues
          )
        )
      );
      for (let b = 0; b < batchIndices.length; b++) {
        resolvedNodes[batchIndices[b]].courses = batchCourses[b];
      }
    }

    const displayNodes: ShuYoProgressNode[] = [];
    for (let i = 0; i < resolvedNodes.length; i++) {
      const n = resolvedNodes[i];
      if (n.id === 'zgzsxx') {
        continue;
      }
      if ((n.isLeaf && n.courses.length > 0) || (n.isLeaf && n.requiredCredits > 0)) {
        displayNodes.push(n);
      }
    }
    if (displayNodes.length === 0) {
      for (let i = 0; i < resolvedNodes.length; i++) {
        const n = resolvedNodes[i];
        if (n.courses.length > 0 || n.requiredCredits > 0) {
          displayNodes.push(n);
        }
      }
    }

    const ranking = await AcademicProgressService.fetchLiveRankingSafe(jwxtBase, index.studentId);

    return {
      studentId: index.studentId,
      gpa: index.gpa.length > 0 ? index.gpa : '--',
      plannedCourses: index.plannedCourses,
      passedCourses: index.passedCourses,
      ongoingCourses: index.ongoingCourses,
      notTakenCourses: index.notTakenCourses,
      nodes: displayNodes.length > 0 ? displayNodes : resolvedNodes,
      ranking: ranking,
      isLoaded: true
    };
  }

  private static async fetchNodeCourses(
    jwxtBase: string,
    refererUrl: string,
    node: ShuYoProgressNode,
    studentId: string,
    formValues: Record<string, string>
  ): Promise<ShuYoProgressCourse[]> {
    const path = node.courseKind === '1'
      ? AcademicProgressService.coursePath
      : AcademicProgressService.otherCoursePath;
    const url = `${jwxtBase}${path}`;

    const parts: string[] = [
      'fromXh_id=',
      `xfyqjd_id=${encodeURIComponent(node.id)}`,
      `xh_id=${encodeURIComponent(studentId)}`
    ];
    if (node.id === 'qtkcxfyq') {
      const extraKeys: string[] = [
        'cjlrxn',
        'cjlrxq',
        'bkcjlrxn',
        'bkcjlrxq',
        'xscjcxkz',
        'cjcxkzzt',
        'cjztkz',
        'cjzt'
      ];
      for (let i = 0; i < extraKeys.length; i++) {
        const k = extraKeys[i];
        const v = formValues[k] ?? '';
        parts.push(`${k}=${encodeURIComponent(v)}`);
      }
    }

    const resp = await HttpClientService.request(
      http.RequestMethod.POST,
      url,
      {
        'accept': 'application/json, text/javascript, */*; q=0.01',
        'referer': refererUrl,
        'origin': jwxtBase,
        'x-requested-with': 'XMLHttpRequest',
        'content-type': 'application/x-www-form-urlencoded;charset=UTF-8'
      },
      parts.join('&')
    );

    if (AcademicProgressService.indicatesAuthExpired(resp.statusCode, resp.body, resp.location)) {
      throw new Error(`${AcademicProgressService.authRequiredPrefix}教务系统登录已失效，请重新登录`);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`学业课程请求失败（HTTP ${resp.statusCode}）`);
    }

    const arr = JsonHelpers.parseArray(resp.body);
    const out: ShuYoProgressCourse[] = [];
    for (let i = 0; i < arr.length; i++) {
      const row = JsonHelpers.asObject(arr[i]);
      if (row === undefined) {
        continue;
      }
      const status = JsonHelpers.str(row, 'XDZT', '3');
      const code = JsonHelpers.str(row, 'KCH', '');
      const kchId = JsonHelpers.str(row, 'KCH_ID', '');
      out.push({
        id: kchId.length > 0 ? kchId : (code.length > 0 ? code : `${node.id}-c-${i}`),
        code: code,
        name: JsonHelpers.str(row, 'KCMC', '未命名课程'),
        status: status,
        statusLabel: AcademicProgressService.statusLabel(status),
        credits: JsonHelpers.str(row, 'XF', JsonHelpers.str(row, 'JHXF', '0')),
        grade: JsonHelpers.str(row, 'CJ', JsonHelpers.str(row, 'MAXCJ', '')),
        gradePoint: JsonHelpers.str(row, 'JD', ''),
        academicYear: JsonHelpers.str(row, 'CJXNMC', JsonHelpers.str(row, 'XNMC', '')),
        term: JsonHelpers.str(row, 'CJXQMC', JsonHelpers.str(row, 'XQMMC', '')),
        nature: JsonHelpers.str(row, 'KCXZMC', JsonHelpers.str(row, 'KCLBMC', '')),
        hours: JsonHelpers.str(row, 'XSXXXX', '')
      });
    }
    return out;
  }

  private static async fetchLiveRankingSafe(
    jwxtBase: string,
    studentId: string
  ): Promise<ShuYoRankingInfo> {
    try {
      const indexUrl = `${jwxtBase}${AcademicProgressService.rankingIndexPath}`;
      const queryUrl = `${jwxtBase}${AcademicProgressService.rankingQueryPath}`;
      const idxResp = await HttpClientService.getWithRedirects(indexUrl, 8, {
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      });
      if (AcademicProgressService.indicatesAuthExpired(idxResp.statusCode, idxResp.body, idxResp.location)) {
        return AcademicProgressService.emptyRanking();
      }
      const bodyStr =
        `_search=false&nd=${Date.now()}&queryModel.showCount=15&queryModel.currentPage=1` +
        '&queryModel.sortName=+&queryModel.sortOrder=asc&time=0';
      const queryResp = await HttpClientService.request(
        http.RequestMethod.POST,
        queryUrl,
        {
          'accept': 'application/json, text/javascript, */*; q=0.01',
          'referer': indexUrl,
          'origin': jwxtBase,
          'x-requested-with': 'XMLHttpRequest',
          'content-type': 'application/x-www-form-urlencoded;charset=UTF-8'
        },
        bodyStr
      );
      if (queryResp.statusCode < 200 || queryResp.statusCode >= 300) {
        return AcademicProgressService.emptyRanking();
      }
      const obj = JsonHelpers.parseObject(queryResp.body);
      if (obj === undefined) {
        return AcademicProgressService.emptyRanking();
      }
      const rawItems = JsonHelpers.asArray(obj['items']);
      const matches: Record<string, Object>[] = [];
      for (let i = 0; i < rawItems.length; i++) {
        const item = JsonHelpers.asObject(rawItems[i]);
        if (item === undefined) {
          continue;
        }
        const xhId = JsonHelpers.str(item, 'xh_id').trim();
        const xh = JsonHelpers.str(item, 'xh').trim();
        const itemStuId = xhId.length > 0 ? xhId : xh;
        if (studentId.length === 0 || itemStuId.length === 0 || itemStuId === studentId) {
          matches.push(item);
        }
      }
      if (matches.length === 0) {
        return AcademicProgressService.emptyRanking();
      }
      matches.sort((a: Record<string, Object>, b: Record<string, Object>): number => {
        const ka = AcademicProgressService.rankingSortKey(a);
        const kb = AcademicProgressService.rankingSortKey(b);
        if (kb > ka) {
          return 1;
        }
        if (kb < ka) {
          return -1;
        }
        return 0;
      });
      const top = matches[0];
      return {
        academicYear: JsonHelpers.str(top, 'xnmc', ''),
        term: JsonHelpers.str(top, 'xqmc', ''),
        collegeName: JsonHelpers.str(top, 'jgmc', JsonHelpers.str(top, 'zsxymc', '')),
        majorName: JsonHelpers.str(top, 'xxzymc', JsonHelpers.str(top, 'zymc', '')),
        collegeRank: Math.max(0, JsonHelpers.num(top, 'njjgpjjdpm', 0)),
        collegeCount: Math.max(0, JsonHelpers.num(top, 'njjgrs', 0)),
        majorRank: Math.max(0, JsonHelpers.num(top, 'njxxzypjjdpm', 0)),
        majorCount: Math.max(0, JsonHelpers.num(top, 'njxxzyrs', 0))
      };
    } catch (_err) {
      return AcademicProgressService.emptyRanking();
    }
  }

  private static rankingSortKey(item: Record<string, Object>): string {
    const year = JsonHelpers.num(item, 'xnm', 0);
    const term = JsonHelpers.num(item, 'xqm', 0);
    const yStr = String(year).padStart(4, '0');
    const tStr = String(term).padStart(3, '0');
    return `${yStr}-${tStr}-${JsonHelpers.str(item, 'czsj', '')}`;
  }

  private static parseIndexHtml(source: string, expectedStudentId: string): ParsedProgressIndex {
    const formValues: Record<string, string> = {};
    const formMatch = new RegExp('<form\\b[^>]*id=["\']form["\'][^>]*>([\\s\\S]*?)<\\/form>', 'i').exec(source);
    const formArea = formMatch !== null ? formMatch[1] : source;
    const inputRe = new RegExp('<input\\b([^>]*)>', 'gi');
    let inMatch = inputRe.exec(formArea);
    while (inMatch !== null) {
      const attrs = inMatch[1];
      const nameMatch = new RegExp('\\bname\\s*=\\s*["\']([^"\']+)["\']', 'i').exec(attrs);
      if (nameMatch !== null) {
        const valMatch = new RegExp('\\bvalue\\s*=\\s*["\']([^"\']*)["\']', 'i').exec(attrs);
        formValues[nameMatch[1]] = valMatch !== null ? valMatch[1] : '';
      }
      inMatch = inputRe.exec(formArea);
    }

    const formStuId = (formValues['xh_id'] ?? '').trim();
    const studentId = formStuId.length > 0 ? formStuId : expectedStudentId.trim();
    if (studentId.length === 0) {
      throw new Error('教务系统未返回学号，无法同步学业信息');
    }

    const alertMatch = new RegExp('<[^>]*id=["\']alertBox["\'][^>]*>([\\s\\S]*?)<\\/div>', 'i').exec(source);
    const summaryText = alertMatch !== null ? alertMatch[1] : source;
    const summaryClean = summaryText.replace(new RegExp('<[^>]+>', 'g'), ' ');

    const gpaMatch = new RegExp('GPA[）)\\s]*[：:]?\\s*(\\d+(?:\\.\\d+)?)').exec(summaryClean);
    const plannedMatch = new RegExp('计划总课程\\s*(\\d+)').exec(summaryClean);
    const passedMatch = new RegExp('通过\\s*(\\d+)').exec(summaryClean);
    const ongoingMatch = new RegExp('在读\\s*(\\d+)').exec(summaryClean);
    const notTakenMatch = new RegExp('未修\\s*(\\d+)').exec(summaryClean);

    const nodes: ParsedNodeShell[] = [];
    const seen = new Set<string>();
    const nodePattern = new RegExp("<li\\s+id='li([^']+)'[^\\n]*?fxfyqjd_id='([^']*)'", 'g');
    const literalPattern = new RegExp('"([^"<>+]{1,100})"', 'g');

    let nm = nodePattern.exec(source);
    while (nm !== null) {
      const id = nm[1];
      const parentId = nm[2];
      if (seen.has(id) || id === 'zgzsxx' || id === 'cxcyqkxfyq') {
        nm = nodePattern.exec(source);
        continue;
      }
      const matchEnd = nm.index + nm[0].length;
      const sliceEnd = Math.min(source.length, matchEnd + 1500);
      const fragment = source.substring(matchEnd, sliceEnd);
      const escId = AcademicProgressService.escapeRegExp(id);

      const titleMatch = new RegExp(
        `xfyqjd_id='${escId}'\\s+jdkcsx='([^']*)'\\s+leaf='([^']*)'\\s+sfmjd='([^']*)'`
      ).exec(fragment);
      const creditsMatch = new RegExp(
        `id='p${escId}'\\s+yxxf='([^']*)'\\s+yqzdxf='([^']*)'\\s+sftg='([^']*)'>`
      ).exec(fragment);

      if (titleMatch !== null && creditsMatch !== null) {
        const nameStart = creditsMatch.index + creditsMatch[0].length;
        const nameSource = fragment.substring(nameStart, Math.min(fragment.length, nameStart + 180));
        let nodeName = '';
        literalPattern.lastIndex = 0;
        let lm = literalPattern.exec(nameSource);
        while (lm !== null) {
          const candidate = AnnouncementService.decodeEntities(lm[1])
            .replace(new RegExp('\\u00a0', 'g'), ' ')
            .trim();
          if (candidate.length > 0 && !candidate.includes(':') && !candidate.includes('$')) {
            nodeName = candidate;
            break;
          }
          lm = literalPattern.exec(nameSource);
        }
        if (nodeName.length > 0) {
          seen.add(id);
          const earned = Number.parseFloat(creditsMatch[1]);
          const required = Number.parseFloat(creditsMatch[2]);
          nodes.push({
            id: id,
            parentId: parentId,
            name: nodeName,
            requiredCredits: Number.isFinite(required) ? required : 0,
            earnedCredits: Number.isFinite(earned) ? earned : 0,
            passed: creditsMatch[3] === '1',
            courseKind: titleMatch[1],
            isLeaf: titleMatch[3] === '1'
          });
        }
      }
      nm = nodePattern.exec(source);
    }

    if (nodes.length === 0) {
      throw new Error('未能从教务系统解析学业修读结构，请稍后重试');
    }

    return {
      studentId: studentId,
      gpa: gpaMatch !== null ? gpaMatch[1] : '--',
      plannedCourses: plannedMatch !== null ? parseInt(plannedMatch[1], 10) : 0,
      passedCourses: passedMatch !== null ? parseInt(passedMatch[1], 10) : 0,
      ongoingCourses: ongoingMatch !== null ? parseInt(ongoingMatch[1], 10) : 0,
      notTakenCourses: notTakenMatch !== null ? parseInt(notTakenMatch[1], 10) : 0,
      formValues: formValues,
      nodes: nodes
    };
  }

  private static escapeRegExp(text: string): string {
    return text.replace(new RegExp('[.*+?^${}()|[\\]\\\\]', 'g'), '\\$&');
  }

  static statusLabel(statusCode: string): string {
    if (statusCode === '1') {
      return '在修';
    }
    if (statusCode === '2') {
      return '未通过';
    }
    if (statusCode === '4') {
      return '已修';
    }
    return '未修';
  }
}
