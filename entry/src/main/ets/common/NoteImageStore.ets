import { Context } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import {
  NOTE_IMAGE_COMPRESS_DIMENSION,
  NOTE_IMAGE_DIMENSION_MAX,
  NOTE_IMAGE_FILE_MAX_BYTES,
  NOTE_IMAGE_INPUT_MAX_BYTES,
  NOTE_IMAGE_TOTAL_MAX_BYTES,
  NoteImageAsset
} from './Models';

export const IMAGE_IMPORT_INVALID: string = 'invalid';
export const IMAGE_IMPORT_INPUT_TOO_LARGE: string = 'inputTooLarge';
export const IMAGE_IMPORT_DIMENSIONS_TOO_LARGE: string = 'dimensionsTooLarge';
export const IMAGE_IMPORT_COMPRESSION_DISABLED: string = 'compressionDisabled';
export const IMAGE_IMPORT_ANIMATED_TOO_LARGE: string = 'animatedTooLarge';
export const IMAGE_IMPORT_STORAGE_FULL: string = 'storageFull';
export const IMAGE_IMPORT_OUTPUT_TOO_LARGE: string = 'outputTooLarge';
export const IMAGE_IMPORT_CANCELLED: string = 'cancelled';
export const IMAGE_IMPORT_FAILED: string = 'failed';

const COPY_BUFFER_BYTES: number = 256 * 1024;
const COPY_TOO_LARGE: number = -1;
const COPY_CANCELLED: number = -2;
const ORPHAN_GRACE_MS: number = 24 * 60 * 60 * 1000;

export interface NoteImageImportResult {
  asset?: NoteImageAsset;
  errorCode?: string;
  errorDetail?: string;
}

interface EncodedImageResult {
  width: number;
  height: number;
  mimeType: string;
  byteLength: number;
}

