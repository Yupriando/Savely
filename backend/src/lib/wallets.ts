import type { SupabaseClient } from '@supabase/supabase-js';
import { HttpError, unwrap } from './errors';

/** Id dompet utama user. Dipakai kalau request tidak menyebut dompet. */
export async function getDefaultWalletId(db: SupabaseClient): Promise<string> {
  const result = await db
    .from('wallets')
    .select('id')
    .eq('is_default', true)
    .maybeSingle<{ id: string }>();
  if (result.error) throw new HttpError(500, 'Gagal membaca dompet', result.error.message);
  if (result.data) return result.data.id;

  // Tidak ada dompet utama (mis. dihapus): pakai dompet aktif pertama
  const first = unwrap(
    await db
      .from('wallets')
      .select('id')
      .eq('archived', false)
      .order('created_at')
      .limit(1)
      .returns<{ id: string }[]>(),
  );
  if (!first.length) throw new HttpError(400, 'Buat dompet dulu sebelum mencatat transaksi');
  return first[0].id;
}
