import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesService } from './PreferencesService';

/**
 * Wraps HarmonyOS @kit.AssetStoreKit for hardware-backed credential & session storage.
 * Automatically splits values over 800 bytes into chunks (Asset SECRET max is 1024 bytes),
 * migrates legacy plaintext entries from PreferencesService on first read, and falls back
 * cleanly to PreferencesService when running in environments without ASSET service.
 */
export class SecureStorageService {
  private static readonly chunkSize: number = 800;
  private static readonly aliasPrefix: string = 'shuyo_sec_';
  private static readonly notFoundCode: number = 24000002;
  private static assetAvailable: boolean = true;

  static isHardwareBacked(): boolean {
    return SecureStorageService.assetAvailable;
  }

  private static aliasOf(key: string): string {
    return `${SecureStorageService.aliasPrefix}${key}`;
  }

  private static chunksMetaAlias(key: string): string {
    return `${SecureStorageService.aliasPrefix}${key}__chunks`;
  }

  private static chunkAlias(key: string, idx: number): string {
    return `${SecureStorageService.aliasPrefix}${key}__c_${idx}`;
  }

  private static encodeUtf8(val: string): Uint8Array {
    return new util.TextEncoder().encodeInto(val);
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  }

  private static queryAliasBytes(alias: string): Uint8Array | undefined {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorageService.encodeUtf8(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results = asset.querySync(query);
      if (results.length === 0) {
        return undefined;
      }
      const secretVal = results[0].get(asset.Tag.SECRET);
      if (secretVal instanceof Uint8Array) {
        return secretVal;
      }
      return undefined;
    } catch (err) {
      const bErr = err as BusinessError;
      if (bErr.code === SecureStorageService.notFoundCode) {
        return undefined;
      }
      throw new Error(`ASSET_UNAVAILABLE:${bErr.code}`);
    }
  }

  private static putAliasBytes(alias: string, data: Uint8Array): void {
    const attr: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attr.set(asset.Tag.ALIAS, SecureStorageService.encodeUtf8(alias));
    attr.set(asset.Tag.SECRET, data);
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attr.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.addSync(attr);
  }

  private static removeAliasSilent(alias: string): void {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorageService.encodeUtf8(alias));
    try {
      asset.removeSync(query);
    } catch (_err) {
      // Ignore missing alias cleanup failure
    }
  }

  private static readOldChunkCount(key: string): number {
    try {
      const bytes = SecureStorageService.queryAliasBytes(SecureStorageService.chunksMetaAlias(key));
      if (bytes === undefined) {
        return 0;
      }
      const parsed = parseInt(SecureStorageService.decodeUtf8(bytes).trim(), 10);
      return Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
    } catch (_err) {
      return 0;
    }
  }

  static getString(key: string, fallback: string = ''): string {
    try {
      const metaBytes = SecureStorageService.queryAliasBytes(SecureStorageService.chunksMetaAlias(key));
      if (metaBytes !== undefined) {
        const count = parseInt(SecureStorageService.decodeUtf8(metaBytes).trim(), 10);
        if (!Number.isNaN(count) && count > 0) {
          let b64 = '';
          let complete = true;
          for (let i = 0; i < count; i++) {
            const partBytes = SecureStorageService.queryAliasBytes(SecureStorageService.chunkAlias(key, i));
            if (partBytes === undefined) {
              complete = false;
              break;
            }
            b64 += SecureStorageService.decodeUtf8(partBytes);
          }
          if (complete && b64.length > 0) {
            const rawBytes = new util.Base64Helper().decodeSync(b64);
            SecureStorageService.assetAvailable = true;
            return SecureStorageService.decodeUtf8(rawBytes);
          }
        }
      }

      const singleBytes = SecureStorageService.queryAliasBytes(SecureStorageService.aliasOf(key));
      if (singleBytes !== undefined) {
        SecureStorageService.assetAvailable = true;
        return SecureStorageService.decodeUtf8(singleBytes);
      }

      SecureStorageService.assetAvailable = true;
      const legacy = PreferencesService.getString(key, '');
      if (legacy.length > 0) {
        SecureStorageService.setString(key, legacy);
        return legacy;
      }
      return fallback;
    } catch (_err) {
      SecureStorageService.assetAvailable = false;
      return PreferencesService.getString(key, fallback);
    }
  }

  static setString(key: string, val: string): void {
    if (val.length === 0) {
      SecureStorageService.remove(key);
      return;
    }
    try {
      const oldCount = SecureStorageService.readOldChunkCount(key);
      const utf8 = SecureStorageService.encodeUtf8(val);
      if (utf8.length <= SecureStorageService.chunkSize) {
        SecureStorageService.putAliasBytes(SecureStorageService.aliasOf(key), utf8);
        SecureStorageService.removeAliasSilent(SecureStorageService.chunksMetaAlias(key));
        for (let i = 0; i < oldCount; i++) {
          SecureStorageService.removeAliasSilent(SecureStorageService.chunkAlias(key, i));
        }
      } else {
        const b64 = new util.Base64Helper().encodeToStringSync(utf8);
        const parts: string[] = [];
        for (let offset = 0; offset < b64.length; offset += SecureStorageService.chunkSize) {
          parts.push(b64.substring(offset, offset + SecureStorageService.chunkSize));
        }
        for (let i = 0; i < parts.length; i++) {
          SecureStorageService.putAliasBytes(
            SecureStorageService.chunkAlias(key, i),
            SecureStorageService.encodeUtf8(parts[i])
          );
        }
        SecureStorageService.putAliasBytes(
          SecureStorageService.chunksMetaAlias(key),
          SecureStorageService.encodeUtf8(`${parts.length}`)
        );
        SecureStorageService.removeAliasSilent(SecureStorageService.aliasOf(key));
        for (let i = parts.length; i < oldCount; i++) {
          SecureStorageService.removeAliasSilent(SecureStorageService.chunkAlias(key, i));
        }
      }
      SecureStorageService.assetAvailable = true;
      PreferencesService.remove(key);
    } catch (_err) {
      SecureStorageService.assetAvailable = false;
      PreferencesService.setString(key, val);
    }
  }

  static remove(key: string): void {
    try {
      const oldCount = SecureStorageService.readOldChunkCount(key);
      SecureStorageService.removeAliasSilent(SecureStorageService.aliasOf(key));
      SecureStorageService.removeAliasSilent(SecureStorageService.chunksMetaAlias(key));
      for (let i = 0; i < oldCount; i++) {
        SecureStorageService.removeAliasSilent(SecureStorageService.chunkAlias(key, i));
      }
    } catch (_err) {
      // Ignore ASSET removal errors on unsupported runtimes
    }
    PreferencesService.remove(key);
  }
}