export class NoteImageStore {
  static async importFromUri(context: Context, noteId: string, uri: string,
    autoCompress: boolean, currentTotalBytes: number,
    isCancelled?: () => boolean): Promise<NoteImageImportResult> {
    if (uri.length === 0 || noteId.length === 0) {
      return { errorCode: IMAGE_IMPORT_INVALID };
    }
    if (NoteImageStore.cancelled(isCancelled)) {
      return { errorCode: IMAGE_IMPORT_CANCELLED };
    }

    const directory: string = context.filesDir + '/note-images';
    const id: string = NoteImageStore.createId();
    const stagingPath: string = directory + '/' + id + '.importing';
    const encodedPath: string = directory + '/' + id + '.encoding';
    let finalPath: string = '';
    let sourceFd: number = -1;
    let stagingFd: number = -1;
    let imageSource: image.ImageSource | undefined = undefined;

    try {
      fileIo.mkdirSync(directory, true);
      const selectedFile: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      sourceFd = selectedFile.fd;
      const copiedBytes: number = await NoteImageStore.copyToStagingBounded(
        sourceFd, stagingPath, isCancelled);
      fileIo.closeSync(sourceFd);
      sourceFd = -1;
      if (copiedBytes === COPY_CANCELLED || NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      if (copiedBytes === COPY_TOO_LARGE) {
        return { errorCode: IMAGE_IMPORT_INPUT_TOO_LARGE };
      }
      const stagedBytes: number = fileIo.statSync(stagingPath).size;
      if (stagedBytes <= 0) {
        return { errorCode: IMAGE_IMPORT_INVALID };
      }
      if (stagedBytes > NOTE_IMAGE_INPUT_MAX_BYTES || stagedBytes !== copiedBytes) {
        return { errorCode: IMAGE_IMPORT_INPUT_TOO_LARGE };
      }

      const stagingFile: fileIo.File = fileIo.openSync(stagingPath, fileIo.OpenMode.READ_ONLY);
      stagingFd = stagingFile.fd;
      imageSource = image.createImageSource(stagingFd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      const sourceWidth: number = info.size.width;
      const sourceHeight: number = info.size.height;
      const sourceMime: string = NoteImageStore.normalizeMimeType(info.mimeType);
      if (sourceWidth <= 0 || sourceHeight <= 0 || sourceMime.length === 0) {
        return { errorCode: IMAGE_IMPORT_INVALID };
      }
      if (sourceWidth > NOTE_IMAGE_DIMENSION_MAX || sourceHeight > NOTE_IMAGE_DIMENSION_MAX) {
        return { errorCode: IMAGE_IMPORT_DIMENSIONS_TOO_LARGE };
      }

      const orientation: string = await NoteImageStore.readOrientation(imageSource);
      const displaySize: image.Size = NoteImageStore.displaySize(sourceWidth, sourceHeight, orientation);
      const frameCount: number = await NoteImageStore.readFrameCount(imageSource);
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      const exceedsFileLimit: boolean = stagedBytes > NOTE_IMAGE_FILE_MAX_BYTES;
      const benefitsFromCompression: boolean = exceedsFileLimit ||
        sourceWidth > NOTE_IMAGE_COMPRESS_DIMENSION || sourceHeight > NOTE_IMAGE_COMPRESS_DIMENSION;
      let activePath: string = stagingPath;
      let finalMime: string = sourceMime;
      let finalWidth: number = displaySize.width;
      let finalHeight: number = displaySize.height;
      let activeBytes: number = stagedBytes;

      if (benefitsFromCompression && autoCompress) {
        if (frameCount > 1) {
          return { errorCode: IMAGE_IMPORT_ANIMATED_TOO_LARGE };
        }
        const encoded: EncodedImageResult | null = await NoteImageStore.encodeWithinLimit(
          imageSource, sourceWidth, sourceHeight, orientation, sourceMime, encodedPath, isCancelled);
        if (NoteImageStore.cancelled(isCancelled)) {
          return { errorCode: IMAGE_IMPORT_CANCELLED };
        }
        if (encoded === null) {
          return { errorCode: IMAGE_IMPORT_OUTPUT_TOO_LARGE };
        }
        activePath = encodedPath;
        finalMime = encoded.mimeType;
        finalWidth = encoded.width;
        finalHeight = encoded.height;
        activeBytes = encoded.byteLength;
      } else if (exceedsFileLimit) {
        return { errorCode: IMAGE_IMPORT_COMPRESSION_DISABLED };
      }

      if (activeBytes <= 0 || activeBytes > NOTE_IMAGE_FILE_MAX_BYTES) {
        return { errorCode: IMAGE_IMPORT_OUTPUT_TOO_LARGE };
      }
      if (!NoteImageStore.canReserveBytes(currentTotalBytes, activeBytes)) {
        return { errorCode: IMAGE_IMPORT_STORAGE_FULL };
      }

      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }

      await imageSource.release();
      imageSource = undefined;
      fileIo.closeSync(stagingFd);
      stagingFd = -1;
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }

      const fileName: string = id + NoteImageStore.extensionForMime(finalMime);
      finalPath = directory + '/' + fileName;
      if (fileIo.accessSync(finalPath)) {
        return { errorCode: IMAGE_IMPORT_FAILED, errorDetail: 'asset collision' };
      }
      fileIo.renameSync(activePath, finalPath);
      return {
        asset: {
          id: id,
          noteId: noteId,
          fileName: fileName,
          mimeType: finalMime,
          width: finalWidth,
          height: finalHeight,
          byteLength: activeBytes,
          createdAt: Date.now()
        }
      };
    } catch (error) {
      return { errorCode: IMAGE_IMPORT_FAILED, errorDetail: String(error) };
    } finally {
      NoteImageStore.closeFd(sourceFd);
      if (imageSource !== undefined) {
        try {
          await imageSource.release();
        } catch (error) {
          console.warn('release image source failed: ' + String(error));
        }
      }
      NoteImageStore.closeFd(stagingFd);
      NoteImageStore.deleteIfTemporary(stagingPath, finalPath);
      NoteImageStore.deleteIfTemporary(encodedPath, finalPath);
    }
  }

