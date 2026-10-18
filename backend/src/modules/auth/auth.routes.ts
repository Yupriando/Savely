import { Router } from 'express';
import multer from 'multer';
import type { Session, User } from '@supabase/supabase-js';
import { env } from '../../config/env';
import { errors, jsonBody, ok, security } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { HttpError } from '../../lib/errors';
import { supabaseAnon } from '../../lib/supabase';
import { validate } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

const RegisterBody = z.object({
  email: z.string().email().openapi({ example: 'kamu@email.com' }),
  password: z.string().min(6).openapi({ example: 'rahasia123' }),
  full_name: z.string().min(1).max(100).optional().openapi({ example: 'Budi' }),
});

const LoginBody = z.object({
  email: z.string().email().openapi({ example: 'kamu@email.com' }),
  password: z.string().min(1).openapi({ example: 'rahasia123' }),
});

const RefreshBody = z.object({
  refresh_token: z.string().min(1),
});

const UserSchema = registry.register(
  'User',
  z.object({
    id: z.string().uuid(),
    email: z.string().nullable(),
    full_name: z.string().nullable(),
    avatar_url: z.string().nullable().openapi({ description: 'URL foto profil (publik)' }),
    pending_email: z.string().nullable().openapi({
      description: 'Email baru yang menunggu konfirmasi (kalau konfirmasi email aktif)',
    }),
    created_at: z.string(),
  }),
);

const UpdateProfileBody = z
  .object({
    full_name: z.string().trim().min(1).max(100).optional().openapi({ example: 'Budi Santoso' }),
    email: z.string().trim().email().optional().openapi({ example: 'budi@email.com' }),
  })
  .refine((b) => b.full_name !== undefined || b.email !== undefined, {
    message: 'Isi minimal full_name atau email',
  });

const AvatarBody = z.object({
  avatar: z.any().openapi({ type: 'string', format: 'binary', description: 'JPG/PNG/WEBP, maks 2 MB' }),
});

const AVATAR_BUCKET = 'avatars';
const AVATAR_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (AVATAR_TYPES.includes(file.mimetype)) cb(null, true);
    else cb(new HttpError(400, 'Format foto harus JPG, PNG, atau WEBP'));
  },
});

/**
 * Update data user (email / metadata) lewat Supabase Auth REST API.
 * supabase-js updateUser() butuh session tersimpan, jadi dipanggil langsung dengan token user.
 */
async function updateAuthUser(accessToken: string, body: Record<string, unknown>): Promise<User> {
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    method: 'PUT',
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    const message = (json.msg ?? json.message ?? json.error_description ?? 'Gagal memperbarui profil') as string;
    throw authError({ message, status: res.status }, message);
  }
  return json as unknown as User;
}

function storageError(message: string): HttpError {
  if (/bucket not found/i.test(message)) {
    return new HttpError(500, 'Storage "avatars" belum dibuat. Jalankan migration avatars_storage.sql di Supabase.');
  }
  return new HttpError(400, `Gagal menyimpan foto: ${message}`);
}

const SessionSchema = registry.register(
  'Session',
  z.object({
    access_token: z.string().openapi({ description: 'Pakai di header Authorization: Bearer <token>' }),
    refresh_token: z.string(),
    expires_at: z.number().nullable().openapi({ description: 'Unix timestamp (detik)' }),
  }),
);

const AuthResponse = z.object({
  user: UserSchema,
  session: SessionSchema.nullable().openapi({
    description: 'null kalau email perlu dikonfirmasi dulu sebelum bisa login',
  }),
});

const toUser = (u: User) => ({
  id: u.id,
  email: u.email ?? null,
  full_name: (u.user_metadata?.full_name as string | undefined) ?? null,
  avatar_url: (u.user_metadata?.avatar_url as string | undefined) ?? null,
  pending_email: u.new_email ?? null,
  created_at: u.created_at,
});

/** Terjemahkan error Supabase Auth ke pesan bahasa Indonesia + status yang tepat. */
function authError(error: { message?: string; status?: number } | null, fallback: string, status = 400): HttpError {
  const msg = error?.message ?? '';
  if (error?.status === 429 || /rate limit/i.test(msg)) {
    return new HttpError(429, 'Terlalu banyak percobaan. Tunggu beberapa menit, lalu coba lagi.');
  }
  if (/already registered|already exists/i.test(msg)) return new HttpError(409, 'Email ini sudah terdaftar. Silakan login.');
  if (/signups not allowed|signups are disabled/i.test(msg)) {
    return new HttpError(403, 'Pendaftaran akun sedang dinonaktifkan di Supabase.');
  }
  if (/password should be|weak password/i.test(msg)) return new HttpError(400, 'Password terlalu lemah, minimal 6 karakter.');
  if (/email not confirmed/i.test(msg)) return new HttpError(401, 'Email belum dikonfirmasi. Cek inbox kamu.');
  if (/invalid email|unable to validate email/i.test(msg)) return new HttpError(400, 'Format email tidak valid.');
  return new HttpError(status, fallback);
}

const toSession = (s: Session | null) =>
  s ? { access_token: s.access_token, refresh_token: s.refresh_token, expires_at: s.expires_at ?? null } : null;

