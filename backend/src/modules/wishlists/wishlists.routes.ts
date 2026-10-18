import { Router } from 'express';
import type { SupabaseClient } from '@supabase/supabase-js';
import { dateString, errors, IdParams, jsonBody, ok, rupiah, security } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { daysBetween, today } from '../../lib/dates';
import { HttpError, unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';

const wishlistStatus = z.enum(['active', 'achieved', 'cancelled']).openapi({
  description: 'active = sedang menabung, achieved = tercapai, cancelled = batal',
});

const SavingPlan = z
  .object({
    days_left: z.number().int().openapi({ description: 'Sisa hari menuju target_date (negatif = lewat)' }),
    is_overdue: z.boolean(),
    per_day: rupiah.openapi({ description: 'Harus ditabung per hari agar tepat waktu' }),
    per_week: rupiah,
    per_month: rupiah,
  })
  .openapi('SavingPlan');

const WishlistSchema = registry.register(
  'Wishlist',
  z.object({
    id: z.string().uuid(),
    name: z.string().openapi({ example: 'HP baru' }),
    target_amount: rupiah.openapi({ example: 3000000 }),
    target_date: dateString,
    note: z.string().nullable(),
    image_url: z.string().nullable(),
    status: wishlistStatus,
    achieved_at: z.string().nullable(),
    created_at: z.string(),
    saved_amount: rupiah,
    remaining_amount: rupiah,
    progress_percent: z.number().openapi({ example: 42.5 }),
    saving_plan: SavingPlan,
  }),
);

const SavingSchema = registry.register(
  'WishlistSaving',
  z.object({
    id: z.string().uuid(),
    wishlist_id: z.string().uuid(),
    amount: rupiah.openapi({ description: 'Positif = setor, negatif = tarik' }),
    saving_date: dateString,
    note: z.string().nullable(),
    created_at: z.string(),
  }),
);

const WishlistDetail = WishlistSchema.extend({ savings: z.array(SavingSchema) }).openapi('WishlistDetail');

const ListQuery = z.object({ status: wishlistStatus.optional() });

const CreateBody = z.object({
  name: z.string().trim().min(1).max(100).openapi({ example: 'HP baru' }),
  target_amount: rupiah.positive().openapi({ example: 3000000 }),
  target_date: dateString.openapi({ example: '2026-12-31' }),
  note: z.string().max(255).nullable().optional(),
  image_url: z.string().url().nullable().optional(),
});

const UpdateBody = CreateBody.partial().extend({ status: wishlistStatus.optional() });

const SavingBody = z.object({
  amount: rupiah
    .refine((n) => n !== 0, 'Nominal tidak boleh 0')
    .openapi({ example: 50000, description: 'Positif = setor, negatif = tarik kembali' }),
  saving_date: dateString.optional().openapi({ description: 'Default: hari ini' }),
  note: z.string().max(255).nullable().optional(),
});

const UpdateSavingBody = SavingBody.partial().refine((b) => Object.keys(b).length > 0, {
  message: 'Isi minimal satu field yang mau diubah',
});

const SavingParams = IdParams.extend({
  savingId: z.string().uuid().openapi({ param: { name: 'savingId', in: 'path' } }),
});

const PROGRESS_COLUMNS =
  'id, name, target_amount, target_date, note, image_url, status, achieved_at, created_at, saved_amount, remaining_amount, progress_percent';
const SAVING_COLUMNS = 'id, wishlist_id, amount, saving_date, note, created_at';

type ProgressRow = {
  target_date: string;
  remaining_amount: number;
  progress_percent: number | string;
  [key: string]: unknown;
};

/** Hitung berapa yang harus ditabung per hari/minggu/bulan agar target tercapai tepat waktu. */
function buildSavingPlan(targetDate: string, remaining: number) {
  const daysLeft = daysBetween(today(), targetDate);
  const isOverdue = daysLeft < 0 && remaining > 0;

  if (remaining <= 0) return { days_left: daysLeft, is_overdue: false, per_day: 0, per_week: 0, per_month: 0 };
  if (daysLeft <= 0) {
    // Hari ini adalah target atau sudah lewat: sisa harus dipenuhi sekarang
    return { days_left: daysLeft, is_overdue: isOverdue, per_day: remaining, per_week: remaining, per_month: remaining };
  }

  return {
    days_left: daysLeft,
    is_overdue: false,
    per_day: Math.ceil(remaining / daysLeft),
    per_week: Math.ceil(remaining / Math.ceil(daysLeft / 7)),
    per_month: Math.ceil(remaining / Math.ceil(daysLeft / 30)),
  };
}

function withPlan(row: ProgressRow) {
  return {
    ...row,
    progress_percent: Number(row.progress_percent),
    saving_plan: buildSavingPlan(row.target_date, row.remaining_amount),
  };
}

async function getProgress(db: SupabaseClient, id: string) {
  return unwrap(
    await db.from('wishlist_progress').select(PROGRESS_COLUMNS).eq('id', id).single<ProgressRow>(),
    'Wishlist',
  );
}

/** Wishlist + progres + riwayat tabungan. */
async function getDetail(db: SupabaseClient, id: string) {
  const row = await getProgress(db, id);
  const savings = unwrap(
    await db
      .from('wishlist_savings')
      .select(SAVING_COLUMNS)
      .eq('wishlist_id', id)
      .order('saving_date', { ascending: false })
      .order('created_at', { ascending: false }),
  );
  return { ...withPlan(row), savings };
}

async function getSaving(db: SupabaseClient, wishlistId: string, savingId: string) {
  return unwrap(
    await db
      .from('wishlist_savings')
      .select('id, amount')
      .eq('id', savingId)
      .eq('wishlist_id', wishlistId)
      .single<{ id: string; amount: number }>(),
    'Catatan tabungan',
  );
}

/** Tolak perubahan yang membuat total tabungan wishlist jadi minus. */
async function ensureNotNegative(db: SupabaseClient, wishlistId: string, delta: number) {
  const saved = Number((await getProgress(db, wishlistId)).saved_amount);
  if (saved + delta < 0) {
    throw new HttpError(
      400,
      `Total tabungan jadi minus (Rp${saved + delta}). Ubah/hapus catatan penarikan dulu.`,
    );
  }
}

/** Setelah setor/tarik: tandai tercapai kalau sudah penuh, atau aktifkan lagi kalau berkurang. */
async function syncStatus(db: SupabaseClient, id: string) {
  const row = await getProgress(db, id);
  const isFull = row.remaining_amount <= 0;

  if (isFull && row.status === 'active') {
    unwrap(await db.from('wishlists').update({ status: 'achieved', achieved_at: new Date().toISOString() }).eq('id', id).select('id').single());
  } else if (!isFull && row.status === 'achieved') {
    unwrap(await db.from('wishlists').update({ status: 'active', achieved_at: null }).eq('id', id).select('id').single());
  }
}

export const wishlistsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/wishlists',
  tags: ['Wishlists'],
  summary: 'Daftar wishlist beserta progres & rencana tabungan',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(z.array(WishlistSchema)), 401: errors[401] },
});
wishlistsRouter.get('/', async (req, res) => {
  const query = validate(ListQuery, req.query);
  let q = req.db
    .from('wishlist_progress')
    .select(PROGRESS_COLUMNS)
    .order('status')
    .order('target_date');
  if (query.status) q = q.eq('status', query.status);
  const rows = unwrap(await q.returns<ProgressRow[]>());
  res.json(rows.map(withPlan));
});