  static async importFromPixelMap(context: Context, noteId: string, pixelMap: image.PixelMap,
    autoCompress: boolean, currentTotalBytes: number,
    isCancelled?: () => boolean): Promise<NoteImageImportResult> {
    const directory: string = context.filesDir + '/note-images';
    let temporaryPath: string = '';
    try {
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      if (info.size.width <= 0 || info.size.height <= 0) {
        return { errorCode: IMAGE_IMPORT_INVALID };
      }
      if (info.size.width > NOTE_IMAGE_DIMENSION_MAX || info.size.height > NOTE_IMAGE_DIMENSION_MAX) {
        return { errorCode: IMAGE_IMPORT_DIMENSIONS_TOO_LARGE };
      }
      fileIo.mkdirSync(directory, true);
      const preserveAlpha: boolean = info.alphaType !== image.AlphaType.OPAQUE;
      const mimeType: string = preserveAlpha ? 'image/png' : 'image/jpeg';
      temporaryPath = directory + '/' + NoteImageStore.createClipboardTemporaryFileName(mimeType);
      const bytes: number = await NoteImageStore.packPixelMap(
        pixelMap, temporaryPath, mimeType, preserveAlpha ? 100 : 92);
      if (NoteImageStore.cancelled(isCancelled)) {
        return { errorCode: IMAGE_IMPORT_CANCELLED };
      }
      if (bytes <= 0) {
        return { errorCode: IMAGE_IMPORT_INVALID };
      }
      if (bytes > NOTE_IMAGE_INPUT_MAX_BYTES) {
        return { errorCode: IMAGE_IMPORT_INPUT_TOO_LARGE };
      }
      return await NoteImageStore.importFromUri(
        context, noteId, fileUri.getUriFromPath(temporaryPath), autoCompress, currentTotalBytes, isCancelled);
    } catch (error) {
      return { errorCode: IMAGE_IMPORT_FAILED, errorDetail: String(error) };
    } finally {
      if (temporaryPath.length > 0) {
        NoteImageStore.deletePath(temporaryPath);
      }
    }
  }

  static reconcileAssets(context: Context, assets: NoteImageAsset[]): NoteImageAsset[] {
    const result: NoteImageAsset[] = [];
    for (let i: number = 0; i < assets.length; i++) {
      const path: string = NoteImageStore.assetPath(context, assets[i]);
      if (path.length === 0) {
        continue;
      }
      try {
        const stat: fileIo.Stat = fileIo.statSync(path);
        if (!stat.isFile() || stat.size <= 0 || stat.size > NOTE_IMAGE_FILE_MAX_BYTES) {
          continue;
        }
        result.push({
          id: assets[i].id,
          noteId: assets[i].noteId,
          fileName: assets[i].fileName,
          mimeType: assets[i].mimeType,
          width: assets[i].width,
          height: assets[i].height,
          byteLength: stat.size,
          createdAt: assets[i].createdAt
        });
      } catch (error) {
        console.warn('reconcile note image failed: ' + String(error));
      }
    }
    return result;
  }

  static cleanupOrphans(context: Context, protectedFileNames: string[]): void {
    const directory: string = context.filesDir + '/note-images';
    try {
      if (!fileIo.accessSync(directory)) {
        return;
      }
      const names: string[] = fileIo.listFileSync(directory);
      const now: number = Date.now();
      for (let i: number = 0; i < names.length; i++) {
        const name: string = names[i];
        const path: string = directory + '/' + name;
        const isTemporary: boolean = NoteImageStore.isTemporaryFileName(name);
        if (!isTemporary && !NoteImageStore.isManagedFileName(name)) {
          continue;
        }
        try {
          const stat: fileIo.Stat = fileIo.statSync(path);
          if (stat.isFile() && NoteImageStore.shouldCleanupEntry(
            name, protectedFileNames, stat.mtime, now)) {
            NoteImageStore.deletePath(path);
          }
        } catch (error) {
          console.warn('clean note image entry failed: ' + name + ': ' + String(error));
        }
      }
    } catch (error) {
      console.warn('clean note image directory failed: ' + String(error));
    }
  }

  static assetPath(context: Context, asset: NoteImageAsset): string {
    if (!NoteImageStore.isManagedAssetIdentity(asset)) {
      return '';
    }
    return context.filesDir + '/note-images/' + asset.fileName;
  }

