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
import { getDefaultWalletId } from '../../lib/wallets';

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
    wallet_id: z.string().uuid(),
    bill_id: z.string().uuid().nullable().openapi({ description: 'Terisi kalau transaksi ini pembayaran tagihan rutin' }),
    category: CategorySummary,
    wallet: CategorySummary.openapi({ description: 'Dompet asal/tujuan uang' }),
  }),
);

const ListQuery = z.object({
  start_date: dateString.optional(),
  end_date: dateString.optional(),
  type: transactionType.optional(),
  category_id: z.string().uuid().optional(),
  wallet_id: z.string().uuid().optional(),
  search: z.string().max(100).optional().openapi({ description: 'Cari di catatan atau nama kategori' }),
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
  wallet_id: z.string().uuid().optional().openapi({ description: 'Default: dompet utama' }),
  client_id: z
    .string()
    .uuid()
    .optional()
    .openapi({ description: 'ID dari aplikasi untuk transaksi offline; kirim ulang dengan ID sama tidak membuat dobel' }),
});

const UpdateBody = CreateBody.omit({ client_id: true }).partial().refine(
  (b) => b.type === undefined || b.category_id !== undefined,
  { message: 'Kalau mengubah type, category_id juga harus dikirim', path: ['category_id'] },
);

const ExportQuery = z
  .object({ start_date: dateString, end_date: dateString })
  .refine((q) => q.start_date <= q.end_date, { message: 'start_date harus <= end_date', path: ['end_date'] });

const COLUMNS =
  'id, category_id, type, amount, note, transaction_date, created_at, updated_at, wallet_id, bill_id, ' +
  'category:categories(id, name, icon, color), wallet:wallets(id, name, icon, color)';

/**
 * Filter pencarian: cocok di catatan ATAU nama kategori.
 * Karakter yang punya arti khusus di filter PostgREST dibuang.
 */
async function searchFilter(db: Express.Request['db'], raw: string): Promise<string> {
  const term = raw.replace(/[,()"\\%*]/g, ' ').trim();
  const categories = unwrap(
    await db.from('categories').select('id').ilike('name', `%${term}%`).returns<{ id: string }[]>(),
  );
  const parts = [`note.ilike.*${term}*`];
  if (categories.length) parts.push(`category_id.in.(${categories.map((c) => c.id).join(',')})`);
  return parts.join(',');
}

export const transactionsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/transactions/export',
  tags: ['Transactions'],
  summary: 'Ekspor transaksi ke CSV (bisa dibuka di Excel)',
  description: 'Pemisah kolom titik koma (;) agar langsung rapi di Excel berbahasa Indonesia.',
  security,
  request: { query: ExportQuery },
  responses: {
    200: { description: 'File CSV', content: { 'text/csv': { schema: z.string() } } },
    400: errors[400],
  },
});
transactionsRouter.get('/export', async (req, res) => {
  const { start_date, end_date } = validate(ExportQuery, req.query);
  const rows = unwrap(
    await req.db
      .from('transactions')
      .select('transaction_date, type, amount, note, category:categories(name), wallet:wallets(name)')
      .gte('transaction_date', start_date)
      .lte('transaction_date', end_date)
      .order('transaction_date')
      .order('created_at')
      .limit(10000)
      .returns<
        {
          transaction_date: string;
          type: string;
          amount: number;
          note: string | null;
          category: { name: string } | null;
          wallet: { name: string } | null;
        }[]
      >(),
  );

  const cell = (v: string | number) => {
    const s = String(v);
    return /[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [
    ['Tanggal', 'Jenis', 'Kategori', 'Dompet', 'Nominal', 'Catatan'].join(';'),
    ...rows.map((r) =>
      [
        r.transaction_date,
        r.type === 'income' ? 'Pemasukan' : 'Pengeluaran',
        r.category?.name ?? '',
        r.wallet?.name ?? '',
        r.type === 'income' ? r.amount : -r.amount,
        r.note ?? '',
      ]
        .map(cell)
        .join(';'),
    ),
  ];

  // BOM supaya Excel membaca UTF-8 (huruf & emoji tidak rusak)
  res
    .type('text/csv; charset=utf-8')
    .attachment(`savely_${start_date}_${end_date}.csv`)
    .send('\uFEFF' + lines.join('\r\n'));
});

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
  if (query.wallet_id) q = q.eq('wallet_id', query.wallet_id);
  if (query.search?.trim()) q = q.or(await searchFilter(req.db, query.search));

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
  const { client_id, ...body } = validate(CreateBody, req.body);
  const row: Record<string, unknown> = {
    ...body,
    transaction_date: body.transaction_date ?? today(),
    wallet_id: body.wallet_id ?? (await getDefaultWalletId(req.db)),
    user_id: req.user.id,
  };

  let result = await req.db
    .from('transactions')
    .insert(client_id ? { ...row, client_id } : row)
    .select(COLUMNS)
    .single();

  // Kolom client_id belum ada (migration anti-dobel belum dijalankan): simpan tanpa client_id
  if (result.error?.code === 'PGRST204' && client_id) {
    result = await req.db.from('transactions').insert(row).select(COLUMNS).single();
  }

  // Transaksi offline yang sama dikirim ulang -> kembalikan yang sudah tersimpan, jangan dobel
  if (result.error?.code === '23505' && client_id) {
    const existing = unwrap(
      await req.db.from('transactions').select(COLUMNS).eq('client_id', client_id).single(),
      'Transaksi',
    );
    res.status(200).json(existing);
    return;
  }

  res.status(201).json(unwrap(result));
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
