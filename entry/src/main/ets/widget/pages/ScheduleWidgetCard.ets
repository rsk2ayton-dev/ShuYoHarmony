let scheduleWidgetStorage = new LocalStorage();

@Entry(scheduleWidgetStorage)
@Component
struct ScheduleWidgetCard {
  @LocalStorageProp('headerTitle') headerTitle: string = 'SHU友 今日课表';
  @LocalStorageProp('dateLabel') dateLabel: string = '今日课程';
  @LocalStorageProp('summaryText') summaryText: string = '打开 SHU友 查看课表';
  @LocalStorageProp('moreCountText') moreCountText: string = '';
  @LocalStorageProp('updatedAt') updatedAt: string = '--:--';
  @LocalStorageProp('cardAccentColor') cardAccentColor: string = '#2563EB';
  @LocalStorageProp('cardBgColor') cardBgColor: string = '#FFFFFF';
  @LocalStorageProp('cardSubBgColor') cardSubBgColor: string = '#F3F6FA';
  @LocalStorageProp('cardTextColor') cardTextColor: string = '#111827';
  @LocalStorageProp('cardSubTextColor') cardSubTextColor: string = '#6B7280';

  @LocalStorageProp('hasCourse1') hasCourse1: boolean = false;
  @LocalStorageProp('course1Name') course1Name: string = '';
  @LocalStorageProp('course1Meta') course1Meta: string = '';
  @LocalStorageProp('course1Color') course1Color: string = '#2563EB';

  @LocalStorageProp('hasCourse2') hasCourse2: boolean = false;
  @LocalStorageProp('course2Name') course2Name: string = '';
  @LocalStorageProp('course2Meta') course2Meta: string = '';
  @LocalStorageProp('course2Color') course2Color: string = '#059669';

  @LocalStorageProp('hasCourse3') hasCourse3: boolean = false;
  @LocalStorageProp('course3Name') course3Name: string = '';
  @LocalStorageProp('course3Meta') course3Meta: string = '';
  @LocalStorageProp('course3Color') course3Color: string = '#D97706';

  @Builder
  private courseItem(titleText: string, metaText: string, barColor: string) {
    Row({ space: 8 }) {
      Column()
        .width(3)
        .height(24)
        .borderRadius(2)
        .backgroundColor(barColor)

      Column({ space: 1 }) {
        Text(titleText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cardTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(metaText)
          .fontSize(10)
          .fontColor(this.cardSubTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(this.cardSubBgColor)
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Column({ space: 1 }) {
          Text(this.headerTitle)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.cardTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.dateLabel)
            .fontSize(10)
            .fontColor(this.cardSubTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('刷新')
          .height(22)
          .fontSize(10)
          .fontColor(this.cardAccentColor)
          .backgroundColor(this.cardSubBgColor)
          .borderRadius(11)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            postCardAction(this, {
              action: 'message',
              params: { action: 'refresh' }
            });
          })
      }
      .width('100%')

      if (!this.hasCourse1) {
        Column() {
          Text(this.summaryText)
            .fontSize(12)
            .fontColor(this.cardSubTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 4 }) {
          this.courseItem(this.course1Name, this.course1Meta, this.course1Color)
          if (this.hasCourse2) {
            this.courseItem(this.course2Name, this.course2Meta, this.course2Color)
          }
          if (this.hasCourse3) {
            this.courseItem(this.course3Name, this.course3Meta, this.course3Color)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }

      Row() {
        Text(this.moreCountText)
          .fontSize(10)
          .fontColor(this.cardAccentColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`更新 ${this.updatedAt}`)
          .fontSize(9)
          .fontColor(this.cardSubTextColor)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.cardBgColor)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetTab: 'schedule' }
      });
    })
  }
}
