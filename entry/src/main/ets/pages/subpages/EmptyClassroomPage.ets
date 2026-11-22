import { ShuYoConstants } from '../../core/ShuYoConstants';
import {
  ShuYoClassroomBuilding,
  ShuYoClassroomRoom,
  ShuYoClassroomSection
} from '../../models/ShuYoModels';
import { ClassroomService } from '../../services/ClassroomService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoEmptyState, ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function EmptyClassroomPageBuilder(): void {
  EmptyClassroomPage()
}

@ComponentV2
export struct EmptyClassroomPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local buildings: ShuYoClassroomBuilding[] = [];
  @Local sections: ShuYoClassroomSection[] = [];
  @Local rooms: ShuYoClassroomRoom[] = [];
  @Local selectedCampus: string = '宝山校区';
  @Local selectedBuildingId: number = 930;
  @Local selectedSections: number[] = [1, 2];
  @Local useWebVpn: boolean = false;
  @Local onlyShowFree: boolean = true;
  @Local isLoading: boolean = false;
  @Local errorMsg: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly campuses: string[] = ['宝山校区', '嘉定校区', '延长校区'];

  aboutToAppear(): void {
    this.useWebVpn = this.store.useWebVpn;
    this.loadOptionsAndRooms();
  }

  private async loadOptionsAndRooms(): Promise<void> {
    this.isLoading = true;
    this.errorMsg = '';
    try {
      if (this.store.isDemoMode) {
        const opts = ClassroomService.loadDemoOptions();
        this.buildings = opts.buildings;
        this.sections = opts.sections;
        this.ensureBuildingSelection();
        this.rooms = ClassroomService.loadDemoRooms(this.selectedBuildingId);
      } else {
        const opts = await ClassroomService.fetchLiveOptions(this.useWebVpn);
        this.buildings = opts.buildings;
        this.sections = opts.sections;
        this.ensureBuildingSelection();
        await this.loadRoomsOnly();
      }
    } catch (err) {
      const e = err as Error;
      this.errorMsg = e.message;
      const opts = ClassroomService.loadDemoOptions();
      this.buildings = opts.buildings;
      this.sections = opts.sections;
      this.ensureBuildingSelection();
      this.rooms = ClassroomService.loadDemoRooms(this.selectedBuildingId);
    } finally {
      this.isLoading = false;
    }
  }

  private async loadRoomsOnly(): Promise<void> {
    if (this.store.isDemoMode) {
      this.rooms = ClassroomService.loadDemoRooms(this.selectedBuildingId);
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    try {
      const now = new Date();
      const y = now.getFullYear();
      const m = now.getMonth() + 1;
      const d = now.getDate();
      const dateStr = `${y}-${m < 10 ? '0' + m : m}-${d < 10 ? '0' + d : d}`;
      this.rooms = await ClassroomService.fetchLiveRooms(this.selectedBuildingId, dateStr, this.useWebVpn);
    } catch (err) {
      const e = err as Error;
      this.errorMsg = e.message;
      this.rooms = ClassroomService.loadDemoRooms(this.selectedBuildingId);
    } finally {
      this.isLoading = false;
    }
  }

  private ensureBuildingSelection(): void {
    const filtered = this.getCampusBuildings();
    let found = false;
    for (let i = 0; i < filtered.length; i++) {
      if (filtered[i].id === this.selectedBuildingId) {
        found = true;
        break;
      }
    }
    if (!found && filtered.length > 0) {
      this.selectedBuildingId = filtered[0].id;
    }
  }

  private getCampusBuildings(): ShuYoClassroomBuilding[] {
    const list: ShuYoClassroomBuilding[] = [];
    for (let i = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].campusName === this.selectedCampus) {
        list.push(this.buildings[i]);
      }
    }
    return list;
  }

  private getDisplayedRooms(): ShuYoClassroomRoom[] {
    if (!this.onlyShowFree) {
      return this.rooms;
    }
    const freeList: ShuYoClassroomRoom[] = [];
    for (let i = 0; i < this.rooms.length; i++) {
      if (ClassroomService.isRoomFreeForSections(this.rooms[i], this.selectedSections)) {
        freeList.push(this.rooms[i]);
      }
    }
    return freeList;
  }

  private toggleSection(secIdx: number): void {
    const next: number[] = [];
    let removed = false;
    for (let i = 0; i < this.selectedSections.length; i++) {
      if (this.selectedSections[i] === secIdx) {
        removed = true;
      } else {
        next.push(this.selectedSections[i]);
      }
    }
    if (!removed) {
      next.push(secIdx);
    }
    next.sort((a: number, b: number): number => a - b);
    this.selectedSections = next;
  }

  private isSectionSelected(secIdx: number): boolean {
    return this.selectedSections.includes(secIdx);
  }

  private getChipBg(active: boolean): string {
    return active ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getChipText(active: boolean): string {
    return active ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private isRoomFree(room: ShuYoClassroomRoom): boolean {
    return ClassroomService.isRoomFreeForSections(room, this.selectedSections);
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '空教室查询',
          subtitleText: this.store.isDemoMode ? '2026-09-01 演示数据' : (ShuYoConstants.isClassroomExternalAccessOpen() ? '实时可用 (07:00-23:00)' : '外网夜间维护时段'),
          showBack: true,
          rightLabel: '',
          rightSymbolName: 'refresh',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.loadRoomsOnly();
          }
        })

        // Campus tabs & WebVPN toggle
        Row({ space: 8 }) {
          ForEach(this.campuses, (campus: string, idx: number) => {
            Button(campus)
              .height(32)
              .fontSize(12)
              .fontColor(this.getChipText(this.selectedCampus === campus))
              .backgroundColor(this.getChipBg(this.selectedCampus === campus))
              .borderRadius(16)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.selectedCampus = campus;
                this.ensureBuildingSelection();
                this.loadRoomsOnly();
              })
          }, (campus: string, idx: number): string => `cmp-${campus}`)

          Blank()

          Row({ space: 4 }) {
            Text('WebVPN')
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
            Toggle({ type: ToggleType.Switch, isOn: this.useWebVpn })
              .selectedColor(this.store.colors.accent)
              .onChange((isOn: boolean) => {
                this.useWebVpn = isOn;
                this.loadOptionsAndRooms();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // Building chips
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.getCampusBuildings(), (b: ShuYoClassroomBuilding, idx: number) => {
              Button(b.name)
                .height(32)
                .fontSize(12)
                .fontColor(this.getChipText(this.selectedBuildingId === b.id))
                .backgroundColor(this.getChipBg(this.selectedBuildingId === b.id))
                .borderRadius(16)
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.selectedBuildingId = b.id;
                  this.loadRoomsOnly();
                })
            }, (b: ShuYoClassroomBuilding, idx: number): string => `bld-${b.id}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(36)

        // Section selector
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.sections, (sec: ShuYoClassroomSection, idx: number) => {
              Button(`第${sec.index}节`)
                .height(30)
                .fontSize(12)
                .fontColor(this.getChipText(this.isSectionSelected(sec.index)))
                .backgroundColor(this.getChipBg(this.isSectionSelected(sec.index)))
                .borderRadius(12)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.toggleSection(sec.index);
                })
            }, (sec: ShuYoClassroomSection, idx: number): string => `sec-flt-${sec.index}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(34)

        // Filter summary row
        Row() {
          Text(`匹配教室 ${this.getDisplayedRooms().length} 间`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textSecondary)
          Blank()
          Row({ space: 6 }) {
            Text('仅看空闲')
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
            Toggle({ type: ToggleType.Switch, isOn: this.onlyShowFree })
              .selectedColor(this.store.colors.accent)
              .onChange((isOn: boolean) => {
                this.onlyShowFree = isOn;
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(12)
            .fontColor(this.store.colors.warning)
            .padding({ left: 16, right: 16 })
            .width('100%')
        }

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(36).height(36).color(this.store.colors.accent)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.getDisplayedRooms().length === 0) {
          ShuYoEmptyState({
            emptyTitle: '所选节次暂无空闲教室',
            emptyHint: '尝试切换其他教学楼或减少节次筛选条件',
            actionText: '显示全部教室',
            onActionTap: () => {
              this.onlyShowFree = false;
            }
          })
        } else {
          List({ space: 8 }) {
            ForEach(this.getDisplayedRooms(), (room: ShuYoClassroomRoom, idx: number) => {
              ListItem() {
                Column({ space: 6 }) {
                  Row() {
                    Text(room.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Text(` · ${room.floorName}`)
                      .fontSize(12)
                      .fontColor(this.store.colors.textTertiary)
                    Blank()
                    Text(this.isRoomFree(room) ? '空闲' : '有课')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isRoomFree(room) ? this.store.colors.success : this.store.colors.warning)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(8)
                      .backgroundColor(this.store.colors.surfaceAlt)
                  }
                  .width('100%')

                  if (room.courseSlots.length > 0) {
                    Text(`当日排课：${room.courseSlots.map((c) => `${c.startSection}-${c.endSection}节 ${c.courseName}`).join('；')}`)
                      .fontSize(12)
                      .fontColor(this.store.colors.textTertiary)
                  } else {
                    Text('全天无排课安排')
                      .fontSize(12)
                      .fontColor(this.store.colors.textMuted)
                  }
                }
                .width('100%')
                .padding(14)
                .borderRadius(12)
                .backgroundColor(this.store.colors.surface)
                .border({ width: 1, color: this.store.colors.border })
                .alignItems(HorizontalAlign.Start)
              }
            }, (room: ShuYoClassroomRoom, idx: number): string => `rm-${room.id}-${idx}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
