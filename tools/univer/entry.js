import { createUniver, generateRandomId, LocaleType, mergeLocales } from '@univerjs/presets';
import { UniverSheetsConditionalFormattingPreset } from '@univerjs/preset-sheets-conditional-formatting';
import sheetsConditionalFormattingZhCN from '@univerjs/preset-sheets-conditional-formatting/locales/zh-CN';
import sheetsConditionalFormattingEnUS from '@univerjs/preset-sheets-conditional-formatting/locales/en-US';
import { UniverSheetsCorePreset } from '@univerjs/preset-sheets-core';
import sheetsCoreZhCN from '@univerjs/preset-sheets-core/locales/zh-CN';
import sheetsCoreEnUS from '@univerjs/preset-sheets-core/locales/en-US';
import { UniverSheetsDataValidationPreset } from '@univerjs/preset-sheets-data-validation';
import sheetsDataValidationZhCN from '@univerjs/preset-sheets-data-validation/locales/zh-CN';
import sheetsDataValidationEnUS from '@univerjs/preset-sheets-data-validation/locales/en-US';
import {
  IImageIoService,
  ImageIoService,
  ImageSourceType,
  ImageUploadStatusType,
  UniverSheetsDrawingPreset,
} from '@univerjs/preset-sheets-drawing';
import sheetsDrawingZhCN from '@univerjs/preset-sheets-drawing/locales/zh-CN';
import sheetsDrawingEnUS from '@univerjs/preset-sheets-drawing/locales/en-US';
import { UniverSheetsFilterPreset } from '@univerjs/preset-sheets-filter';
import sheetsFilterZhCN from '@univerjs/preset-sheets-filter/locales/zh-CN';
import sheetsFilterEnUS from '@univerjs/preset-sheets-filter/locales/en-US';
import { UniverSheetsFindReplacePreset } from '@univerjs/preset-sheets-find-replace';
import sheetsFindReplaceZhCN from '@univerjs/preset-sheets-find-replace/locales/zh-CN';
import sheetsFindReplaceEnUS from '@univerjs/preset-sheets-find-replace/locales/en-US';
import { UniverSheetsHyperLinkPreset } from '@univerjs/preset-sheets-hyper-link';
import sheetsHyperLinkZhCN from '@univerjs/preset-sheets-hyper-link/locales/zh-CN';
import sheetsHyperLinkEnUS from '@univerjs/preset-sheets-hyper-link/locales/en-US';
import { UniverSheetsNotePreset } from '@univerjs/preset-sheets-note';
import sheetsNoteZhCN from '@univerjs/preset-sheets-note/locales/zh-CN';
import sheetsNoteEnUS from '@univerjs/preset-sheets-note/locales/en-US';
import { UniverSheetsSortPreset } from '@univerjs/preset-sheets-sort';
import sheetsSortZhCN from '@univerjs/preset-sheets-sort/locales/zh-CN';
import sheetsSortEnUS from '@univerjs/preset-sheets-sort/locales/en-US';
import { UniverSheetsTablePreset } from '@univerjs/preset-sheets-table';
import sheetsTableZhCN from '@univerjs/preset-sheets-table/locales/zh-CN';
import sheetsTableEnUS from '@univerjs/preset-sheets-table/locales/en-US';
import '@univerjs/preset-sheets-conditional-formatting/lib/index.css';
import '@univerjs/preset-sheets-core/lib/index.css';
import '@univerjs/preset-sheets-data-validation/lib/index.css';
import '@univerjs/preset-sheets-drawing/lib/index.css';
import '@univerjs/preset-sheets-filter/lib/index.css';
import '@univerjs/preset-sheets-find-replace/lib/index.css';
import '@univerjs/preset-sheets-hyper-link/lib/index.css';
import '@univerjs/preset-sheets-note/lib/index.css';
import '@univerjs/preset-sheets-sort/lib/index.css';
import '@univerjs/preset-sheets-table/lib/index.css';

const ALLOWED_IMAGE_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/gif',
  'image/bmp',
  'image/webp',
  'image/svg+xml',
]);
const MAX_IMAGE_SIZE = 5 * 1024 * 1024;

function readFileAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (event) => {
      const value = event.target?.result;
      if (typeof value === 'string' && value) resolve(value);
      else reject(new Error(ImageUploadStatusType.ERROR_IMAGE));
    };
    reader.onerror = () => reject(new Error(ImageUploadStatusType.ERROR_IMAGE));
    reader.readAsDataURL(file);
  });
}

class BookStarkImageIoService extends ImageIoService {
  async saveImage(imageFile) {
    try {
      if (!ALLOWED_IMAGE_TYPES.has(imageFile.type)) {
        throw new Error(ImageUploadStatusType.ERROR_IMAGE_TYPE);
      }
      if (imageFile.size > MAX_IMAGE_SIZE) {
        throw new Error(ImageUploadStatusType.ERROR_EXCEED_SIZE);
      }
      if (typeof window.BookStarkUniverUploadImage !== 'function') {
        throw new Error(ImageUploadStatusType.ERROR_IMAGE);
      }

      const base64Cache = await readFileAsDataURL(imageFile);
      const uploaded = await window.BookStarkUniverUploadImage(imageFile);
      if (!uploaded?.url) throw new Error(ImageUploadStatusType.ERROR_IMAGE);

      return {
        imageId: generateRandomId(8),
        imageSourceType: ImageSourceType.URL,
        source: uploaded.url,
        base64Cache,
        status: ImageUploadStatusType.SUCCUSS,
      };
    } catch (error) {
      const knownStatus = Object.values(ImageUploadStatusType).includes(error?.message);
      throw new Error(knownStatus ? error.message : ImageUploadStatusType.ERROR_IMAGE);
    } finally {
      this._decreaseWaiting();
    }
  }
}

function BookStarkSheetsDrawingPreset(options = {}) {
  const preset = UniverSheetsDrawingPreset(options);
  const drawingPlugin = preset.plugins.find((plugin) => Array.isArray(plugin) && plugin[1]?.override);
  if (drawingPlugin) {
    drawingPlugin[1].override = [
      [IImageIoService, { useClass: BookStarkImageIoService }],
    ];
  }
  return preset;
}

window.UniverBookStark = {
  createUniver,
  LocaleType,
  mergeLocales,
  UniverSheetsConditionalFormattingPreset,
  UniverSheetsCorePreset,
  UniverSheetsDataValidationPreset,
  UniverSheetsDrawingPreset,
  UniverSheetsFilterPreset,
  UniverSheetsFindReplacePreset,
  UniverSheetsHyperLinkPreset,
  UniverSheetsNotePreset,
  UniverSheetsSortPreset,
  UniverSheetsTablePreset,
  BookStarkSheetsDrawingPreset,
  IImageIoService,
  BookStarkImageIoService,
  sheetsConditionalFormattingZhCN,
  sheetsConditionalFormattingEnUS,
  sheetsCoreZhCN,
  sheetsCoreEnUS,
  sheetsDataValidationZhCN,
  sheetsDataValidationEnUS,
  sheetsDrawingZhCN,
  sheetsDrawingEnUS,
  sheetsFilterZhCN,
  sheetsFilterEnUS,
  sheetsFindReplaceZhCN,
  sheetsFindReplaceEnUS,
  sheetsHyperLinkZhCN,
  sheetsHyperLinkEnUS,
  sheetsNoteZhCN,
  sheetsNoteEnUS,
  sheetsSortZhCN,
  sheetsSortEnUS,
  sheetsTableZhCN,
  sheetsTableEnUS,
};
