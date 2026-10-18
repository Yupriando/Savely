import { Router } from 'express';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  dateString,
  errors,
  IdParams,
  jsonBody,
  monthString,
  ok,
  rupiah,
  security,
  transactionType,
} from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { daysBetween, monthRange, today } from '../../lib/dates';
import { HttpError, unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';
import { getDefaultWalletId } from '../../lib/wallets';

const billStatus = z.enum(['paid', 'overdue', 'due_soon', 'upcoming', 'inactive']).openapi({
  description:
    'paid = sudah dibayar bulan ini, overdue = lewat jatuh tempo, due_soon = jatuh tempo dalam remind_days hari, upcoming = belum dekat, inactive = dinonaktifkan',
});

const Ref = z.object({ id: z.string(), name: z.string(), icon: z.string(), color: z.string() });

const BillSchema = registry.register(
  'Bill',
  z.object({
    id: z.string().uuid(),
    name: z.string().openapi({ example: 'IPL Apartemen' }),
    type: transactionType,
    category_id: z.string().uuid(),
    wallet_id: z.string().uuid().nullable(),
    amount: rupiah.openapi({ example: 750000 }),
    due_day: z.number().int().openapi({ example: 10, description: 'Tanggal jatuh tempo tiap bulan (1–31)' }),
    remind_days: z.number().int().openapi({ example: 3, description: 'Ingatkan berapa hari sebelumnya' }),
    note: z.string().nullable(),
    is_active: z.boolean(),
    category: Ref,
    wallet: Ref.nullable(),
    due_date: dateString.openapi({ description: 'Tanggal jatuh tempo di bulan yang diminta' }),
    days_until_due: z.number().int().openapi({ description: 'Negatif = sudah lewat' }),
    status: billStatus,
    payment: z
      .object({ transaction_id: z.string().uuid(), amount: rupiah, date: dateString })
      .nullable()
      .openapi({ description: 'Pembayaran di bulan ini (kalau sudah dibayar)' }),
  }),
);

const BillsResponse = z.object({
  month: monthString,
  total_due: rupiah.openapi({ description: 'Total tagihan pengeluaran yang belum dibayar' }),
  items: z.array(BillSchema),
});

const ListQuery = z.object({ month: monthString.optional().openapi({ description: 'Default: bulan ini' }) });

const CreateBody = z.object({
  name: z.string().trim().min(1).max(60).openapi({ example: 'IPL Apartemen' }),
  type: transactionType.default('expense'),
  category_id: z.string().uuid(),
  wallet_id: z.string().uuid().nullable().optional().openapi({ description: 'Dompet default untuk bayar' }),
  amount: rupiah.positive().openapi({ example: 750000 }),
  due_day: z.number().int().min(1).max(31).openapi({ example: 10 }),
  remind_days: z.number().int().min(0).max(14).default(3),
  note: z.string().max(255).nullable().optional(),
  is_active: z.boolean().optional(),
});

const UpdateBody = CreateBody.partial().refine(
  (b) => b.type === undefined || b.category_id !== undefined,
  { message: 'Kalau mengubah type, category_id juga harus dikirim', path: ['category_id'] },
);

const PayBody = z.object({
  month: monthString.optional().openapi({ description: 'Bulan yang dibayar. Default: bulan ini' }),
  amount: rupiah.positive().optional().openapi({ description: 'Default: nominal tagihan' }),
  wallet_id: z.string().uuid().optional().openapi({ description: 'Default: dompet tagihan / dompet utama' }),
  date: dateString.optional().openapi({ description: 'Tanggal bayar. Default: hari ini' }),
  note: z.string().max(255).nullable().optional(),
});

const UnpayQuery = z.object({ month: monthString.optional() });

const COLUMNS =
  'id, name, type, category_id, wallet_id, amount, due_day, remind_days, note, is_active, ' +
  'category:categories(id, name, icon, color), wallet:wallets(id, name, icon, color)';

type BillRow = {
  id: string;
  type: 'income' | 'expense';
  amount: number;
  due_day: number;
  remind_days: number;
  is_active: boolean;
};

async function getBillsForMonth(db: SupabaseClient, month: string, onlyId?: string) {
  let q = db.from('bills').select(COLUMNS).order('due_day').order('name');
  if (onlyId) q = q.eq('id', onlyId);
  const bills = unwrap(await q.returns<BillRow[]>());

  const monthStart = monthRange(month).start;
  const payments = bills.length
    ? unwrap(
        await db
          .from('transactions')
          .select('id, bill_id, amount, transaction_date')
          .eq('bill_month', monthStart)
          .in(
            'bill_id',
            bills.map((b) => b.id),
          )
          .returns<{ id: string; bill_id: string; amount: number; transaction_date: string }[]>(),
      )
    : [];
  const paidBy = new Map(payments.map((p) => [p.bill_id, p]));

  const { end } = monthRange(month);
  const lastDay = Number(end.slice(8, 10));
  const now = today();

  const items = bills
    .map((b) => {
      const dueDate = `${month}-${String(Math.min(b.due_day, lastDay)).padStart(2, '0')}`;
      const days = daysBetween(now, dueDate);
      const paid = paidBy.get(b.id);
      const status = paid
        ? 'paid'
        : !b.is_active
          ? 'inactive'
          : days < 0
            ? 'overdue'
            : days <= b.remind_days
              ? 'due_soon'
              : 'upcoming';
      return {
        ...b,
        due_date: dueDate,
        days_until_due: days,
        status,
        payment: paid ? { transaction_id: paid.id, amount: paid.amount, date: paid.transaction_date } : null,
      };
    })
    // Yang mendesak di atas: lewat > segera > nanti > lunas > nonaktif
    .sort((a, b) => rank(a.status) - rank(b.status) || a.days_until_due - b.days_until_due);

  const totalDue = items
    .filter((b) => b.type === 'expense' && (b.status === 'overdue' || b.status === 'due_soon' || b.status === 'upcoming'))
    .reduce((s, b) => s + Number(b.amount), 0);

  return { month, total_due: totalDue, items };
}

const rank = (s: string) => ['overdue', 'due_soon', 'upcoming', 'paid', 'inactive'].indexOf(s);

export const billsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/bills',
  tags: ['Bills'],
  summary: 'Tagihan / pemasukan rutin + status bayar bulan ini (paling mendesak di atas)',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(BillsResponse), 401: errors[401] },
});
billsRouter.get('/', async (req, res) => {
  const month = validate(ListQuery, req.query).month ?? today().slice(0, 7);
  res.json(await getBillsForMonth(req.db, month));
});