registry.registerPath({
  method: 'get',
  path: '/wishlists/{id}',
  tags: ['Wishlists'],
  summary: 'Detail wishlist + riwayat tabungan',
  security,
  request: { params: IdParams },
  responses: { 200: ok(WishlistDetail), 404: errors[404] },
});
wishlistsRouter.get('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  res.json(await getDetail(req.db, id));
});

registry.registerPath({
  method: 'post',
  path: '/wishlists',
  tags: ['Wishlists'],
  summary: 'Buat wishlist baru',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(WishlistSchema, 'Wishlist dibuat'), 400: errors[400] },
});
wishlistsRouter.post('/', async (req, res) => {
  const body = validate(CreateBody, req.body);
  if (body.target_date < today()) throw new HttpError(400, 'target_date tidak boleh di masa lalu');

  const created = unwrap(
    await req.db.from('wishlists').insert({ ...body, user_id: req.user.id }).select('id').single<{ id: string }>(),
  );
  res.status(201).json(withPlan(await getProgress(req.db, created.id)));
});

registry.registerPath({
  method: 'patch',
  path: '/wishlists/{id}',
  tags: ['Wishlists'],
  summary: 'Ubah wishlist (termasuk status)',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(WishlistSchema), 400: errors[400], 404: errors[404] },
});
wishlistsRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(UpdateBody, req.body);

  const changes: Record<string, unknown> = { ...body };
  if (body.status === 'achieved') changes.achieved_at = new Date().toISOString();
  else if (body.status) changes.achieved_at = null;

  unwrap(await req.db.from('wishlists').update(changes).eq('id', id).select('id').single(), 'Wishlist');
  res.json(withPlan(await getProgress(req.db, id)));
});

