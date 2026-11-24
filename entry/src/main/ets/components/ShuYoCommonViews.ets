import { ShuYoGlass, ShuYoMotion } from '../core/ShuYoMotionGlass';
import { ShuYoAppStore } from '../store/ShuYoAppStore';

@ComponentV2
export struct ShuYoTopBar {
  @Param headerTitle: string = '';
  @Param subtitleText: string = '';
  @Param showBack: boolean = true;
  @Param rightLabel: string = '';
  @Param rightSymbolName: string = '';
  @Event onBackTap: () => void = () => {};
  @Event onRightTap: () => void = () => {};
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  build() {
    Row({ space: 8 }) {
      if (this.showBack) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.store.colors.textPrimary])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ShuYoGlass.interactiveButtonMaterial(this.store.colors.isDark))
        .clickEffect(ShuYoMotion.snappyClick)
        .onClick(() => {
          this.onBackTap();
        })
      }

      Column({ space: 2 }) {
        Text(this.headerTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitleText.length > 0) {
          Text(this.subtitleText)
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.rightLabel.length > 0) {
        Button(this.rightLabel)
          .height(32)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.colors.accent)
          .backgroundColor(this.store.colors.accentSoft)
          .borderRadius(16)
          .padding({ left: 12, right: 12 })
          .clickEffect(ShuYoMotion.snappyClick)
          .onClick(() => {
            this.onRightTap();
          })
      } else if (this.rightSymbolName === 'refresh') {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor([this.store.colors.textPrimary])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ShuYoGlass.interactiveButtonMaterial(this.store.colors.isDark))
        .clickEffect(ShuYoMotion.snappyClick)
        .onClick(() => {
          this.onRightTap();
        })
      } else if (this.rightSymbolName === 'add') {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([this.store.colors.accent])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ShuYoGlass.interactiveButtonMaterial(this.store.colors.isDark))
        .clickEffect(ShuYoMotion.snappyClick)
        .onClick(() => {
          this.onRightTap();
        })
      }
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, {
      colorMode: ShuYoGlass.blurColorMode(this.store.colors.isDark),
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.8
    })
    .border({
      width: { bottom: 0.5 },
      color: this.store.colors.isDark ? '#1FFFFFFF' : '#240F172A'
    })
  }
}

@ComponentV2
export struct ShuYoEmptyState {
  @Param emptyTitle: string = '暂无内容';
  @Param emptyHint: string = '';
  @Param actionText: string = '';
  @Event onActionTap: () => void = () => {};
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  build() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(36)
        .fontColor([this.store.colors.textMuted])
      Text(this.emptyTitle)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.store.colors.textSecondary)
      if (this.emptyHint.length > 0) {
        Text(this.emptyHint)
          .fontSize(13)
          .fontColor(this.store.colors.textTertiary)
          .textAlign(TextAlign.Center)
      }
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .height(36)
          .fontSize(13)
          .fontColor(this.store.colors.onAccent)
          .backgroundColor(this.store.colors.accent)
          .borderRadius(18)
          .padding({ left: 18, right: 18 })
          .margin({ top: 4 })
          .clickEffect(ShuYoMotion.lightClick)
          .onClick(() => {
            this.onActionTap();
          })
      }
    }
    .width('100%')
    .padding({ top: 36, bottom: 36, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}

@ComponentV2
export struct ShuYoSectionHeader {
  @Param sectionTitle: string = '';
  @Param actionLabel: string = '';
  @Event onActionTap: () => void = () => {};
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  build() {
    Row() {
      Text(this.sectionTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.store.colors.textPrimary)
      Blank()
      if (this.actionLabel.length > 0) {
        Text(this.actionLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.colors.accent)
          .clickEffect(ShuYoMotion.lightClick)
          .onClick(() => {
            this.onActionTap();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
