import type { PostgrestError } from '@supabase/supabase-js';
import type { ZodError } from 'zod';

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
  }
}

export const notFound = (what: string) => new HttpError(404, `${what} tidak ditemukan`);

export function fromZodError(error: ZodError): HttpError {
  return new HttpError(
    400,
    'Input tidak valid',
    error.issues.map((i) => ({ field: i.path.join('.'), message: i.message })),
  );
}

/** Ubah error Postgres/PostgREST jadi HttpError yang mudah dipahami client. */
export function fromPostgrestError(error: PostgrestError, notFoundLabel = 'Data'): HttpError {
  switch (error.code) {
    case 'PGRST116': // .single() tidak menemukan baris
      return notFound(notFoundLabel);
    case '23505':
      return new HttpError(409, 'Data dengan nama tersebut sudah ada');
    case '23503':
      // "update or delete on table ..." = data masih direferensikan tabel lain.
      // "insert or update on table ..." = referensi (kategori/wishlist) tidak cocok.
      return error.message.startsWith('update or delete')
        ? new HttpError(409, 'Data masih dipakai oleh data lain, tidak bisa dihapus')
        : new HttpError(400, 'Referensi tidak valid (cek kategori dan tipe transaksi)');
    case '23514':
      return new HttpError(400, 'Nilai tidak memenuhi aturan validasi');
    case '22P02':
      return new HttpError(400, 'Format ID atau nilai tidak valid');
    default:
      return new HttpError(500, 'Terjadi kesalahan pada database', error.message);
  }
}

/** Ambil `data` dari hasil query Supabase, lempar HttpError kalau gagal. */
export function unwrap<T>(
  result: { data: T | null; error: PostgrestError | null },
  notFoundLabel = 'Data',
): NonNullable<T> {
  if (result.error) throw fromPostgrestError(result.error, notFoundLabel);
  if (result.data === null || result.data === undefined) throw notFound(notFoundLabel);
  return result.data as NonNullable<T>;
}
