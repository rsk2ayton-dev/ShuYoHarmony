import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import {
  ShuYoCampusInfo,
  ShuYoCampusMapData,
  ShuYoCampusMapPlace,
  ShuYoMapFact,
  ShuYoMapLocationPoint,
  ShuYoMapPoint,
  ShuYoMapView
} from '../../models/ShuYoModels';
import { CampusLocationService } from '../../services/CampusLocationService';
import { CampusMapService } from '../../services/CampusMapService';
import { JsonHelpers } from '../../services/JsonHelpers';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

interface ShuYoMapCanvasPlacePayload {
  id: string;
  featureIds: string[];
  point?: ShuYoMapPoint;
}

interface ShuYoMapCanvasLoadPayload {
  campusId: string;
  svg: string;
  viewBox: number[];
  initialView: ShuYoMapView;
  backgroundColor: string;
  debug: boolean;
  places: ShuYoMapCanvasPlacePayload[];
  bottomInset: number;
  cachedGestures: boolean;
  active: boolean;
}

interface ShuYoMapCanvasUpdatePayload {
  selectedId: string;
  accent: string;
  bottomInset: number;
  focus: boolean;
  focusPoint?: ShuYoMapPoint;
  location?: ShuYoMapLocationPoint;
  active: boolean;
}

class ShuYoMapJsBridge {
  private onMessageCb: (msg: string) => void;

  constructor(cb: (msg: string) => void) {
    this.onMessageCb = cb;
  }

  postMessage(msg: string): void {
    this.onMessageCb(msg);
  }
}

@Builder
export function CampusMapPageBuilder(): void {
  CampusMapPage()
}

