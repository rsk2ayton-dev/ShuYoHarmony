export enum ShuYoTabId {
  HOME = 'home',
  RATE = 'rate',
  PROGRESS = 'progress',
  SCHEDULE = 'schedule'
}

export enum ShuYoCampusSystem {
  UNDERGRADUATE = 'undergraduate',
  GRADUATE = 'graduate'
}

export interface ShuYoAcademicTerm {
  yearCode: string;
  termCode: string;
  academicYearName: string;
  termName: string;
  studentName: string;
  studentId: string;
  className: string;
}

export interface ShuYoCourseSession {
  id: string;
  courseName: string;
  courseCode: string;
  teachingClassId: string;
  teacherName: string;
  campus: string;
  location: string;
  weekday: number;
  startSection: number;
  endSection: number;
  sections: number[];
  weeks: number[];
  weekText: string;
  credit: string;
  note: string;
  isManual: boolean;
}

export interface ShuYoUntimedCourse {
  id: string;
  courseName: string;
  teacherName: string;
  campus: string;
  weeks: number[];
  weekText: string;
  summary: string;
  credit: string;
}

export interface ShuYoScheduleData {
  term: ShuYoAcademicTerm;
  sessions: ShuYoCourseSession[];
  untimedCourses: ShuYoUntimedCourse[];
  fetchedAt: string;
  maxWeek: number;
}

export interface ShuYoScheduleCollection {
  id: string;
  title: string;
  schedule: ShuYoScheduleData;
  isPrimary: boolean;
  updatedAt: string;
}

export interface ShuYoProgressCourse {
  id: string;
  code: string;
  name: string;
  status: string; // '1'=在修, '2'=未通过/待修, '3'=未修, '4'=已修
  statusLabel: string;
  credits: string;
  grade: string;
  gradePoint: string;
  academicYear: string;
  term: string;
  nature: string;
  hours: string;
}

export interface ShuYoProgressNode {
  id: string;
  name: string;
  requiredCredits: number;
  earnedCredits: number;
  passed: boolean;
  courses: ShuYoProgressCourse[];
}

export interface ShuYoRankingInfo {
  academicYear: string;
  term: string;
  collegeName: string;
  majorName: string;
  collegeRank: number;
  collegeCount: number;
  majorRank: number;
  majorCount: number;
}

export interface ShuYoProgressSummary {
  studentId: string;
  gpa: string;
  plannedCourses: number;
  passedCourses: number;
  ongoingCourses: number;
  notTakenCourses: number;
  nodes: ShuYoProgressNode[];
  ranking: ShuYoRankingInfo;
}

export interface ShuYoAnnouncementBlock {
  blockType: string;
  blockValue: string;
}

export interface ShuYoAnnouncementItem {
  id: string;
  title: string;
  url: string;
  summary: string;
  dateText: string;
  sourceName: string;
  author: string;
  department: string;
  blocks: ShuYoAnnouncementBlock[];
}

export interface ShuYoClassroomBuilding {
  id: number;
  name: string;
  fullName: string;
  campusName: string;
}

export interface ShuYoClassroomSection {
  index: number;
  startTime: string;
  endTime: string;
}

export interface ShuYoClassroomCourseSlot {
  courseName: string;
  teacherName: string;
  startSection: number;
  endSection: number;
}

export interface ShuYoClassroomRoom {
  id: number;
  name: string;
  floorName: string;
  courseSlots: ShuYoClassroomCourseSlot[];
}

export interface ShuYoCampusCardInfo {
  studentId: string;
  holderName: string;
  cardStatus: string;
  balance: number;
  validUntil: string;
  isLoaded: boolean;
}

export interface ShuYoCampusCardBill {
  id: string;
  merchantName: string;
  payTime: string;
  amount: number;
}

export interface ShuYoDailySpending {
  dateLabel: string;
  totalAmount: number;
}

export interface ShuYoLibraryVenue {
  id: string;
  name: string;
  campusName: string;
  areaNames: string[];
}

export interface ShuYoLibrarySeat {
  id: string;
  seatLabel: string;
  areaId: string;
  isBusy: boolean;
  isDisabled: boolean;
  isBooked: boolean;
}

export interface ShuYoLibraryArea {
  id: string;
  name: string;
  totalCount: number;
  freeCount: number;
  seats: ShuYoLibrarySeat[];
}

export interface ShuYoLibraryBookingRecord {
  id: string;
  venueId: string;
  venueName: string;
  areaId: string;
  areaName: string;
  seatId: string;
  seatLabel: string;
  day: string;
  beginTime: string;
  endTime: string;
  status: string;
}

export interface ShuYoMapPoint {
  x: number;
  y: number;
}

export interface ShuYoMapView {
  zoom: number;
  center: ShuYoMapPoint;
}

export interface ShuYoCampusInfo {
  id: string;
  name: string;
  assetPath: string;
  viewBox: number[];
  initialView: ShuYoMapView;
  backgroundColor: string;
}

