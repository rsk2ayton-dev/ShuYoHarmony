import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function AvatarCropPageBuilder(): void {
  AvatarCropPage()
}

@ComponentV2
export struct AvatarCropPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local selectedImageUri: string = '';
  @Local sourcePixelMap: image.PixelMap | undefined = undefined;
  @Local pixelWidth: number = 0;
  @Local pixelHeight: number = 0;
  @Local stageWidth: number = 320;
  @Local stageHeight: number = 320;
  @Local imgLeft: number = 0;
  @Local imgTop: number = 0;
  @Local imgW: number = 320;
  @Local imgH: number = 320;
  @Local cropX: number = 40;
  @Local cropY: number = 40;
  @Local cropSize: number = 220;
  @Local minCropSize: number = 64;
  @Local maxCropSize: number = 320;
  @Local isDecoding: boolean = false;
  @Local isSaving: boolean = false;
  @Local errorMessage: string = '';

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private dragStartSize: number = 220;
  private pinchStartSize: number = 220;
  private pickerTriggeredOnEnter: boolean = false;

  aboutToAppear(): void {
    this.pickerTriggeredOnEnter = false;
  }

  aboutToDisappear(): void {
    this.releaseSourcePixelMap();
  }

  private releaseSourcePixelMap(): void {
    if (this.sourcePixelMap !== undefined) {
      const old = this.sourcePixelMap;
      this.sourcePixelMap = undefined;
      old.release().catch(() => {});
    }
  }

  private async pickImage(): Promise<void> {
    if (this.isDecoding || this.isSaving) {
      return;
    }
    this.errorMessage = '';
    try {
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(opts);
      if (result.photoUris.length === 0) {
        return;
      }
      await this.decodePickedUri(result.photoUris[0]);
    } catch (err) {
      const e = err as Error;
      this.errorMessage = e.message.length > 0 ? e.message : '选择图片失败，请重试';
    }
  }

  private async decodePickedUri(uri: string): Promise<void> {
    this.isDecoding = true;
    this.errorMessage = '';
    let file: fileIo.File | undefined = undefined;
    let imgSrc: image.ImageSource | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      imgSrc = image.createImageSource(file.fd);
      const info = await imgSrc.getImageInfo();
      const rawW = info.size.width;
      const rawH = info.size.height;
      if (rawW <= 0 || rawH <= 0) {
        throw new Error('所选图片尺寸无效');
      }

      const maxEdge = 1440;
      let targetW = rawW;
      let targetH = rawH;
      if (rawW > maxEdge || rawH > maxEdge) {
        if (rawW >= rawH) {
          targetW = maxEdge;
          targetH = Math.max(1, Math.round((rawH * maxEdge) / rawW));
        } else {
          targetH = maxEdge;
          targetW = Math.max(1, Math.round((rawW * maxEdge) / rawH));
        }
      }

      const decodingOpts: image.DecodingOptions = {
        editable: true,
        desiredSize: { width: targetW, height: targetH }
      };
      const pm = await imgSrc.createPixelMap(decodingOpts);
      const pmInfo = await pm.getImageInfo();
      this.releaseSourcePixelMap();
      this.selectedImageUri = uri;
      this.sourcePixelMap = pm;
      this.pixelWidth = pmInfo.size.width;
      this.pixelHeight = pmInfo.size.height;
      this.recomputeImageLayout(true);
    } catch (err) {
      const e = err as Error;
      this.errorMessage = e.message.length > 0 ? e.message : '无法解析所选图片';
    } finally {
      if (imgSrc !== undefined) {
        try {
          await imgSrc.release();
        } catch (_e) {
          // Ignore release failure
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (_e) {
          // Ignore close failure
        }
      }
      this.isDecoding = false;
    }
  }

  private handleStageAreaChange(newArea: Area): void {
    const w = Number(newArea.width);
    const h = Number(newArea.height);
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 120 || h < 120) {
      return;
    }
    if (Math.abs(w - this.stageWidth) < 1 && Math.abs(h - this.stageHeight) < 1) {
      return;
    }
    this.stageWidth = w;
    this.stageHeight = h;
    this.recomputeImageLayout(false);
  }

  private recomputeImageLayout(resetCrop: boolean): void {
    if (this.pixelWidth <= 0 || this.pixelHeight <= 0 || this.stageWidth <= 0 || this.stageHeight <= 0) {
      return;
    }
    const prevLeft = this.imgLeft;
    const prevTop = this.imgTop;
    const prevW = this.imgW;
    const prevH = this.imgH;

    const imgAspect = this.pixelWidth / this.pixelHeight;
    const stageAspect = this.stageWidth / this.stageHeight;
    let dispW = this.stageWidth;
    let dispH = this.stageHeight;
    if (imgAspect >= stageAspect) {
      dispW = this.stageWidth;
      dispH = this.stageWidth / imgAspect;
    } else {
      dispH = this.stageHeight;
      dispW = this.stageHeight * imgAspect;
    }
    const dispLeft = (this.stageWidth - dispW) / 2;
    const dispTop = (this.stageHeight - dispH) / 2;

    this.imgLeft = dispLeft;
    this.imgTop = dispTop;
    this.imgW = dispW;
    this.imgH = dispH;

    const maxSq = Math.max(16, Math.min(dispW, dispH));
    const minSq = Math.min(64, maxSq);
    this.maxCropSize = maxSq;
    this.minCropSize = minSq;

    if (resetCrop || prevW <= 0 || prevH <= 0) {
      const initial = Math.max(minSq, maxSq * 0.78);
      this.cropSize = initial;
      this.cropX = dispLeft + (dispW - initial) / 2;
      this.cropY = dispTop + (dispH - initial) / 2;
      this.clampCropBox();
      return;
    }

    const scale = dispW / prevW;
    this.cropSize = this.clamp(this.cropSize * scale, minSq, maxSq);
    this.cropX = dispLeft + (this.cropX - prevLeft) * scale;
    this.cropY = dispTop + (this.cropY - prevTop) * scale;
    this.clampCropBox();
  }

  private clamp(val: number, minVal: number, maxVal: number): number {
    if (val < minVal) {
      return minVal;
    }
    if (val > maxVal) {
      return maxVal;
    }
    return val;
  }

  private clampCropBox(): void {
    const size = this.clamp(this.cropSize, this.minCropSize, this.maxCropSize);
    this.cropSize = size;
    const maxX = Math.max(this.imgLeft, this.imgLeft + this.imgW - size);
    const maxY = Math.max(this.imgTop, this.imgTop + this.imgH - size);
    this.cropX = this.clamp(this.cropX, this.imgLeft, maxX);
    this.cropY = this.clamp(this.cropY, this.imgTop, maxY);
  }

  private startBoxPan(): void {
    this.dragStartX = this.cropX;
    this.dragStartY = this.cropY;
  }

  private updateBoxPan(event: GestureEvent): void {
    const maxX = Math.max(this.imgLeft, this.imgLeft + this.imgW - this.cropSize);
    const maxY = Math.max(this.imgTop, this.imgTop + this.imgH - this.cropSize);
    this.cropX = this.clamp(this.dragStartX + event.offsetX, this.imgLeft, maxX);
    this.cropY = this.clamp(this.dragStartY + event.offsetY, this.imgTop, maxY);
  }

  private startCornerResize(): void {
    this.dragStartX = this.cropX;
    this.dragStartY = this.cropY;
    this.dragStartSize = this.cropSize;
  }

  private updateCornerResize(corner: string, event: GestureEvent): void {
    if (corner === 'br') {
      const availMax = Math.min(
        this.maxCropSize,
        this.imgLeft + this.imgW - this.dragStartX,
        this.imgTop + this.imgH - this.dragStartY
      );
      const delta = (event.offsetX + event.offsetY) / 2;
      const newSize = this.clamp(this.dragStartSize + delta, this.minCropSize, Math.max(this.minCropSize, availMax));
      this.cropSize = newSize;
      this.cropX = this.dragStartX;
      this.cropY = this.dragStartY;
      return;
    }

    if (corner === 'tl') {
      const anchorR = this.dragStartX + this.dragStartSize;
      const anchorB = this.dragStartY + this.dragStartSize;
      const availMax = Math.min(this.maxCropSize, anchorR - this.imgLeft, anchorB - this.imgTop);
      const delta = (-event.offsetX - event.offsetY) / 2;
      const newSize = this.clamp(this.dragStartSize + delta, this.minCropSize, Math.max(this.minCropSize, availMax));
      this.cropSize = newSize;
      this.cropX = anchorR - newSize;
      this.cropY = anchorB - newSize;
      return;
    }

    if (corner === 'tr') {
      const anchorL = this.dragStartX;
      const anchorB = this.dragStartY + this.dragStartSize;
      const availMax = Math.min(this.maxCropSize, this.imgLeft + this.imgW - anchorL, anchorB - this.imgTop);
      const delta = (event.offsetX - event.offsetY) / 2;
      const newSize = this.clamp(this.dragStartSize + delta, this.minCropSize, Math.max(this.minCropSize, availMax));
      this.cropSize = newSize;
      this.cropX = anchorL;
      this.cropY = anchorB - newSize;
      return;
    }

    // Bottom-left ('bl')
    const anchorR = this.dragStartX + this.dragStartSize;
    const anchorT = this.dragStartY;
    const availMax = Math.min(this.maxCropSize, anchorR - this.imgLeft, this.imgTop + this.imgH - anchorT);
    const delta = (-event.offsetX + event.offsetY) / 2;
    const newSize = this.clamp(this.dragStartSize + delta, this.minCropSize, Math.max(this.minCropSize, availMax));
    this.cropSize = newSize;
    this.cropX = anchorR - newSize;
    this.cropY = anchorT;
  }

  private startPinchResize(): void {
    this.pinchStartSize = this.cropSize;
  }

  private updatePinchResize(event: GestureEvent): void {
    this.resizeAroundCenter(this.pinchStartSize * event.scale);
  }

  private resizeAroundCenter(targetSize: number): void {
    const centerX = this.cropX + this.cropSize / 2;
    const centerY = this.cropY + this.cropSize / 2;
    const nextSize = this.clamp(targetSize, this.minCropSize, this.maxCropSize);
    this.cropSize = nextSize;
    this.cropX = centerX - nextSize / 2;
    this.cropY = centerY - nextSize / 2;
    this.clampCropBox();
  }

  private nudgeCropSize(delta: number): void {
    this.resizeAroundCenter(this.cropSize + delta);
  }

  private getEstimatedCropPx(): number {
    if (this.pixelWidth <= 0 || this.imgW <= 0) {
      return 0;
    }
    return Math.max(1, Math.round((this.cropSize * this.pixelWidth) / this.imgW));
  }

  private getRightMaskLeft(): number {
    return this.cropX + this.cropSize;
  }

  private getRightMaskWidth(): number {
    return Math.max(0, this.stageWidth - (this.cropX + this.cropSize));
  }

  private getBottomMaskTop(): number {
    return this.cropY + this.cropSize;
  }

  private getBottomMaskHeight(): number {
    return Math.max(0, this.stageHeight - (this.cropY + this.cropSize));
  }

  private getCornerSizeLabel(): string {
    const px = this.getEstimatedCropPx();
    return px > 0 ? `选区像素：${px} × ${px} px` : '拖动框内移动选区，拖动四角或滑块缩放选择框';
  }

  private async decodeFreshSavePixelMap(): Promise<image.PixelMap | undefined> {
    if (this.selectedImageUri.length === 0) {
      return undefined;
    }
    let file: fileIo.File | undefined = undefined;
    let imgSrc: image.ImageSource | undefined = undefined;
    try {
      file = fileIo.openSync(this.selectedImageUri, fileIo.OpenMode.READ_ONLY);
      imgSrc = image.createImageSource(file.fd);
      const opts: image.DecodingOptions = {
        editable: true,
        desiredSize: { width: this.pixelWidth, height: this.pixelHeight }
      };
      return await imgSrc.createPixelMap(opts);
    } catch (_err) {
      return undefined;
    } finally {
      if (imgSrc !== undefined) {
        try {
          await imgSrc.release();
        } catch (_e) {
          // Ignore release error
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (_e) {
          // Ignore close error
        }
      }
    }
  }

  private removeOldAvatarFiles(filesDir: string, keepFileName: string): void {
    try {
      const names = fileIo.listFileSync(filesDir);
      for (let i = 0; i < names.length; i++) {
        const fn = names[i];
        if (fn.startsWith('shuyo_avatar_') && fn.endsWith('.jpg') && fn !== keepFileName) {
          try {
            fileIo.unlinkSync(`${filesDir}/${fn}`);
          } catch (_err) {
            // Ignore single unlink failure
          }
        }
      }
    } catch (_err) {
      // Ignore directory list failure
    }
  }

  private async saveCroppedAvatar(): Promise<void> {
    if (this.sourcePixelMap === undefined || this.pixelWidth <= 0 || this.pixelHeight <= 0 ||
      this.imgW <= 0 || this.imgH <= 0 || this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = '';

    let workingPm: image.PixelMap | undefined = undefined;
    let shouldReleaseWorkingPm = false;
    let packer: image.ImagePacker | undefined = undefined;
    let outFile: fileIo.File | undefined = undefined;

    try {
      workingPm = await this.decodeFreshSavePixelMap();
      if (workingPm !== undefined) {
        shouldReleaseWorkingPm = true;
      } else {
        workingPm = this.sourcePixelMap;
        this.sourcePixelMap = undefined;
        shouldReleaseWorkingPm = true;
      }

      const workInfo = await workingPm.getImageInfo();
      const wPx = workInfo.size.width;
      const hPx = workInfo.size.height;

      const scaleX = wPx / this.imgW;
      const scaleY = hPx / this.imgH;
      let pxX = Math.round((this.cropX - this.imgLeft) * scaleX);
      let pxY = Math.round((this.cropY - this.imgTop) * scaleY);
      let pxSize = Math.round(this.cropSize * Math.min(scaleX, scaleY));

      if (pxSize < 1) {
        pxSize = 1;
      }
      if (pxX < 0) {
        pxX = 0;
      }
      if (pxY < 0) {
        pxY = 0;
      }
      if (pxSize > wPx) {
        pxSize = wPx;
      }
      if (pxSize > hPx) {
        pxSize = hPx;
      }
      if (pxX + pxSize > wPx) {
        pxX = Math.max(0, wPx - pxSize);
      }
      if (pxY + pxSize > hPx) {
        pxY = Math.max(0, hPx - pxSize);
      }

      await workingPm.crop({
        x: pxX,
        y: pxY,
        size: { width: pxSize, height: pxSize }
      });

      if (pxSize > 512) {
        const ratio = 512 / pxSize;
        await workingPm.scale(ratio, ratio);
      }

      const hostCtx = this.getUIContext().getHostContext();
      if (hostCtx === undefined) {
        throw new Error('无法获取应用存储目录');
      }
      const filesDir = hostCtx.filesDir;
      const fileName = `shuyo_avatar_${Date.now()}.jpg`;
      const outPath = `${filesDir}/${fileName}`;

      outFile = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      packer = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 92
      };
      await packer.packToFile(workingPm, outFile.fd, packOpts);
      fileIo.closeSync(outFile);
      outFile = undefined;

      this.removeOldAvatarFiles(filesDir, fileName);
      const localUri = fileUri.getUriFromPath(outPath);
      this.store.setCustomAvatarUri(localUri);
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新' });
      this.navStack.pop();
    } catch (err) {
      const e = err as Error;
      this.errorMessage = e.message.length > 0 ? e.message : '保存裁剪头像失败，请重试';
    } finally {
      if (outFile !== undefined) {
        try {
          fileIo.closeSync(outFile);
        } catch (_e) {
          // Ignore close error
        }
      }
      if (packer !== undefined) {
        try {
          await packer.release();
        } catch (_e) {
          // Ignore packer release error
        }
      }
      if (shouldReleaseWorkingPm && workingPm !== undefined) {
        try {
          await workingPm.release();
        } catch (_e) {
          // Ignore pixelmap release error
        }
      }
      this.isSaving = false;
    }
  }

  private resetAvatarToDefault(): void {
    this.store.clearCustomAvatar();
    this.getUIContext().getPromptAction().showToast({ message: '已恢复默认头像' });
    this.navStack.pop();
  }

  @Builder
  private cornerHandle(cornerKey: string, xPos: number, yPos: number) {
    Column() {
      Column()
        .width(12)
        .height(12)
        .borderRadius(6)
        .backgroundColor('#FFFFFF')
        .border({ width: 2, color: this.store.colors.accent })
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: xPos, y: yPos })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All })
        .onActionStart(() => {
          this.startCornerResize();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateCornerResize(cornerKey, event);
        })
    )
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        ShuYoTopBar({
          headerTitle: '自定义头像',
          subtitleText: '选择图片并调整方形/圆形头像选区',
          showBack: true,
          rightLabel: this.sourcePixelMap !== undefined ? '重新选图' : '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.pickImage();
          }
        })

        if (this.sourcePixelMap === undefined) {
          Column({ space: 16 }) {
            if (this.store.customAvatarUri.length > 0) {
              Image(this.store.customAvatarUri)
                .width(96)
                .height(96)
                .borderRadius(48)
                .objectFit(ImageFit.Cover)
                .border({ width: 2, color: this.store.colors.accent })
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.person'))
                  .fontSize(44)
                  .fontColor([this.store.colors.accent])
              }
              .width(96)
              .height(96)
              .borderRadius(48)
              .backgroundColor(this.store.colors.accentSoft)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }

            Text(this.isDecoding ? '正在读取图片...' : '从系统相册选择图片')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)

            Text('选图后可拖动裁切框选择保留部位，并通过四角拖拽、双指捏合或下方滑块放大缩小选择框。')
              .fontSize(13)
              .fontColor(this.store.colors.textSecondary)
              .textAlign(TextAlign.Center)
              .padding({ left: 12, right: 12 })

            if (this.errorMessage.length > 0) {
              Text(this.errorMessage)
                .fontSize(12)
                .fontColor(this.store.colors.danger)
                .textAlign(TextAlign.Center)
            }

            if (this.isDecoding) {
              LoadingProgress().width(32).height(32).color(this.store.colors.accent)
            } else {
              Button('选择相册图片')
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(12)
                .onClick(() => {
                  this.pickImage();
                })

              if (this.store.customAvatarUri.length > 0) {
                Button('恢复默认头像')
                  .width('100%')
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.colors.danger)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .border({ width: 1, color: this.store.colors.border })
                  .borderRadius(12)
                  .onClick(() => {
                    this.resetAvatarToDefault();
                  })
              }
            }
          }
          .width('92%')
          .padding(24)
          .margin({ top: 20 })
          .borderRadius(18)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              // Crop Stage
              Stack({ alignContent: Alignment.TopStart }) {
                Image(this.sourcePixelMap)
                  .width(this.imgW)
                  .height(this.imgH)
                  .objectFit(ImageFit.Fill)
                  .position({ x: this.imgLeft, y: this.imgTop })

                // Top mask
                Column()
                  .width(this.stageWidth)
                  .height(Math.max(0, this.cropY))
                  .backgroundColor('#99000000')
                  .position({ x: 0, y: 0 })

                // Bottom mask
                Column()
                  .width(this.stageWidth)
                  .height(this.getBottomMaskHeight())
                  .backgroundColor('#99000000')
                  .position({ x: 0, y: this.getBottomMaskTop() })

                // Left mask
                Column()
                  .width(Math.max(0, this.cropX))
                  .height(this.cropSize)
                  .backgroundColor('#99000000')
                  .position({ x: 0, y: this.cropY })

                // Right mask
                Column()
                  .width(this.getRightMaskWidth())
                  .height(this.cropSize)
                  .backgroundColor('#99000000')
                  .position({ x: this.getRightMaskLeft(), y: this.cropY })

                // Draggable crop selection box with circular preview guide
                Stack({ alignContent: Alignment.Center }) {
                  // Vertical thirds guides
                  Row() {
                    Blank().layoutWeight(1)
                    Column().width(0.5).height('100%').backgroundColor('#66FFFFFF')
                    Blank().layoutWeight(1)
                    Column().width(0.5).height('100%').backgroundColor('#66FFFFFF')
                    Blank().layoutWeight(1)
                  }
                  .width('100%')
                  .height('100%')

                  // Horizontal thirds guides
                  Column() {
                    Blank().layoutWeight(1)
                    Row().width('100%').height(0.5).backgroundColor('#66FFFFFF')
                    Blank().layoutWeight(1)
                    Row().width('100%').height(0.5).backgroundColor('#66FFFFFF')
                    Blank().layoutWeight(1)
                  }
                  .width('100%')
                  .height('100%')

                  // Circular avatar preview boundary
                  Column()
                    .width('100%')
                    .height('100%')
                    .borderRadius(this.cropSize / 2)
                    .border({ width: 1, color: '#AAFFFFFF', style: BorderStyle.Dashed })
                }
                .width(this.cropSize)
                .height(this.cropSize)
                .position({ x: this.cropX, y: this.cropY })
                .border({ width: 2, color: '#FFFFFF' })
                .gesture(
                  PanGesture({ fingers: 1, direction: PanDirection.All })
                    .onActionStart(() => {
                      this.startBoxPan();
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      this.updateBoxPan(event);
                    })
                )

                // 4 independent corner resize handles (siblings so they don't bubble to box pan)
                this.cornerHandle('tl', this.cropX - 14, this.cropY - 14)
                this.cornerHandle('tr', this.cropX + this.cropSize - 14, this.cropY - 14)
                this.cornerHandle('bl', this.cropX - 14, this.cropY + this.cropSize - 14)
                this.cornerHandle('br', this.cropX + this.cropSize - 14, this.cropY + this.cropSize - 14)
              }
              .width('100%')
              .aspectRatio(1)
              .borderRadius(14)
              .clip(true)
              .backgroundColor('#111111')
              .onAreaChange((_oldVal: Area, newVal: Area) => {
                this.handleStageAreaChange(newVal);
              })
              .gesture(
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.startPinchResize();
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.updatePinchResize(event);
                  })
              )

              // Resize Slider & Fine Controls
              Column({ space: 8 }) {
                Row() {
                  Text('选区大小调节（支持双指缩放与四角拖拽）')
                    .fontSize(12)
                    .fontColor(this.store.colors.textSecondary)
                    .layoutWeight(1)
                  Text(this.getCornerSizeLabel())
                    .fontSize(11)
                    .fontColor(this.store.colors.accent)
                }
                .width('100%')

                Row({ space: 10 }) {
                  Button('缩小')
                    .height(32)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .border({ width: 1, color: this.store.colors.border })
                    .borderRadius(10)
                    .onClick(() => {
                      this.nudgeCropSize(-20);
                    })

                  Slider({
                    value: this.cropSize,
                    min: this.minCropSize,
                    max: Math.max(this.minCropSize + 1, this.maxCropSize),
                    step: 1,
                    style: SliderStyle.OutSet
                  })
                    .layoutWeight(1)
                    .selectedColor(this.store.colors.accent)
                    .onChange((val: number) => {
                      this.resizeAroundCenter(val);
                    })

                  Button('放大')
                    .height(32)
                    .fontSize(12)
                    .fontColor(this.store.colors.textPrimary)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .border({ width: 1, color: this.store.colors.border })
                    .borderRadius(10)
                    .onClick(() => {
                      this.nudgeCropSize(20);
                    })
                }
                .width('100%')

                if (this.errorMessage.length > 0) {
                  Text(this.errorMessage)
                    .fontSize(12)
                    .fontColor(this.store.colors.danger)
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })

              // Bottom Action Buttons
              Row({ space: 10 }) {
                if (this.store.customAvatarUri.length > 0) {
                  Button('恢复默认')
                    .height(44)
                    .fontSize(14)
                    .fontColor(this.store.colors.danger)
                    .backgroundColor(this.store.colors.surface)
                    .border({ width: 1, color: this.store.colors.border })
                    .borderRadius(12)
                    .padding({ left: 14, right: 14 })
                    .onClick(() => {
                      this.resetAvatarToDefault();
                    })
                }

                Button('重选图片')
                  .height(44)
                  .fontSize(14)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                  .borderRadius(12)
                  .padding({ left: 14, right: 14 })
                  .onClick(() => {
                    this.pickImage();
                  })

                Button(this.isSaving ? '正在保存...' : '保存头像')
                  .layoutWeight(1)
                  .height(44)
                  .fontSize(15)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(12)
                  .enabled(!this.isSaving && !this.isDecoding)
                  .onClick(() => {
                    this.saveCroppedAvatar();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
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
    .onShown(() => {
      if (!this.pickerTriggeredOnEnter && this.sourcePixelMap === undefined) {
        this.pickerTriggeredOnEnter = true;
        this.pickImage();
      }
    })
  }
}