registry.registerPath({
  method: 'delete',
  path: '/wishlists/{id}',
  tags: ['Wishlists'],
  summary: 'Hapus wishlist (riwayat tabungannya ikut terhapus)',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
wishlistsRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('wishlists').delete().eq('id', id).select('id').single(), 'Wishlist');
  res.status(204).end();
});

registry.registerPath({
  method: 'post',
  path: '/wishlists/{id}/savings',
  tags: ['Wishlists'],
  summary: 'Setor / tarik tabungan wishlist',
  description:
    'Amount positif = setor, negatif = tarik. Status otomatis jadi `achieved` saat target terpenuhi.',
  security,
  request: { params: IdParams, body: jsonBody(SavingBody) },
  responses: { 201: ok(WishlistDetail, 'Tabungan dicatat'), 400: errors[400], 404: errors[404] },
});
wishlistsRouter.post('/:id/savings', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(SavingBody, req.body);

  const current = await getProgress(req.db, id);
  const saved = Number(current.saved_amount);
  if (body.amount < 0 && -body.amount > saved) {
    throw new HttpError(400, `Tidak bisa menarik lebih dari saldo tabungan (Rp${saved})`);
  }

  unwrap(
    await req.db
      .from('wishlist_savings')
      .insert({ ...body, saving_date: body.saving_date ?? today(), wishlist_id: id, user_id: req.user.id })
      .select('id')
      .single(),
  );
  await syncStatus(req.db, id);
  res.status(201).json(await getDetail(req.db, id));
});

registry.registerPath({
  method: 'patch',
  path: '/wishlists/{id}/savings/{savingId}',
  tags: ['Wishlists'],
  summary: 'Ubah satu catatan tabungan (nominal, tanggal, catatan)',
  description: 'Ditolak kalau perubahan membuat total tabungan jadi minus.',
  security,
  request: { params: SavingParams, body: jsonBody(UpdateSavingBody) },
  responses: { 200: ok(WishlistDetail), 400: errors[400], 404: errors[404] },
});
wishlistsRouter.patch('/:id/savings/:savingId', async (req, res) => {
  const { id, savingId } = validate(SavingParams, req.params);
  const body = validate(UpdateSavingBody, req.body);

  if (body.amount !== undefined) {
    const old = await getSaving(req.db, id, savingId);
    await ensureNotNegative(req.db, id, body.amount - old.amount);
  }

  unwrap(
    await req.db
      .from('wishlist_savings')
      .update(body)
      .eq('id', savingId)
      .eq('wishlist_id', id)
      .select('id')
      .single(),
    'Catatan tabungan',
  );
  await syncStatus(req.db, id);
  res.json(await getDetail(req.db, id));
});

registry.registerPath({
  method: 'delete',
  path: '/wishlists/{id}/savings/{savingId}',
  tags: ['Wishlists'],
  summary: 'Hapus satu catatan tabungan',
  security,
  request: { params: SavingParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
wishlistsRouter.delete('/:id/savings/:savingId', async (req, res) => {
  const { id, savingId } = validate(SavingParams, req.params);
  const old = await getSaving(req.db, id, savingId);
  await ensureNotNegative(req.db, id, -old.amount);
  unwrap(
    await req.db
      .from('wishlist_savings')
      .delete()
      .eq('id', savingId)
      .eq('wishlist_id', id)
      .select('id')
      .single(),
    'Catatan tabungan',
  );
  await syncStatus(req.db, id);
  res.status(204).end();
});