  static assetUri(context: Context, asset: NoteImageAsset): string {
    const path: string = NoteImageStore.assetPath(context, asset);
    return path.length > 0 ? fileUri.getUriFromPath(path) : '';
  }

  static assetExists(context: Context, asset: NoteImageAsset): boolean {
    const path: string = NoteImageStore.assetPath(context, asset);
    if (path.length === 0) {
      return false;
    }
    try {
      return fileIo.statSync(path).isFile();
    } catch (error) {
      return false;
    }
  }

  static deleteAsset(context: Context, asset: NoteImageAsset, expectedNoteId: string): void {
    if (!NoteImageStore.isOwnedManagedAsset(asset, expectedNoteId)) {
      return;
    }
    const path: string = NoteImageStore.assetPath(context, asset);
    if (path.length > 0) {
      NoteImageStore.deletePath(path);
    }
  }

  static isManagedFileName(fileName: string): boolean {
    return /^img_[0-9]+_[0-9]+\.(png|jpg|webp|gif|bmp|tiff)$/.test(fileName);
  }

  static isManagedAssetIdentity(asset: NoteImageAsset): boolean {
    const extension: string = NoteImageStore.extensionForMime(asset.mimeType);
    return /^img_[0-9]+_[0-9]+$/.test(asset.id) && extension.length > 0 &&
      asset.fileName === asset.id + extension && NoteImageStore.isManagedFileName(asset.fileName);
  }

  static isOwnedManagedAsset(asset: NoteImageAsset, expectedNoteId: string): boolean {
    return expectedNoteId.length > 0 && asset.noteId === expectedNoteId &&
      NoteImageStore.isManagedAssetIdentity(asset);
  }

  static canReserveBytes(currentTotalBytes: number, additionalBytes: number): boolean {
    return Number.isFinite(currentTotalBytes) && Number.isFinite(additionalBytes) &&
      currentTotalBytes >= 0 && additionalBytes > 0 && currentTotalBytes <= NOTE_IMAGE_TOTAL_MAX_BYTES &&
      additionalBytes <= NOTE_IMAGE_TOTAL_MAX_BYTES - currentTotalBytes;
  }

  static isTemporaryFileName(fileName: string): boolean {
    if (/^img_[0-9]+_[0-9]+\.(importing|encoding)$/.test(fileName)) {
      return true;
    }
    // The first form recognizes crash leftovers created before clipboard
    // imports gained a random suffix; the second is the current format.
    return /^clipboard_[0-9]+(?:_[0-9]+)?\.(png|jpg)$/.test(fileName);
  }

  static shouldCleanupEntry(fileName: string, protectedFileNames: string[], modifiedAt: number,
    now: number): boolean {
    if (NoteImageStore.isTemporaryFileName(fileName)) {
      return true;
    }
    if (!NoteImageStore.isManagedFileName(fileName) || NoteImageStore.contains(protectedFileNames, fileName) ||
      !Number.isFinite(modifiedAt) || !Number.isFinite(now) || modifiedAt > now) {
      return false;
    }
    return now - modifiedAt >= ORPHAN_GRACE_MS;
  }

  static isSupportedMimeType(mimeType: string): boolean {
    return NoteImageStore.normalizeMimeType(mimeType).length > 0;
  }

  static extensionForMime(mimeType: string): string {
    if (mimeType === 'image/png') {
      return '.png';
    }
    if (mimeType === 'image/webp') {
      return '.webp';
    }
    if (mimeType === 'image/gif') {
      return '.gif';
    }
    if (mimeType === 'image/bmp') {
      return '.bmp';
    }
    if (mimeType === 'image/tiff') {
      return '.tiff';
    }
    return mimeType === 'image/jpeg' ? '.jpg' : '';
  }

