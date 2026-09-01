import { describe, expect, it } from '@ohos/hypium';
import { NOTE_IMAGE_TOTAL_MAX_BYTES, NoteImageAsset } from '../main/ets/common/Models';
import { NoteImageStore } from '../main/ets/common/NoteImageStore';

const DAY_MS: number = 24 * 60 * 60 * 1000;

export default function noteImageStoreTest(): void {
  describe('NoteImageStoreTest', () => {
    it('recognizesOnlyStrictManagedAssetNames', 0, () => {
      const valid: string[] = [
        'img_1725148800000_0.png',
        'img_1725148800000_1.jpg',
        'img_1725148800000_2.webp',
        'img_1725148800000_3.gif',
        'img_1725148800000_4.bmp',
        'img_1725148800000_5.tiff'
      ];
      for (let i: number = 0; i < valid.length; i++) {
        expect(NoteImageStore.isManagedFileName(valid[i])).assertTrue();
      }

      const invalid: string[] = [
        '',
        'img_1725148800000.png',
        'img_time_1.png',
        'img_1725148800000_random.png',
        'img_1725148800000_1.jpeg',
        'img_1725148800000_1.PNG',
        'img_1725148800000_1.png.bak',
        'img_1725148800000_1.importing',
        'clipboard_1725148800000.png',
        '../img_1725148800000_1.png',
        'nested/img_1725148800000_1.png'
      ];
      for (let i: number = 0; i < invalid.length; i++) {
        expect(NoteImageStore.isManagedFileName(invalid[i])).assertFalse();
      }
    });

    it('recognizesOnlyOwnedCrashTemporaryNames', 0, () => {
      const valid: string[] = [
        'img_1725148800000_1.importing',
        'img_1725148800000_1.encoding',
        'clipboard_1725148800000.png',
        'clipboard_1725148800000.jpg',
        'clipboard_1725148800000_42.png',
        'clipboard_1725148800000_42.jpg'
      ];
      for (let i: number = 0; i < valid.length; i++) {
        expect(NoteImageStore.isTemporaryFileName(valid[i])).assertTrue();
        expect(NoteImageStore.isManagedFileName(valid[i])).assertFalse();
      }

      const invalid: string[] = [
        'unrelated.importing',
        'unrelated.encoding',
        'photo.clipboard_1725148800000.png',
        'clipboard_1725148800000.webp',
        'clipboard_1725148800000.png.bak',
        'clipboard_time.png',
        'img_1725148800000_1.jpg.importing',
        '../clipboard_1725148800000.png'
      ];
      for (let i: number = 0; i < invalid.length; i++) {
        expect(NoteImageStore.isTemporaryFileName(invalid[i])).assertFalse();
      }
    });

    it('keepsProtectedAndYoungAssetsButAlwaysCleansOwnedTemps', 0, () => {
      const now: number = 2000000000000;
      const orphan: string = 'img_1725148800000_7.png';
      const protectedNames: string[] = [orphan];

      expect(NoteImageStore.shouldCleanupEntry(orphan, protectedNames, now - DAY_MS * 2, now)).assertFalse();
      expect(NoteImageStore.shouldCleanupEntry(orphan, [], now - DAY_MS + 1, now)).assertFalse();
      expect(NoteImageStore.shouldCleanupEntry(orphan, [], now - DAY_MS, now)).assertTrue();
      expect(NoteImageStore.shouldCleanupEntry(orphan, [], now + 1, now)).assertFalse();
      expect(NoteImageStore.shouldCleanupEntry('notes.importing', [], now - DAY_MS * 2, now)).assertFalse();
      expect(NoteImageStore.shouldCleanupEntry(
        'clipboard_1725148800000.png', [], now + DAY_MS, now)).assertTrue();
    });

    it('requiresMatchingAssetIdentityAndOwnerBeforeDeletion', 0, () => {
      const valid: NoteImageAsset = {
        id: 'img_1725148800000_9',
        noteId: 'note-a',
        fileName: 'img_1725148800000_9.jpg',
        mimeType: 'image/jpeg',
        width: 100,
        height: 80,
        byteLength: 1024,
        createdAt: 1725148800000
      };
      const mismatchedFile: NoteImageAsset = {
        id: 'img_1725148800000_8',
        noteId: 'note-a',
        fileName: 'img_1725148800000_9.jpg',
        mimeType: 'image/jpeg',
        width: 100,
        height: 80,
        byteLength: 1024,
        createdAt: 1725148800000
      };
      const mismatchedMime: NoteImageAsset = {
        id: 'img_1725148800000_9',
        noteId: 'note-a',
        fileName: 'img_1725148800000_9.jpg',
        mimeType: 'image/png',
        width: 100,
        height: 80,
        byteLength: 1024,
        createdAt: 1725148800000
      };

      expect(NoteImageStore.isManagedAssetIdentity(valid)).assertTrue();
      expect(NoteImageStore.isOwnedManagedAsset(valid, 'note-a')).assertTrue();
      expect(NoteImageStore.isOwnedManagedAsset(valid, 'note-b')).assertFalse();
      expect(NoteImageStore.isOwnedManagedAsset(valid, '')).assertFalse();
      expect(NoteImageStore.isManagedAssetIdentity(mismatchedFile)).assertFalse();
      expect(NoteImageStore.isManagedAssetIdentity(mismatchedMime)).assertFalse();
    });

    it('checksQuotaWithoutNaNOrOverflowBypass', 0, () => {
      expect(NoteImageStore.canReserveBytes(0, 1)).assertTrue();
      expect(NoteImageStore.canReserveBytes(NOTE_IMAGE_TOTAL_MAX_BYTES - 1, 1)).assertTrue();
      expect(NoteImageStore.canReserveBytes(NOTE_IMAGE_TOTAL_MAX_BYTES, 1)).assertFalse();
      expect(NoteImageStore.canReserveBytes(NOTE_IMAGE_TOTAL_MAX_BYTES + 1, 1)).assertFalse();
      expect(NoteImageStore.canReserveBytes(-1, 1)).assertFalse();
      expect(NoteImageStore.canReserveBytes(0, 0)).assertFalse();
      expect(NoteImageStore.canReserveBytes(Number.NaN, 1)).assertFalse();
      expect(NoteImageStore.canReserveBytes(0, Number.POSITIVE_INFINITY)).assertFalse();
    });
  });
}
