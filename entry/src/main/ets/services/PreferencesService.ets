import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class PreferencesService {
  private static readonly storeName: string = 'shuyo_prefs';
  private static prefs: preferences.Preferences | undefined = undefined;

  static init(context: common.Context): void {
    try {
      PreferencesService.prefs = preferences.getPreferencesSync(context, {
        name: PreferencesService.storeName
      });
    } catch (_err) {
      PreferencesService.prefs = undefined;
    }
  }

  static getString(key: string, fallback: string = ''): string {
    if (PreferencesService.prefs === undefined) {
      return fallback;
    }
    try {
      const val = PreferencesService.prefs.getSync(key, fallback);
      return typeof val === 'string' ? val : fallback;
    } catch (_err) {
      return fallback;
    }
  }

  static setString(key: string, val: string): void {
    if (PreferencesService.prefs === undefined) {
      return;
    }
    try {
      PreferencesService.prefs.putSync(key, val);
      PreferencesService.prefs.flushSync();
    } catch (_err) {
      // Ignore storage write error
    }
  }

  static getBoolean(key: string, fallback: boolean = false): boolean {
    if (PreferencesService.prefs === undefined) {
      return fallback;
    }
    try {
      const val = PreferencesService.prefs.getSync(key, fallback);
      return typeof val === 'boolean' ? val : fallback;
    } catch (_err) {
      return fallback;
    }
  }

  static setBoolean(key: string, val: boolean): void {
    if (PreferencesService.prefs === undefined) {
      return;
    }
    try {
      PreferencesService.prefs.putSync(key, val);
      PreferencesService.prefs.flushSync();
    } catch (_err) {
      // Ignore storage write error
    }
  }

  static getNumber(key: string, fallback: number = 0): number {
    if (PreferencesService.prefs === undefined) {
      return fallback;
    }
    try {
      const val = PreferencesService.prefs.getSync(key, fallback);
      return typeof val === 'number' ? val : fallback;
    } catch (_err) {
      return fallback;
    }
  }

  static setNumber(key: string, val: number): void {
    if (PreferencesService.prefs === undefined) {
      return;
    }
    try {
      PreferencesService.prefs.putSync(key, val);
      PreferencesService.prefs.flushSync();
    } catch (_err) {
      // Ignore storage write error
    }
  }

  static remove(key: string): void {
    if (PreferencesService.prefs === undefined) {
      return;
    }
    try {
      PreferencesService.prefs.deleteSync(key);
      PreferencesService.prefs.flushSync();
    } catch (_err) {
      // Ignore
    }
  }

  static clearAll(): void {
    if (PreferencesService.prefs === undefined) {
      return;
    }
    try {
      PreferencesService.prefs.clearSync();
      PreferencesService.prefs.flushSync();
    } catch (_err) {
      // Ignore
    }
  }
}