  private static async copyToStagingBounded(sourceFd: number, stagingPath: string,
    isCancelled?: () => boolean): Promise<number> {
    let outputFd: number = -1;
    try {
      const output: fileIo.File = fileIo.openSync(stagingPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      outputFd = output.fd;
      const buffer: ArrayBuffer = new ArrayBuffer(COPY_BUFFER_BYTES);
      let total: number = 0;
      while (true) {
        if (NoteImageStore.cancelled(isCancelled)) {
          return COPY_CANCELLED;
        }
        const readBytes: number = await fileIo.read(sourceFd, buffer);
        if (NoteImageStore.cancelled(isCancelled)) {
          return COPY_CANCELLED;
        }
        if (readBytes <= 0) {
          break;
        }
        if (total + readBytes > NOTE_IMAGE_INPUT_MAX_BYTES) {
          return COPY_TOO_LARGE;
        }
        let written: number = 0;
        while (written < readBytes) {
          const remaining: ArrayBuffer = written === 0 ? buffer.slice(0, readBytes) : buffer.slice(written, readBytes);
          const count: number = await fileIo.write(outputFd, remaining);
          if (NoteImageStore.cancelled(isCancelled)) {
            return COPY_CANCELLED;
          }
          if (count <= 0) {
            throw new Error('image copy made no progress');
          }
          written += count;
        }
        total += readBytes;
      }
      return total;
    } catch (error) {
      throw new Error(String(error));
    } finally {
      NoteImageStore.closeFd(outputFd);
    }
  }

  private static async encodeWithinLimit(source: image.ImageSource, sourceWidth: number, sourceHeight: number,
    orientation: string, sourceMime: string, outputPath: string,
    isCancelled?: () => boolean): Promise<EncodedImageResult | null> {
    let targetEdge: number = Math.min(NOTE_IMAGE_COMPRESS_DIMENSION, Math.max(sourceWidth, sourceHeight));
    for (let attempt: number = 0; attempt < 6; attempt++) {
      if (NoteImageStore.cancelled(isCancelled)) {
        return null;
      }
      const scale: number = Math.min(1, targetEdge / Math.max(sourceWidth, sourceHeight));
      const targetWidth: number = Math.max(1, Math.round(sourceWidth * scale));
      const targetHeight: number = Math.max(1, Math.round(sourceHeight * scale));
      let pixelMap: image.PixelMap | undefined = undefined;
      try {
        pixelMap = await source.createPixelMap({
          desiredSize: { width: targetWidth, height: targetHeight },
          editable: true
        });
        if (NoteImageStore.cancelled(isCancelled)) {
          return null;
        }
        await NoteImageStore.applyOrientation(pixelMap, orientation);
        const pixelInfo: image.ImageInfo = await pixelMap.getImageInfo();
        const preserveAlpha: boolean = NoteImageStore.shouldPreserveAlpha(sourceMime, pixelInfo.alphaType);
        const outputMime: string = preserveAlpha ? 'image/png' : 'image/jpeg';
        const qualities: number[] = preserveAlpha ? [100] : [84, 72, 60, 48];
        for (let qualityIndex: number = 0; qualityIndex < qualities.length; qualityIndex++) {
          if (NoteImageStore.cancelled(isCancelled)) {
            return null;
          }
          const byteLength: number = await NoteImageStore.packPixelMap(
            pixelMap, outputPath, outputMime, qualities[qualityIndex]);
          if (NoteImageStore.cancelled(isCancelled)) {
            return null;
          }
          if (byteLength > 0 && byteLength <= NOTE_IMAGE_FILE_MAX_BYTES) {
            return {
              width: pixelInfo.size.width,
              height: pixelInfo.size.height,
              mimeType: outputMime,
              byteLength: byteLength
            };
          }
        }
      } finally {
        if (pixelMap !== undefined) {
          try {
            await pixelMap.release();
          } catch (error) {
            console.warn('release compressed pixel map failed: ' + String(error));
          }
        }
      }
      targetEdge = Math.max(384, Math.floor(targetEdge * 0.75));
    }
    return null;
  }

  private static async packPixelMap(pixelMap: image.PixelMap, outputPath: string,
    mimeType: string, quality: number): Promise<number> {
    let outputFd: number = -1;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      const output: fileIo.File = fileIo.openSync(outputPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      outputFd = output.fd;
      packer = image.createImagePacker();
      await packer.packToFile(pixelMap, outputFd, { format: mimeType, quality: quality });
      fileIo.closeSync(outputFd);
      outputFd = -1;
      return fileIo.statSync(outputPath).size;
    } catch (error) {
      throw new Error(String(error));
    } finally {
      NoteImageStore.closeFd(outputFd);
      if (packer !== undefined) {
        try {
          await packer.release();
        } catch (error) {
          console.warn('release image packer failed: ' + String(error));
        }
      }
    }
  }

  private static async applyOrientation(pixelMap: image.PixelMap, orientation: string): Promise<void> {
    if (orientation === 'Top-right') {
      await pixelMap.flip(true, false);
    } else if (orientation === 'Bottom-right') {
      await pixelMap.rotate(180);
    } else if (orientation === 'Bottom-left') {
      await pixelMap.flip(false, true);
    } else if (orientation === 'Left-top') {
      await pixelMap.flip(true, false);
      await pixelMap.rotate(270);
    } else if (orientation === 'Right-top') {
      await pixelMap.rotate(90);
    } else if (orientation === 'Right-bottom') {
      await pixelMap.flip(true, false);
      await pixelMap.rotate(90);
    } else if (orientation === 'Left-bottom') {
      await pixelMap.rotate(270);
    }
  }

  private static async readOrientation(source: image.ImageSource): Promise<string> {
    try {
      return await source.getImageProperty(image.PropertyKey.ORIENTATION);
    } catch (error) {
      return 'Top-left';
    }
  }

  private static async readFrameCount(source: image.ImageSource): Promise<number> {
    try {
      return Math.max(1, await source.getFrameCount());
    } catch (error) {
      return 1;
    }
  }

  private static displaySize(width: number, height: number, orientation: string): image.Size {
    if (orientation === 'Left-top' || orientation === 'Right-top' ||
      orientation === 'Right-bottom' || orientation === 'Left-bottom') {
      return { width: height, height: width };
    }
    return { width: width, height: height };
  }

  private static shouldPreserveAlpha(sourceMime: string, alphaType: image.AlphaType): boolean {
    if (sourceMime === 'image/jpeg' || sourceMime === 'image/bmp' || sourceMime === 'image/tiff') {
      return false;
    }
    return alphaType !== image.AlphaType.OPAQUE;
  }

  private static cancelled(isCancelled?: () => boolean): boolean {
    if (isCancelled === undefined) {
      return false;
    }
    try {
      return isCancelled();
    } catch (error) {
      console.warn('image cancellation check failed: ' + String(error));
      return true;
    }
  }

  private static normalizeMimeType(mimeType: string): string {
    const normalized: string = mimeType.toLowerCase().trim();
    if (normalized === 'image/jpeg' || normalized === 'image/jpg' || normalized === 'image/pjpeg') {
      return 'image/jpeg';
    }
    if (normalized === 'image/png' || normalized === 'image/x-png') {
      return 'image/png';
    }
    if (normalized === 'image/webp' || normalized === 'image/gif') {
      return normalized;
    }
    if (normalized === 'image/bmp' || normalized === 'image/x-bmp' || normalized === 'image/x-ms-bmp') {
      return 'image/bmp';
    }
    if (normalized === 'image/tiff' || normalized === 'image/tif') {
      return 'image/tiff';
    }
    return '';
  }

  private static createId(): string {
    return 'img_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000000000).toString();
  }

  private static createClipboardTemporaryFileName(mimeType: string): string {
    return 'clipboard_' + Date.now().toString() + '_' +
      Math.floor(Math.random() * 1000000000).toString() + NoteImageStore.extensionForMime(mimeType);
  }

  private static contains(values: string[], target: string): boolean {
    for (let i: number = 0; i < values.length; i++) {
      if (values[i] === target) {
        return true;
      }
    }
    return false;
  }

  private static closeFd(fd: number): void {
    if (fd < 0) {
      return;
    }
    try {
      fileIo.closeSync(fd);
    } catch (error) {
      console.warn('close image file failed: ' + String(error));
    }
  }

  private static deleteIfTemporary(path: string, finalPath: string): void {
    if (path !== finalPath) {
      NoteImageStore.deletePath(path);
    }
  }

  private static deletePath(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      console.warn('delete note image file failed: ' + String(error));
    }
  }
}
