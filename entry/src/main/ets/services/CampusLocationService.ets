import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface ShuYoDeviceLocationResult {
  ok: boolean;
  longitude: number;
  latitude: number;
  accuracy: number;
  message: string;
}

/**
 * Provides native device positioning via @kit.LocationKit and runtime permission checks
 * via @kit.AbilityKit (abilityAccessCtrl).
 */
export class CampusLocationService {
  private static readonly approxPermission: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
  private static readonly precisePermission: Permissions = 'ohos.permission.LOCATION';

  static hasLocationPermission(): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId = info.appInfo.accessTokenId;
      const approxStatus = atManager.checkAccessTokenSync(tokenId, CampusLocationService.approxPermission);
      return approxStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_err) {
      return false;
    }
  }

  static async ensureLocationPermission(context: common.UIAbilityContext | undefined): Promise<boolean> {
    if (CampusLocationService.hasLocationPermission()) {
      return true;
    }
    if (context === undefined) {
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const reqList: Array<Permissions> = [
        CampusLocationService.approxPermission,
        CampusLocationService.precisePermission
      ];
      const result = await atManager.requestPermissionsFromUser(context, reqList);
      return result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_err) {
      return false;
    }
  }

  static async locateOnce(context: common.UIAbilityContext | undefined): Promise<ShuYoDeviceLocationResult> {
    try {
      const enabled = geoLocationManager.isLocationEnabled();
      if (!enabled) {
        return {
          ok: false,
          longitude: 0,
          latitude: 0,
          accuracy: 0,
          message: '请先在系统设置中开启位置服务'
        };
      }
    } catch (_err) {
      return {
        ok: false,
        longitude: 0,
        latitude: 0,
        accuracy: 0,
        message: '当前设备暂不支持位置服务'
      };
    }

    const granted = await CampusLocationService.ensureLocationPermission(context);
    if (!granted) {
      return {
        ok: false,
        longitude: 0,
        latitude: 0,
        accuracy: 0,
        message: '未获得定位权限，仍可浏览和搜索地图'
      };
    }

    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 10000
    };
    try {
      const loc = await geoLocationManager.getCurrentLocation(request);
      return {
        ok: true,
        longitude: loc.longitude,
        latitude: loc.latitude,
        accuracy: loc.accuracy,
        message: ''
      };
    } catch (err) {
      try {
        const cached = geoLocationManager.getLastLocation();
        return {
          ok: true,
          longitude: cached.longitude,
          latitude: cached.latitude,
          accuracy: cached.accuracy,
          message: '已使用最近一次缓存定位'
        };
      } catch (_cacheErr) {
        const bErr = err as BusinessError;
        if (bErr.code === 3301100) {
          return { ok: false, longitude: 0, latitude: 0, accuracy: 0, message: '系统位置开关已关闭' };
        }
        return {
          ok: false,
          longitude: 0,
          latitude: 0,
          accuracy: 0,
          message: '暂未获取到当前位置，请移步室外开阔处重试'
        };
      }
    }
  }

  static startWatching(callback: (loc: geoLocationManager.Location) => void): boolean {
    if (!CampusLocationService.hasLocationPermission()) {
      return false;
    }
    try {
      if (!geoLocationManager.isLocationEnabled()) {
        return false;
      }
      const req: geoLocationManager.ContinuousLocationRequest = {
        interval: 3,
        locationScenario: geoLocationManager.UserActivityScenario.DAILY_LIFE_SERVICE
      };
      geoLocationManager.on('locationChange', req, callback);
      return true;
    } catch (_err) {
      return false;
    }
  }

  static stopWatching(callback?: (loc: geoLocationManager.Location) => void): void {
    try {
      if (callback !== undefined) {
        geoLocationManager.off('locationChange', callback);
      } else {
        geoLocationManager.off('locationChange');
      }
    } catch (_err) {
      // Ignore unregister errors if watcher was not active
    }
  }
}
