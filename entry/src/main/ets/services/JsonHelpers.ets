export class JsonHelpers {
  static parseObject(text: string): Record<string, Object> | undefined {
    try {
      const parsed = JSON.parse(text) as Object | null;
      if (parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, Object>;
      }
    } catch (_err) {
      return undefined;
    }
    return undefined;
  }

  static parseArray(text: string): Object[] {
    try {
      const parsed = JSON.parse(text) as Object | null;
      if (parsed !== null && Array.isArray(parsed)) {
        return parsed as Object[];
      }
    } catch (_err) {
      return [];
    }
    return [];
  }

  static asObject(val: Object | undefined | null): Record<string, Object> | undefined {
    if (val !== undefined && val !== null && typeof val === 'object' && !Array.isArray(val)) {
      return val as Record<string, Object>;
    }
    return undefined;
  }

  static asArray(val: Object | undefined | null): Object[] {
    if (val !== undefined && val !== null && Array.isArray(val)) {
      return val as Object[];
    }
    return [];
  }

  static str(obj: Record<string, Object> | undefined, key: string, fallback: string = ''): string {
    if (obj === undefined) {
      return fallback;
    }
    const val = obj[key];
    if (val === undefined || val === null) {
      return fallback;
    }
    if (typeof val === 'string') {
      return val;
    }
    if (typeof val === 'number' || typeof val === 'boolean') {
      return String(val);
    }
    return fallback;
  }

  static num(obj: Record<string, Object> | undefined, key: string, fallback: number = 0): number {
    if (obj === undefined) {
      return fallback;
    }
    const val = obj[key];
    if (typeof val === 'number') {
      return Number.isFinite(val) ? val : fallback;
    }
    if (typeof val === 'string') {
      const n = Number(val);
      return Number.isFinite(n) ? n : fallback;
    }
    return fallback;
  }

  static bool(obj: Record<string, Object> | undefined, key: string, fallback: boolean = false): boolean {
    if (obj === undefined) {
      return fallback;
    }
    const val = obj[key];
    if (typeof val === 'boolean') {
      return val;
    }
    if (typeof val === 'number') {
      return val !== 0;
    }
    if (typeof val === 'string') {
      const lower = val.toLowerCase();
      return lower === 'true' || lower === '1';
    }
    return fallback;
  }

  static strList(obj: Record<string, Object> | undefined, key: string): string[] {
    if (obj === undefined) {
      return [];
    }
    const raw = JsonHelpers.asArray(obj[key]);
    const out: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      if (typeof item === 'string') {
        out.push(item);
      } else if (typeof item === 'number') {
        out.push(String(item));
      }
    }
    return out;
  }
}
