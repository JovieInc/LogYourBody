declare module 'read-excel-file/web' {
  type CellValue = string | number | boolean | Date | null | undefined;

  interface ReadOptions {
    dateFormat?: string;
  }

  export default function readXlsxFile(
    input: Blob | File | ArrayBuffer,
    options?: ReadOptions,
  ): Promise<CellValue[][]>;
}
