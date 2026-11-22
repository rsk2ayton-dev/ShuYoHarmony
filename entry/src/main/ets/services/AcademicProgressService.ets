import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoProgressCourse,
  ShuYoProgressNode,
  ShuYoProgressSummary
} from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';

export class AcademicProgressService {
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
        name: '公共基础课程',
        requiredCredits: 72,
        earnedCredits: 38,
        passed: false,
        courses: basicCourses
      },
      {
        id: 'demo-major',
        name: '专业核心与实践课程',
        requiredCredits: 88,
        earnedCredits: 24,
        passed: false,
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
      }
    };
  }

  static async fetchLiveProgress(): Promise<ShuYoProgressSummary> {
    const indexUrl = `${ShuYoConstants.jwxtBaseUrl}/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default`;
    const resp = await HttpClientService.getWithRedirects(indexUrl, 8);
    if (resp.body.includes('oauth2/login') || resp.statusCode === 401 || resp.statusCode === 403) {
      throw new Error('教务系统登录已失效，请重新登录');
    }
    const gpaMatch = new RegExp('GPA[）)\\s]*[：:]?\\s*(\\d+(?:\\.\\d+)?)').exec(resp.body);
    const plannedMatch = new RegExp('计划总课程\\s*(\\d+)').exec(resp.body);
    const passedMatch = new RegExp('通过\\s*(\\d+)').exec(resp.body);
    const ongoingMatch = new RegExp('在读\\s*(\\d+)').exec(resp.body);
    const notTakenMatch = new RegExp('未修\\s*(\\d+)').exec(resp.body);

    const demo = AcademicProgressService.loadDemoProgress();
    if (gpaMatch === null && plannedMatch === null) {
      throw new Error('未能从教务系统解析学业修读页面');
    }
    return {
      studentId: demo.studentId,
      gpa: gpaMatch !== null ? gpaMatch[1] : demo.gpa,
      plannedCourses: plannedMatch !== null ? parseInt(plannedMatch[1], 10) : demo.plannedCourses,
      passedCourses: passedMatch !== null ? parseInt(passedMatch[1], 10) : demo.passedCourses,
      ongoingCourses: ongoingMatch !== null ? parseInt(ongoingMatch[1], 10) : demo.ongoingCourses,
      notTakenCourses: notTakenMatch !== null ? parseInt(notTakenMatch[1], 10) : demo.notTakenCourses,
      nodes: demo.nodes,
      ranking: demo.ranking
    };
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