registry.registerPath({
  method: 'post',
  path: '/bills',
  tags: ['Bills'],
  summary: 'Tambah tagihan / pemasukan rutin bulanan',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(BillSchema, 'Tagihan dibuat'), 400: errors[400] },
});
billsRouter.post('/', async (req, res) => {
  const body = validate(CreateBody, req.body);
  const created = unwrap(
    await req.db.from('bills').insert({ ...body, user_id: req.user.id }).select('id').single<{ id: string }>(),
  );
  const { items } = await getBillsForMonth(req.db, today().slice(0, 7), created.id);
  res.status(201).json(items[0]);
});

registry.registerPath({
  method: 'patch',
  path: '/bills/{id}',
  tags: ['Bills'],
  summary: 'Ubah tagihan rutin',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(BillSchema), 400: errors[400], 404: errors[404] },
});
billsRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(UpdateBody, req.body);
  unwrap(await req.db.from('bills').update(body).eq('id', id).select('id').single(), 'Tagihan');
  const { items } = await getBillsForMonth(req.db, today().slice(0, 7), id);
  res.json(items[0]);
});

registry.registerPath({
  method: 'delete',
  path: '/bills/{id}',
  tags: ['Bills'],
  summary: 'Hapus tagihan rutin (transaksi pembayaran lama tetap ada)',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
billsRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('bills').delete().eq('id', id).select('id').single(), 'Tagihan');
  res.status(204).end();
});

registry.registerPath({
  method: 'post',
  path: '/bills/{id}/pay',
  tags: ['Bills'],
  summary: 'Tandai sudah dibayar: otomatis mencatat transaksinya',
  description: 'Satu tagihan hanya bisa dibayar sekali per bulan (409 kalau sudah).',
  security,
  request: { params: IdParams, body: jsonBody(PayBody) },
  responses: { 201: ok(BillSchema, 'Dibayar'), 400: errors[400], 404: errors[404], 409: errors[409] },
});
billsRouter.post('/:id/pay', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(PayBody, req.body ?? {});
  const month = body.month ?? today().slice(0, 7);

  const bill = unwrap(
    await req.db
      .from('bills')
      .select('id, name, type, category_id, wallet_id, amount')
      .eq('id', id)
      .single<{ id: string; name: string; type: string; category_id: string; wallet_id: string | null; amount: number }>(),
    'Tagihan',
  );

  const result = await req.db.from('transactions').insert({
    user_id: req.user.id,
    type: bill.type,
    category_id: bill.category_id,
    wallet_id: body.wallet_id ?? bill.wallet_id ?? (await getDefaultWalletId(req.db)),
    amount: body.amount ?? bill.amount,
    transaction_date: body.date ?? today(),
    note: body.note ?? bill.name,
    bill_id: bill.id,
    bill_month: monthRange(month).start,
  });
  if (result.error?.code === '23505') {
    throw new HttpError(409, `"${bill.name}" sudah dibayar untuk bulan ini`);
  }
  unwrap({ data: true, error: result.error });

  const { items } = await getBillsForMonth(req.db, month, id);
  res.status(201).json(items[0]);
});

registry.registerPath({
  method: 'delete',
  path: '/bills/{id}/pay',
  tags: ['Bills'],
  summary: 'Batalkan pembayaran bulan ini (transaksinya ikut dihapus)',
  security,
  request: { params: IdParams, query: UnpayQuery },
  responses: { 200: ok(BillSchema), 404: errors[404] },
});
billsRouter.delete('/:id/pay', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const month = validate(UnpayQuery, req.query).month ?? today().slice(0, 7);
  unwrap(
    await req.db
      .from('transactions')
      .delete()
      .eq('bill_id', id)
      .eq('bill_month', monthRange(month).start)
      .select('id')
      .single(),
    'Pembayaran',
  );
  const { items } = await getBillsForMonth(req.db, month, id);
  res.json(items[0]);
});