export interface ShuYoMapFact {
  factLabel: string;
  factValue: string;
}

export interface ShuYoCampusMapPlace {
  id: string;
  campusId: string;
  name: string;
  kind: string;
  address: string;
  description: string;
  aliases: string[];
  featureIds: string[];
  facts: ShuYoMapFact[];
  hasPoint: boolean;
  pointX: number;
  pointY: number;
}

export interface ShuYoCampusMapData {
  version: string;
  campuses: ShuYoCampusInfo[];
  places: ShuYoCampusMapPlace[];
}

export interface ShuYoOtpToken {
  code: string;
  account: string;
  remaining: number;
  period: number;
}

export interface ShuYoRateOption {
  key: string;
  label: string;
}

export interface ShuYoRateQuestion {
  key: string;
  title: string;
  multiple: boolean;
  required: boolean;
  maxSelections: number;
  options: ShuYoRateOption[];
}

export interface ShuYoRateOptionStat {
  key: string;
  label: string;
  count: number;
  percent: number;
  isTop: boolean;
}

export interface ShuYoRateQuestionStat {
  key: string;
  title: string;
  answered: number;
  options: ShuYoRateOptionStat[];
}

export interface ShuYoRateUnitItem {
  id: string;
  courseId: string;
  courseName: string;
  college: string;
  credits: string;
  teacherId: string;
  teacherName: string;
  reviewCount: number;
  average: number;
  lastReviewedText: string;
  tags: string[];
}

export interface ShuYoRateReviewRecord {
  id: string;
  unitId: string;
  overall: number;
  answers: Record<string, string[]>;
  comment: string;
  updatedAt: string;
}

export interface ShuYoRateHomeData {
  recent: ShuYoRateUnitItem[];
  rankingTitle: string;
  rankingItems: ShuYoRateUnitItem[];
  colleges: string[];
  questions: ShuYoRateQuestion[];
}

export enum ShuYoHomeModuleId {
  TODAY_COURSE = 'today_course',
  CAMPUS_CARD = 'campus_card',
  ANNOUNCEMENTS = 'announcements',
  CAMPUS_TOOLS = 'campus_tools'
}

export interface ShuYoHomeLayoutItem {
  id: ShuYoHomeModuleId;
  title: string;
  subtitle: string;
  enabled: boolean;
}

export interface ShuYoContributor {
  login: string;
  displayName: string;
  avatarUrl: string;
  profileUrl: string;
  commits: number;
  additions: number;
  deletions: number;
}

// Navigation Route Parameter Interfaces (ArkTS strict typing, no inline object literals in pushDestination)
export interface ShuYoRateDetailParam {
  unitId: string;
}

export interface ShuYoRatePublishParam {
  unitId: string;
  courseName: string;
  teacherName: string;
}

export interface ShuYoScheduleEditorParam {
  sessionId: string;
  defaultWeekday: number;
}

export interface ShuYoLoginPageParam {
  sourceLabel: string;
}

export interface ShuYoEmptyParam {
  tag: string;
}

export interface ShuYoVodTerm {
  id: number;
  name: string;
  academicYear: string;
  termNumber: number;
  isCurrent: boolean;
  academicYearLabel: string;
  seasonLabel: string;
  startDateMs: number;
  endDateMs: number;
  teachingWeekCount: number;
}

export interface ShuYoVodCourse {
  teachingClassId: number;
  termId: number;
  name: string;
  teachingClassName: string;
  code: string;
  teacherNames: string[];
  teacherLabel: string;
  lessonCount: number;
  coverUrl: string;
  isLive: boolean;
  liveLessonId: number;
}

export interface ShuYoVodLesson {
  id: number;
  teachingClassId: number;
  name: string;
  courseName: string;
  courseCode: string;
  teacherLabel: string;
  beginTimeMs: number;
  endTimeMs: number;
  dateLabel: string;
  timeRangeLabel: string;
  weekNumber: number;
  weekday: number;
  sectionNumber: number;
  sectionLabel: string;
  classroom: string;
  watchPercent: string;
  isPlayable: boolean;
  isLive: boolean;
  isLiveAvailable: boolean;
  isGenerating: boolean;
  isListed: boolean;
  statusLabel: string;
}

export interface ShuYoVodView {
  viewNumber: number;
  label: string;
  url: string;
}

export interface ShuYoVodPlayback {
  lessonId: number;
  teachingClassId: number;
  title: string;
  views: ShuYoVodView[];
  lastPositionSec: number;
  isLive: boolean;
  description: string;
}

export interface ShuYoVodPptSlide {
  id: string;
  imageUrl: string;
  positionSec: number;
  timeLabel: string;
  text: string;
}

export interface ShuYoVodPlayerParam {
  teachingClassId: number;
  termId: number;
  courseName: string;
  courseCode: string;
  teacherLabel: string;
  initialLessonId: number;
  isLive: boolean;
  fromSearch: boolean;
}
