import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env } from '../config/env';

const clientOptions = {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
};

/** Client tanpa user, dipakai untuk login/daftar dan verifikasi token. */
export const supabaseAnon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, clientOptions);

/**
 * Client atas nama user yang login. Semua query lewat client ini
 * tunduk pada Row Level Security, jadi user hanya bisa akses datanya sendiri.
 */
export function createUserClient(accessToken: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    ...clientOptions,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}