@ComponentV2
export struct CampusMapPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local mapData: ShuYoCampusMapData = { version: '', campuses: [], places: [] };
  @Local selectedCampusId: string = 'baoshan';
  @Local selectedPlace: ShuYoCampusMapPlace | undefined = undefined;
  @Local showPlaceSheet: boolean = false;
  @Local showPlaceList: boolean = false;
  @Local searchQuery: string = '';
  @Local webReady: boolean = false;
  @Local isLocating: boolean = false;
  @Local hasDeviceLocation: boolean = false;
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private webController: webview.WebviewController = new webview.WebviewController();
  private loadedCampusInWeb: string = '';
  private lastWgsLng: number = 0;
  private lastWgsLat: number = 0;
  private lastAccuracyMeters: number = 0;
  private watchCallback: ((loc: geoLocationManager.Location) => void) | undefined = undefined;
  private mapBridge: ShuYoMapJsBridge = new ShuYoMapJsBridge((msg: string) => {
    this.handleBridgeMessage(msg);
  });

  aboutToAppear(): void {
    this.mapData = CampusMapService.loadMapData();
    if (this.mapData.campuses.length > 0) {
      this.selectedCampusId = this.mapData.campuses[0].id;
    }
  }

  aboutToDisappear(): void {
    if (this.watchCallback !== undefined) {
      CampusLocationService.stopWatching(this.watchCallback);
      this.watchCallback = undefined;
    }
  }

  private handleBridgeMessage(msg: string): void {
    const obj = JsonHelpers.parseObject(msg);
    if (obj === undefined) {
      return;
    }
    const msgType = JsonHelpers.str(obj, 'type');
    if (msgType === 'ready') {
      this.webReady = true;
      this.syncCampusToWeb(false);
    } else if (msgType === 'place') {
      const pid = JsonHelpers.str(obj, 'id');
      this.selectPlaceById(pid, false);
    } else if (msgType === 'background') {
      this.selectedPlace = undefined;
      this.showPlaceSheet = false;
    }
  }

  private getCurrentCampus(): ShuYoCampusInfo | undefined {
    for (let i = 0; i < this.mapData.campuses.length; i++) {
      if (this.mapData.campuses[i].id === this.selectedCampusId) {
        return this.mapData.campuses[i];
      }
    }
    return this.mapData.campuses.length > 0 ? this.mapData.campuses[0] : undefined;
  }

  private getFilteredPlaces(): ShuYoCampusMapPlace[] {
    return CampusMapService.searchPlaces(this.mapData.places, this.selectedCampusId, this.searchQuery);
  }

  private selectPlaceById(placeId: string, focusOnMap: boolean): void {
    for (let i = 0; i < this.mapData.places.length; i++) {
      if (this.mapData.places[i].id === placeId) {
        this.selectedPlace = this.mapData.places[i];
        this.showPlaceSheet = true;
        this.showPlaceList = false;
        this.syncUpdateToWeb(focusOnMap);
        return;
      }
    }
  }

  private syncCampusToWeb(focusPlace: boolean): void {
    if (!this.webReady) {
      return;
    }
    const campus = this.getCurrentCampus();
    if (campus === undefined) {
      return;
    }
    if (this.loadedCampusInWeb !== campus.id) {
      const svgText = CampusMapService.readCampusSvg(campus.assetPath);
      const campusPlaces: ShuYoMapCanvasPlacePayload[] = [];
      for (let i = 0; i < this.mapData.places.length; i++) {
        const p = this.mapData.places[i];
        if (p.campusId !== campus.id) {
          continue;
        }
        if (p.hasPoint) {
          campusPlaces.push({
            id: p.id,
            featureIds: p.featureIds,
            point: { x: p.pointX, y: p.pointY }
          });
        } else {
          campusPlaces.push({
            id: p.id,
            featureIds: p.featureIds
          });
        }
      }
      const loadPayload: ShuYoMapCanvasLoadPayload = {
        campusId: campus.id,
        svg: svgText,
        viewBox: campus.viewBox,
        initialView: campus.initialView,
        backgroundColor: campus.backgroundColor,
        debug: false,
        places: campusPlaces,
        bottomInset: 0,
        cachedGestures: true,
        active: true
      };
      try {
        this.webController.runJavaScript(`window.campusMap.load(${JSON.stringify(loadPayload)});`);
      } catch (_err) {
        // Ignore if webview not yet attached
      }
      this.loadedCampusInWeb = campus.id;
    }
    this.syncUpdateToWeb(focusPlace);
  }

  private computeLocationOverlayForCurrentCampus(): ShuYoMapLocationPoint | undefined {
    if (!this.hasDeviceLocation) {
      return undefined;
    }
    const campus = this.getCurrentCampus();
    if (campus === undefined) {
      return undefined;
    }
    return CampusMapService.projectWgs84ToCampus(
      campus,
      this.lastWgsLng,
      this.lastWgsLat,
      this.lastAccuracyMeters
    );
  }

  private ensureWatchingLocation(): void {
    if (this.watchCallback !== undefined) {
      return;
    }
    const cb = (loc: geoLocationManager.Location): void => {
      this.hasDeviceLocation = true;
      this.lastWgsLng = loc.longitude;
      this.lastWgsLat = loc.latitude;
      this.lastAccuracyMeters = loc.accuracy;
      this.syncUpdateToWeb(false);
    };
    if (CampusLocationService.startWatching(cb)) {
      this.watchCallback = cb;
    }
  }

  private async locateUserOnCampus(): Promise<void> {
    if (this.isLocating) {
      return;
    }
    this.isLocating = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const res = await CampusLocationService.locateOnce(ctx);
      if (!res.ok) {
        this.getUIContext().getPromptAction().showToast({ message: res.message });
        return;
      }
      this.hasDeviceLocation = true;
      this.lastWgsLng = res.longitude;
      this.lastWgsLat = res.latitude;
      this.lastAccuracyMeters = res.accuracy;
      this.ensureWatchingLocation();

      const matchedCampus = CampusMapService.findCampusAtWgs84(
        this.mapData.campuses,
        res.longitude,
        res.latitude
      );
      if (matchedCampus === undefined) {
        this.syncUpdateToWeb(false);
        this.getUIContext().getPromptAction().showToast({
          message: '当前位置不在宝山/延长/嘉定校区范围内'
        });
        return;
      }

      if (matchedCampus.id !== this.selectedCampusId) {
        this.selectedCampusId = matchedCampus.id;
        this.selectedPlace = undefined;
        this.showPlaceSheet = false;
        this.syncCampusToWeb(false);
      }
      const projected = CampusMapService.projectWgs84ToCampus(
        matchedCampus,
        res.longitude,
        res.latitude,
        res.accuracy
      );
      if (projected !== undefined) {
        this.syncUpdateToWeb(true, { x: projected.x, y: projected.y });
      }
      const toastMsg = res.message.length > 0 ? res.message : `已定位到${matchedCampus.name}`;
      this.getUIContext().getPromptAction().showToast({ message: toastMsg });
    } finally {
      this.isLocating = false;
    }
  }

  private syncUpdateToWeb(focusPlace: boolean, focusPoint?: ShuYoMapPoint): void {
    if (!this.webReady) {
      return;
    }
    const locOverlay = this.computeLocationOverlayForCurrentCampus();
    const updatePayload: ShuYoMapCanvasUpdatePayload = {
      selectedId: this.selectedPlace !== undefined ? this.selectedPlace.id : '',
      accent: this.store.colors.accent,
      bottomInset: 0,
      focus: focusPlace,
      focusPoint: focusPoint,
      location: locOverlay,
      active: true
    };
    try {
      this.webController.runJavaScript(`window.campusMap.update(${JSON.stringify(updatePayload)});`);
    } catch (_err) {
      // Ignore if webview not yet attached
    }
  }

  private getCampusBtnBg(id: string): string {
    return this.selectedCampusId === id ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getCampusBtnText(id: string): string {
    return this.selectedCampusId === id ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  @Builder
  private placeSheetBuilder() {
    Column({ space: 10 }) {
      if (this.selectedPlace !== undefined) {
        Row() {
          Text(this.selectedPlace.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)
          Blank()
          if (this.selectedPlace.kind.length > 0) {
            Text(this.selectedPlace.kind)
              .fontSize(12)
              .fontColor(this.store.colors.accent)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(8)
              .backgroundColor(this.store.colors.accentSoft)
          }
        }
        .width('100%')

        if (this.selectedPlace.address.length > 0) {
          Text(this.selectedPlace.address)
            .fontSize(13)
            .fontColor(this.store.colors.textTertiary)
        }
        if (this.selectedPlace.description.length > 0) {
          Text(this.selectedPlace.description)
            .fontSize(14)
            .fontColor(this.store.colors.textSecondary)
        }
        ForEach(this.selectedPlace.facts, (fact: ShuYoMapFact, idx: number) => {
          Row({ space: 8 }) {
            Text(fact.factLabel)
              .width(78)
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
            Text(fact.factValue)
              .layoutWeight(1)
              .fontSize(13)
              .fontColor(this.store.colors.textPrimary)
          }
          .width('100%')
        }, (fact: ShuYoMapFact, idx: number): string => `fact-${idx}`)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.store.colors.surface)
  }

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        ShuYoTopBar({
          headerTitle: '校园地图',
          subtitleText: `离线矢量地图 ${this.mapData.version}`,
          showBack: true,
          rightLabel: this.showPlaceList ? '看地图' : '地点列表',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.showPlaceList = !this.showPlaceList;
          }
        })

        // Campus tabs
        Row({ space: 8 }) {
          ForEach(this.mapData.campuses, (campus: ShuYoCampusInfo, idx: number) => {
            Button(campus.name)
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .fontColor(this.getCampusBtnText(campus.id))
              .backgroundColor(this.getCampusBtnBg(campus.id))
              .borderRadius(12)
              .onClick(() => {
                this.selectedCampusId = campus.id;
                this.selectedPlace = undefined;
                this.showPlaceSheet = false;
                this.syncCampusToWeb(false);
              })
          }, (campus: ShuYoCampusInfo, idx: number): string => `map-cmp-${campus.id}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // Search box
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([this.store.colors.textMuted])
          TextInput({ placeholder: '搜索教学楼、食堂、图书馆、校门...', text: this.searchQuery })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor(this.store.colors.textPrimary)
            .fontSize(13)
            .onChange((val: string) => {
              this.searchQuery = val;
              if (val.trim().length > 0) {
                this.showPlaceList = true;
              }
            })
          if (this.searchQuery.length > 0) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(15)
              .fontColor([this.store.colors.textMuted])
              .onClick(() => {
                this.searchQuery = '';
                this.showPlaceList = false;
              })
          }
        }
        .height(42)
        .padding({ left: 12, right: 12 })
        .margin({ left: 16, right: 16 })
        .borderRadius(12)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })

        Stack({ alignContent: Alignment.BottomEnd }) {
          Web({ src: $rawfile('campus_map/canvas.html'), controller: this.webController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .javaScriptProxy({
              object: this.mapBridge,
              name: 'ShuyoMap',
              methodList: ['postMessage'],
              controller: this.webController
            })
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
              const reqUrl = event.data.getRequestUrl();
              if (reqUrl === 'about:blank' || reqUrl.includes('campus_map/canvas.html')) {
                return false;
              }
              return true;
            })
            .onPageEnd(() => {
              this.syncCampusToWeb(false);
            })
            .width('100%')
            .height('100%')

          if (!this.showPlaceList) {
            Button() {
              Row({ space: 6 }) {
                if (this.isLocating) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(this.store.colors.onAccent)
                } else {
                  SymbolGlyph($r('sys.symbol.map'))
                    .fontSize(16)
                    .fontColor([this.hasDeviceLocation ? this.store.colors.onAccent : this.store.colors.accent])
                }
                Text(this.isLocating ? '定位中' : '定位')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(
                    this.isLocating || this.hasDeviceLocation
                      ? this.store.colors.onAccent
                      : this.store.colors.textPrimary
                  )
              }
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            }
            .height(38)
            .borderRadius(19)
            .backgroundColor(
              this.isLocating || this.hasDeviceLocation
                ? this.store.colors.accent
                : this.store.colors.surface
            )
            .border({
              width: 1,
              color: this.hasDeviceLocation ? this.store.colors.accent : this.store.colors.borderStrong
            })
            .shadow({ radius: 10, color: '#26000000', offsetX: 0, offsetY: 3 })
            .margin({ right: 16, bottom: 22 })
            .onClick(() => {
              this.locateUserOnCampus();
            })
          }

          if (this.showPlaceList) {
            List({ space: 8 }) {
              ForEach(this.getFilteredPlaces(), (place: ShuYoCampusMapPlace, idx: number) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text(place.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.store.colors.textPrimary)
                      Text(`${place.kind} · ${place.address}`)
                        .fontSize(12)
                        .fontColor(this.store.colors.textTertiary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text('定位')
                      .fontSize(12)
                      .fontColor(this.store.colors.accent)
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                  .onClick(() => {
                    this.selectPlaceById(place.id, true);
                  })
                }
              }, (place: ShuYoCampusMapPlace, idx: number): string => `${place.id}-${idx}`)
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            .backgroundColor(this.store.colors.background)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
      .bindSheet($$this.showPlaceSheet, this.placeSheetBuilder(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: true
      })
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
