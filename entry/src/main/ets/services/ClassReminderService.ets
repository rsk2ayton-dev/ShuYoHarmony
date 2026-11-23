import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { ShuYoCourseSession, ShuYoScheduleData } from '../models/ShuYoModels';
import { JsonHelpers } from './JsonHelpers';
import { PreferencesService } from './PreferencesService';
import { ScheduleService } from './ScheduleService';

interface ShuYoReminderCandidate {
  triggerMs: number;
  session: ShuYoCourseSession;
  timeRangeText: string;
}

/**
 * Manages class reminder notifications using @kit.BackgroundTasksKit (reminderAgentManager)
 * and notification permission negotiation via @kit.NotificationKit.
 */
export class ClassReminderService {
  private static readonly keyEnabled: string = 'shuyo_reminder_enabled_v1';
  private static readonly keyLeadMinutes: string = 'shuyo_reminder_lead_min_v1';
  private static readonly keyPublishedIds: string = 'shuyo_reminder_ids_v1';
  private static readonly maxReminders: number = 20;

  static isEnabled(): boolean {
    return PreferencesService.getBoolean(ClassReminderService.keyEnabled, false);
  }

  static getLeadMinutes(): number {
    const saved = PreferencesService.getNumber(ClassReminderService.keyLeadMinutes, 15);
    if (saved >= 5 && saved <= 60) {
      return saved;
    }
    return 15;
  }

  static setLeadMinutes(mins: number): void {
    const clamped = Math.max(5, Math.min(60, mins));
    PreferencesService.setNumber(ClassReminderService.keyLeadMinutes, clamped);
  }

  private static loadStoredIds(): number[] {
    const raw = PreferencesService.getString(ClassReminderService.keyPublishedIds, '');
    if (raw.length === 0) {
      return [];
    }
    const arr = JsonHelpers.parseArray(raw);
    const out: number[] = [];
    for (let i = 0; i < arr.length; i++) {
      const id = Number(arr[i]);
      if (Number.isFinite(id) && id > 0) {
        out.push(id);
      }
    }
    return out;
  }

  private static saveStoredIds(ids: number[]): void {
    if (ids.length === 0) {
      PreferencesService.remove(ClassReminderService.keyPublishedIds);
    } else {
      PreferencesService.setString(ClassReminderService.keyPublishedIds, JSON.stringify(ids));
    }
  }

  static async cancelScheduledReminders(): Promise<void> {
    const ids = ClassReminderService.loadStoredIds();
    for (let i = 0; i < ids.length; i++) {
      try {
        await reminderAgentManager.cancelReminder(ids[i]);
      } catch (_err) {
        // Ignore already expired/removed reminders
      }
    }
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (_err) {
      // Ignore if unavailable on Previewer
    }
    ClassReminderService.saveStoredIds([]);
  }

  static async disableAll(): Promise<string> {
    PreferencesService.setBoolean(ClassReminderService.keyEnabled, false);
    await ClassReminderService.cancelScheduledReminders();
    return '已关闭课前提醒';
  }