export const authRouter = Router();

registry.registerPath({
  method: 'post',
  path: '/auth/register',
  tags: ['Auth'],
  summary: 'Daftar akun baru',
  request: { body: jsonBody(RegisterBody) },
  responses: { 201: ok(AuthResponse, 'Akun dibuat'), 400: errors[400] },
});
authRouter.post('/register', async (req, res) => {
  const body = validate(RegisterBody, req.body);
  const { data, error } = await supabaseAnon.auth.signUp({
    email: body.email,
    password: body.password,
    options: { data: { full_name: body.full_name } },
  });
  if (error || !data.user) throw authError(error, error?.message ?? 'Gagal mendaftar');
  res.status(201).json({ user: toUser(data.user), session: toSession(data.session) });
});

registry.registerPath({
  method: 'post',
  path: '/auth/login',
  tags: ['Auth'],
  summary: 'Login dengan email & password',
  description: 'Salin `session.access_token`, lalu klik tombol **Authorize** di atas untuk mencoba endpoint lain.',
  request: { body: jsonBody(LoginBody) },
  responses: { 200: ok(AuthResponse), 400: errors[400], 401: errors[401] },
});
authRouter.post('/login', async (req, res) => {
  const body = validate(LoginBody, req.body);
  const { data, error } = await supabaseAnon.auth.signInWithPassword(body);
  if (error || !data.user) throw authError(error, 'Email atau password salah', 401);
  res.json({ user: toUser(data.user), session: toSession(data.session) });
});

registry.registerPath({
  method: 'post',
  path: '/auth/refresh',
  tags: ['Auth'],
  summary: 'Perbarui access_token yang sudah kedaluwarsa',
  request: { body: jsonBody(RefreshBody) },
  responses: { 200: ok(AuthResponse), 401: errors[401] },
});
authRouter.post('/refresh', async (req, res) => {
  const body = validate(RefreshBody, req.body);
  const { data, error } = await supabaseAnon.auth.refreshSession({ refresh_token: body.refresh_token });
  if (error || !data.user) throw new HttpError(401, 'Refresh token tidak valid');
  res.json({ user: toUser(data.user), session: toSession(data.session) });
});

registry.registerPath({
  method: 'get',
  path: '/auth/me',
  tags: ['Auth'],
  summary: 'Data user yang sedang login',
  security,
  responses: { 200: ok(UserSchema), 401: errors[401] },
});
authRouter.get('/me', requireAuth, (req, res) => {
  res.json(toUser(req.user));
});

registry.registerPath({
  method: 'patch',
  path: '/auth/me',
  tags: ['Auth'],
  summary: 'Ubah nama dan/atau email',
  description:
    'Kalau konfirmasi email aktif di Supabase, email baru masuk ke `pending_email` sampai dikonfirmasi lewat link di email.',
  security,
  request: { body: jsonBody(UpdateProfileBody) },
  responses: { 200: ok(UserSchema), 400: errors[400], 401: errors[401] },
});
authRouter.patch('/me', requireAuth, async (req, res) => {
  const body = validate(UpdateProfileBody, req.body);
  const changes: Record<string, unknown> = {};
  if (body.full_name !== undefined) changes.data = { full_name: body.full_name };
  if (body.email !== undefined && body.email.toLowerCase() !== req.user.email?.toLowerCase()) {
    changes.email = body.email;
  }
  const user = Object.keys(changes).length ? await updateAuthUser(req.accessToken, changes) : req.user;
  res.json(toUser(user));
});

registry.registerPath({
  method: 'post',
  path: '/auth/me/avatar',
  tags: ['Auth'],
  summary: 'Upload / ganti foto profil',
  security,
  request: { body: { content: { 'multipart/form-data': { schema: AvatarBody } } } },
  responses: { 200: ok(UserSchema), 400: errors[400], 401: errors[401] },
});
authRouter.post('/me/avatar', requireAuth, upload.single('avatar'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'Kirim file foto di field "avatar"');

  const path = `${req.user.id}/avatar`;
  const bucket = req.db.storage.from(AVATAR_BUCKET);
  const { error } = await bucket.upload(path, req.file.buffer, {
    contentType: req.file.mimetype,
    upsert: true,
    cacheControl: '3600',
  });
  if (error) throw storageError(error.message);

  // ?v=... supaya app tidak memakai foto lama dari cache
  const url = `${bucket.getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
  const user = await updateAuthUser(req.accessToken, { data: { avatar_url: url } });
  res.json(toUser(user));
});

registry.registerPath({
  method: 'delete',
  path: '/auth/me/avatar',
  tags: ['Auth'],
  summary: 'Hapus foto profil',
  security,
  responses: { 200: ok(UserSchema), 401: errors[401] },
});
authRouter.delete('/me/avatar', requireAuth, async (req, res) => {
  const { error } = await req.db.storage.from(AVATAR_BUCKET).remove([`${req.user.id}/avatar`]);
  if (error) throw storageError(error.message);
  const user = await updateAuthUser(req.accessToken, { data: { avatar_url: null } });
  res.json(toUser(user));
});
