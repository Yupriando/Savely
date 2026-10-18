import { Router } from 'express';
import {
  dateString,
  errors,
  IdParams,
  jsonBody,
  ok,
  rupiah,
  security,
  transactionType,
} from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { unwrap } from '../../lib/errors';
import { today } from '../../lib/dates';
import { validate } from '../../lib/validate';

const CategorySummary = z.object({
  id: z.string().uuid(),
  name: z.string(),
  icon: z.string(),
  color: z.string(),
});

const TransactionSchema = registry.register(
  'Transaction',
  z.object({
    id: z.string().uuid(),
    category_id: z.string().uuid(),
    type: transactionType,
    amount: rupiah,
    note: z.string().nullable(),
    transaction_date: dateString,
    created_at: z.string(),
    updated_at: z.string(),
    category: CategorySummary,
  }),
);

const ListQuery = z.object({
  start_date: dateString.optional(),
  end_date: dateString.optional(),
  type: transactionType.optional(),
  category_id: z.string().uuid().optional(),
  search: z.string().max(100).optional().openapi({ description: 'Cari di catatan' }),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const ListResponse = z.object({
  data: z.array(TransactionSchema),
  pagination: z.object({
    page: z.number(),
    limit: z.number(),
    total: z.number(),
    total_pages: z.number(),
  }),
});

const CreateBody = z.object({
  category_id: z.string().uuid(),
  type: transactionType,
  amount: rupiah.positive(),
  note: z.string().max(255).nullable().optional().openapi({ example: 'Makan siang' }),
  transaction_date: dateString.optional().openapi({ description: 'Default: hari ini' }),
});

const UpdateBody = CreateBody.partial().refine(
  (b) => b.type === undefined || b.category_id !== undefined,
  { message: 'Kalau mengubah type, category_id juga harus dikirim', path: ['category_id'] },
);

const COLUMNS =
  'id, category_id, type, amount, note, transaction_date, created_at, updated_at, category:categories(id, name, icon, color)';

export const transactionsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/transactions',
  tags: ['Transactions'],
  summary: 'Daftar transaksi (terbaru dulu)',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(ListResponse), 400: errors[400], 401: errors[401] },
});
transactionsRouter.get('/', async (req, res) => {
  const query = validate(ListQuery, req.query);
  const from = (query.page - 1) * query.limit;

  let q = req.db
    .from('transactions')
    .select(COLUMNS, { count: 'exact' })
    .order('transaction_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, from + query.limit - 1);

  if (query.start_date) q = q.gte('transaction_date', query.start_date);
  if (query.end_date) q = q.lte('transaction_date', query.end_date);
  if (query.type) q = q.eq('type', query.type);
  if (query.category_id) q = q.eq('category_id', query.category_id);
  if (query.search) q = q.ilike('note', `%${query.search}%`);

  const result = await q;
  const data = unwrap(result);
  const total = result.count ?? 0;
  res.json({
    data,
    pagination: {
      page: query.page,
      limit: query.limit,
      total,
      total_pages: Math.ceil(total / query.limit),
    },
  });
});

registry.registerPath({
  method: 'get',
  path: '/transactions/{id}',
  tags: ['Transactions'],
  summary: 'Detail transaksi',
  security,
  request: { params: IdParams },
  responses: { 200: ok(TransactionSchema), 404: errors[404] },
});
transactionsRouter.get('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  res.json(unwrap(await req.db.from('transactions').select(COLUMNS).eq('id', id).single(), 'Transaksi'));
});

registry.registerPath({
  method: 'post',
  path: '/transactions',
  tags: ['Transactions'],
  summary: 'Catat pemasukan / pengeluaran',
  description: '`type` harus sama dengan tipe kategorinya.',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(TransactionSchema, 'Transaksi dibuat'), 400: errors[400] },
});
transactionsRouter.post('/', async (req, res) => {
  const body = validate(CreateBody, req.body);
  const created = unwrap(
    await req.db
      .from('transactions')
      .insert({ ...body, transaction_date: body.transaction_date ?? today(), user_id: req.user.id })
      .select(COLUMNS)
      .single(),
  );
  res.status(201).json(created);
});

registry.registerPath({
  method: 'patch',
  path: '/transactions/{id}',
  tags: ['Transactions'],
  summary: 'Ubah transaksi',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(TransactionSchema), 400: errors[400], 404: errors[404] },
});
transactionsRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(UpdateBody, req.body);
  const updated = unwrap(
    await req.db.from('transactions').update(body).eq('id', id).select(COLUMNS).single(),
    'Transaksi',
  );
  res.json(updated);
});

registry.registerPath({
  method: 'delete',
  path: '/transactions/{id}',
  tags: ['Transactions'],
  summary: 'Hapus transaksi',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
transactionsRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('transactions').delete().eq('id', id).select('id').single(), 'Transaksi');
  res.status(204).end();
});
