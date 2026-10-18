import type { RequestHandler } from 'express';
import type { SupabaseClient, User } from '@supabase/supabase-js';
import { HttpError } from '../lib/errors';
import { createUserClient, supabaseAnon } from '../lib/supabase';

declare global {
  namespace Express {
    interface Request {
      user: User;
      /** Supabase client atas nama user yang login (RLS aktif). */
      db: SupabaseClient;
      /** Access token mentah dari header Authorization. */
      accessToken: string;
    }
  }
}

/** Wajibkan header `Authorization: Bearer <access_token>` dari Supabase Auth. */
export const requireAuth: RequestHandler = async (req, _res, next) => {
  const header = req.headers.authorization;
  const token = header?.startsWith('Bearer ') ? header.slice(7).trim() : null;
  if (!token) throw new HttpError(401, 'Token tidak ada. Kirim header Authorization: Bearer <token>');

  const { data, error } = await supabaseAnon.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'Token tidak valid atau sudah kedaluwarsa');

  req.user = data.user;
  req.db = createUserClient(token);
  req.accessToken = token;
  next();
};