  private static async ensureNotificationEnabled(context: common.UIAbilityContext | undefined): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      if (context !== undefined) {
        await notificationManager.requestEnableNotification(context);
        return await notificationManager.isNotificationEnabled();
      }
      return false;
    } catch (_err) {
      return false;
    }
  }

  private static collectUpcomingCandidates(
    schedule: ShuYoScheduleData,
    termStartDate: string,
    maxWeek: number,
    leadMinutes: number
  ): ShuYoReminderCandidate[] {
    const todayStr = ScheduleService.getTodayDateStr();
    const nowMs = Date.now();
    const out: ShuYoReminderCandidate[] = [];

    for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
      const dateStr = ScheduleService.addDaysToDateStr(todayStr, dayOffset);
      const weekNum = ScheduleService.computeWeekFromStart(termStartDate, dateStr);
      if (weekNum < 1 || weekNum > maxWeek) {
        continue;
      }
      const dateObj = ScheduleService.makeDate(dateStr);
      const jsDay = dateObj.getDay();
      const weekday = jsDay === 0 ? 7 : jsDay;

      for (let i = 0; i < schedule.sessions.length; i++) {
        const session = schedule.sessions[i];
        if (session.weekday !== weekday) {
          continue;
        }
        if (session.weeks.length > 0 && !session.weeks.includes(weekNum)) {
          continue;
        }
        const periodIdx = Math.max(1, Math.min(ShuYoConstants.classPeriods.length, session.startSection)) - 1;
        const startTimeStr = ShuYoConstants.classPeriods[periodIdx].startTime;
        const hm = startTimeStr.split(':');
        if (hm.length !== 2) {
          continue;
        }
        const hour = parseInt(hm[0], 10);
        const minute = parseInt(hm[1], 10);
        if (Number.isNaN(hour) || Number.isNaN(minute)) {
          continue;
        }
        const classStart = new Date(
          dateObj.getFullYear(),
          dateObj.getMonth(),
          dateObj.getDate(),
          hour,
          minute,
          0,
          0
        );
        const triggerMs = classStart.getTime() - leadMinutes * 60000;
        if (triggerMs <= nowMs + 5000) {
          continue;
        }
        out.push({
          triggerMs: triggerMs,
          session: session,
          timeRangeText: ShuYoConstants.getPeriodTimeText(session.startSection, session.endSection)
        });
      }
    }

    out.sort((a: ShuYoReminderCandidate, b: ShuYoReminderCandidate): number => a.triggerMs - b.triggerMs);
    if (out.length > ClassReminderService.maxReminders) {
      return out.slice(0, ClassReminderService.maxReminders);
    }
    return out;
  }

  static async syncReminders(
    context: common.UIAbilityContext | undefined,
    schedule: ShuYoScheduleData,
    termStartDate: string,
    maxWeek: number,
    requestPermissionIfNeeded: boolean
  ): Promise<string> {
    if (requestPermissionIfNeeded) {
      const granted = await ClassReminderService.ensureNotificationEnabled(context);
      if (!granted) {
        PreferencesService.setBoolean(ClassReminderService.keyEnabled, false);
        return '未授予通知权限，无法开启课前提醒';
      }
    }

    PreferencesService.setBoolean(ClassReminderService.keyEnabled, true);
    await ClassReminderService.cancelScheduledReminders();

    const leadMinutes = ClassReminderService.getLeadMinutes();
    const candidates = ClassReminderService.collectUpcomingCandidates(
      schedule,
      termStartDate,
      maxWeek,
      leadMinutes
    );

    if (candidates.length === 0) {
      return '未来 7 天暂无待提醒课程';
    }

    const publishedIds: number[] = [];
    for (let i = 0; i < candidates.length; i++) {
      const item = candidates[i];
      const triggerDate = new Date(item.triggerMs);
      const room = item.session.location.length > 0 ? item.session.location : '待定教室';
      const timeLabel = item.timeRangeText.length > 0
        ? item.timeRangeText
        : `第${item.session.startSection}-${item.session.endSection}节`;
      const req: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: triggerDate.getFullYear(),
          month: triggerDate.getMonth() + 1,
          day: triggerDate.getDate(),
          hour: triggerDate.getHours(),
          minute: triggerDate.getMinutes(),
          second: 0
        },
        title: `即将上课 · ${item.session.courseName}`,
        content: `${room} · ${timeLabel}（提前 ${leadMinutes} 分钟）`,
        expiredContent: `${item.session.courseName} 已开始上课`,
        ringDuration: 0,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION,
        wantAgent: {
          pkgName: ShuYoConstants.bundleName,
          abilityName: 'EntryAbility'
        }
      };

      try {
        const id = await reminderAgentManager.publishReminder(req);
        publishedIds.push(id);
      } catch (_err) {
        // Stop early if system quota reached or device unsupported
        if (i === 0) {
          return '已开启提醒开关（当前运行环境暂不支持系统代理提醒）';
        }
        break;
      }
    }

    ClassReminderService.saveStoredIds(publishedIds);
    return `已为未来 7 天设置 ${publishedIds.length} 条课前提醒`;
  }
}
