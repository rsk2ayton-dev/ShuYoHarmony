import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { ShuYoColorPalette, ShuYoThemes } from '../core/ShuYoTheme';
import { ShuYoCourseSession, ShuYoScheduleData } from '../models/ShuYoModels';
import { JsonHelpers } from './JsonHelpers';
import { PreferencesService } from './PreferencesService';
import { ScheduleService } from './ScheduleService';

export interface ShuYoWidgetSnapshot {
  headerTitle: string;
  dateLabel: string;
  summaryText: string;
  moreCountText: string;
  updatedAt: string;
  cardAccentColor: string;
  cardBgColor: string;
  cardSubBgColor: string;
  cardTextColor: string;
  cardSubTextColor: string;
  hasCourse1: boolean;
  course1Name: string;
  course1Meta: string;
  course1Color: string;
  hasCourse2: boolean;
  course2Name: string;
  course2Meta: string;
  course2Color: string;
  hasCourse3: boolean;
  course3Name: string;
  course3Meta: string;
  course3Color: string;
}

/**
 * Coordinates Form Kit widget snapshot persistence and active widget refreshes.
 */
export class ScheduleWidgetService {
  private static readonly snapshotKey: string = 'shuyo_widget_snapshot_v1';

  private static pad2(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }

  static buildSnapshot(
    schedule: ShuYoScheduleData,
    termStartDate: string,
    maxWeek: number,
    colors: ShuYoColorPalette,
    isDemoMode: boolean
  ): ShuYoWidgetSnapshot {
    const now = new Date();
    const todayStr = ScheduleService.getTodayDateStr();
    const rawWeek = ScheduleService.computeWeekFromStart(termStartDate, todayStr);
    const jsDay = now.getDay();
    const weekday = jsDay === 0 ? 7 : jsDay;
    const weekdayLabel = ShuYoConstants.weekdayLabels[weekday - 1];
    const weekLabel = rawWeek >= 1 && rawWeek <= maxWeek
      ? `第${rawWeek}周`
      : (rawWeek < 1 ? '未开学' : '假期中');
    const dateLabel = `${now.getMonth() + 1}月${now.getDate()}日 ${weekdayLabel} · ${weekLabel}`;
    const updatedAt = `${ScheduleWidgetService.pad2(now.getHours())}:${ScheduleWidgetService.pad2(now.getMinutes())}`;

    const todaySessions: ShuYoCourseSession[] = [];
    if (isDemoMode || (rawWeek >= 1 && rawWeek <= maxWeek)) {
      const targetWeek = rawWeek >= 1 && rawWeek <= maxWeek ? rawWeek : 1;
      for (let i = 0; i < schedule.sessions.length; i++) {
        const s = schedule.sessions[i];
        if (s.weekday === weekday && (s.weeks.length === 0 || s.weeks.includes(targetWeek))) {
          todaySessions.push(s);
        }
      }
      todaySessions.sort((a: ShuYoCourseSession, b: ShuYoCourseSession): number => a.startSection - b.startSection);
    }

    let summaryText = '';
    if (schedule.sessions.length === 0) {
      summaryText = '打开 SHU友 同步课表后自动显示';
    } else if (!isDemoMode && (rawWeek < 1 || rawWeek > maxWeek)) {
      summaryText = rawWeek < 1 ? '本学期尚未开始，注意休息' : '当前不在教学周内';
    } else if (todaySessions.length === 0) {
      summaryText = '今日无排课，享受自由时光';
    } else {
      summaryText = `今日共 ${todaySessions.length} 节课程`;
    }

    const moreCountText = todaySessions.length > 3
      ? `还有 ${todaySessions.length - 3} 节课程`
      : (todaySessions.length > 0 ? `今日共 ${todaySessions.length} 节` : '点击查看周课表');

    const formatMeta = (s: ShuYoCourseSession): string => {
      const timeRange = ShuYoConstants.getPeriodTimeText(s.startSection, s.endSection);
      const room = s.location.length > 0 ? s.location : '待定教室';
      return timeRange.length > 0 ? `${timeRange} · ${room}` : `第${s.startSection}-${s.endSection}节 · ${room}`;
    };

    const s1 = todaySessions.length > 0 ? todaySessions[0] : undefined;
    const s2 = todaySessions.length > 1 ? todaySessions[1] : undefined;
    const s3 = todaySessions.length > 2 ? todaySessions[2] : undefined;

    return {
      headerTitle: isDemoMode ? 'SHU友 · 演示课表' : 'SHU友 今日课表',
      dateLabel: dateLabel,
      summaryText: summaryText,
      moreCountText: moreCountText,
      updatedAt: updatedAt,
      cardAccentColor: colors.accent,
      cardBgColor: colors.surface,
      cardSubBgColor: colors.surfaceAlt,
      cardTextColor: colors.textPrimary,
      cardSubTextColor: colors.textTertiary,
      hasCourse1: s1 !== undefined,
      course1Name: s1 !== undefined ? s1.courseName : '',
      course1Meta: s1 !== undefined ? formatMeta(s1) : '',
      course1Color: s1 !== undefined ? ShuYoThemes.courseColorFor(s1.courseName) : colors.accent,
      hasCourse2: s2 !== undefined,
      course2Name: s2 !== undefined ? s2.courseName : '',
      course2Meta: s2 !== undefined ? formatMeta(s2) : '',
      course2Color: s2 !== undefined ? ShuYoThemes.courseColorFor(s2.courseName) : colors.accent,
      hasCourse3: s3 !== undefined,
      course3Name: s3 !== undefined ? s3.courseName : '',
      course3Meta: s3 !== undefined ? formatMeta(s3) : '',
      course3Color: s3 !== undefined ? ShuYoThemes.courseColorFor(s3.courseName) : colors.accent
    };
  }

  static persistSnapshot(
    schedule: ShuYoScheduleData,
    termStartDate: string,
    maxWeek: number,
    colors: ShuYoColorPalette,
    isDemoMode: boolean
  ): void {
    const snap = ScheduleWidgetService.buildSnapshot(schedule, termStartDate, maxWeek, colors, isDemoMode);
    PreferencesService.setString(ScheduleWidgetService.snapshotKey, JSON.stringify(snap));
  }

  private static readSnapshotOrFallback(): ShuYoWidgetSnapshot {
    const fallbackColors = ShuYoThemes.byId(ShuYoThemes.defaultId).colors;
    const raw = PreferencesService.getString(ScheduleWidgetService.snapshotKey, '');
    if (raw.length > 0) {
      const obj = JsonHelpers.parseObject(raw);
      if (obj !== undefined) {
        return {
          headerTitle: JsonHelpers.str(obj, 'headerTitle', 'SHU友 今日课表'),
          dateLabel: JsonHelpers.str(obj, 'dateLabel', '今日课程'),
          summaryText: JsonHelpers.str(obj, 'summaryText', '打开应用查看完整课表'),
          moreCountText: JsonHelpers.str(obj, 'moreCountText', '点击查看周课表'),
          updatedAt: JsonHelpers.str(obj, 'updatedAt', '--:--'),
          cardAccentColor: JsonHelpers.str(obj, 'cardAccentColor', fallbackColors.accent),
          cardBgColor: JsonHelpers.str(obj, 'cardBgColor', fallbackColors.surface),
          cardSubBgColor: JsonHelpers.str(obj, 'cardSubBgColor', fallbackColors.surfaceAlt),
          cardTextColor: JsonHelpers.str(obj, 'cardTextColor', fallbackColors.textPrimary),
          cardSubTextColor: JsonHelpers.str(obj, 'cardSubTextColor', fallbackColors.textTertiary),
          hasCourse1: JsonHelpers.bool(obj, 'hasCourse1', false),
          course1Name: JsonHelpers.str(obj, 'course1Name', ''),
          course1Meta: JsonHelpers.str(obj, 'course1Meta', ''),
          course1Color: JsonHelpers.str(obj, 'course1Color', fallbackColors.accent),
          hasCourse2: JsonHelpers.bool(obj, 'hasCourse2', false),
          course2Name: JsonHelpers.str(obj, 'course2Name', ''),
          course2Meta: JsonHelpers.str(obj, 'course2Meta', ''),
          course2Color: JsonHelpers.str(obj, 'course2Color', fallbackColors.accent),
          hasCourse3: JsonHelpers.bool(obj, 'hasCourse3', false),
          course3Name: JsonHelpers.str(obj, 'course3Name', ''),
          course3Meta: JsonHelpers.str(obj, 'course3Meta', ''),
          course3Color: JsonHelpers.str(obj, 'course3Color', fallbackColors.accent)
        };
      }
    }

    return ScheduleWidgetService.buildSnapshot(
      ScheduleService.emptySchedule(''),
      '2026-09-14',
      18,
      fallbackColors,
      false
    );
  }

  static buildFormBindingDataFromPrefs(): formBindingData.FormBindingData {
    const snap = ScheduleWidgetService.readSnapshotOrFallback();
    const record: Record<string, Object> = {
      'headerTitle': snap.headerTitle,
      'dateLabel': snap.dateLabel,
      'summaryText': snap.summaryText,
      'moreCountText': snap.moreCountText,
      'updatedAt': snap.updatedAt,
      'cardAccentColor': snap.cardAccentColor,
      'cardBgColor': snap.cardBgColor,
      'cardSubBgColor': snap.cardSubBgColor,
      'cardTextColor': snap.cardTextColor,
      'cardSubTextColor': snap.cardSubTextColor,
      'hasCourse1': snap.hasCourse1,
      'course1Name': snap.course1Name,
      'course1Meta': snap.course1Meta,
      'course1Color': snap.course1Color,
      'hasCourse2': snap.hasCourse2,
      'course2Name': snap.course2Name,
      'course2Meta': snap.course2Meta,
      'course2Color': snap.course2Color,
      'hasCourse3': snap.hasCourse3,
      'course3Name': snap.course3Name,
      'course3Meta': snap.course3Meta,
      'course3Color': snap.course3Color
    };
    return formBindingData.createFormBindingData(record);
  }

  static async reloadWidgets(context: common.UIAbilityContext | undefined): Promise<number> {
    if (context === undefined) {
      return 0;
    }
    try {
      return await formProvider.reloadForms(context, 'entry', 'EntryFormAbility', 'schedule_widget');
    } catch (_err) {
      return 0;
    }
  }
}
