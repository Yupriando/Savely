import { Router } from 'express';
import { dateString, errors, IdParams, jsonBody, ok, rupiah, security } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { today } from '../../lib/dates';
import { HttpError, unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';

const walletType = z.enum(['cash', 'bank', 'ewallet', 'other']).openapi({
  description: 'cash = tunai, bank = rekening bank, ewallet = GoPay/OVO/dll.',
});

const WalletSchema = registry.register(
  'Wallet',
  z.object({
    id: z.string().uuid(),
    name: z.string().openapi({ example: 'BCA' }),
    type: walletType,
    icon: z.string().openapi({ example: 'account_balance' }),
    color: z.string().openapi({ example: '#2563EB' }),
    initial_balance: rupiah,
    balance: rupiah.openapi({ description: 'Saldo sekarang (saldo awal + transaksi + transfer - tabungan wishlist)' }),
    is_default: z.boolean(),
    archived: z.boolean(),
    created_at: z.string(),
  }),
);

const WalletsResponse = z.object({
  total_balance: rupiah.openapi({ description: 'Total saldo semua dompet aktif' }),
  wallets: z.array(WalletSchema),
});

const ListQuery = z.object({
  include_archived: z
    .enum(['true', 'false'])
    .optional()
    .openapi({ description: 'Tampilkan dompet yang diarsipkan' }),
});

const color = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Warna harus format #RRGGBB');

const CreateBody = z.object({
  name: z.string().trim().min(1).max(50).openapi({ example: 'BCA' }),
  type: walletType.default('cash'),
  icon: z.string().min(1).max(50).optional().openapi({ example: 'account_balance' }),
  color: color.optional().openapi({ example: '#2563EB' }),
  initial_balance: rupiah.default(0).openapi({ description: 'Saldo saat mulai dicatat di Savely' }),
  is_default: z.boolean().optional(),
});

const UpdateBody = CreateBody.partial().extend({ archived: z.boolean().optional() });

const TransferSchema = registry.register(
  'Transfer',
  z.object({
    id: z.string().uuid(),
    from_wallet_id: z.string().uuid(),
    to_wallet_id: z.string().uuid(),
    amount: rupiah,
    transfer_date: dateString,
    note: z.string().nullable(),
    created_at: z.string(),
    from_wallet: z.object({ id: z.string(), name: z.string(), icon: z.string(), color: z.string() }),
    to_wallet: z.object({ id: z.string(), name: z.string(), icon: z.string(), color: z.string() }),
  }),
);

const TransferQuery = z.object({
  start_date: dateString.optional(),
  end_date: dateString.optional(),
  wallet_id: z.string().uuid().optional(),
});

const TransferBody = z
  .object({
    from_wallet_id: z.string().uuid(),
    to_wallet_id: z.string().uuid(),
    amount: rupiah.positive().openapi({ example: 200000 }),
    transfer_date: dateString.optional().openapi({ description: 'Default: hari ini' }),
    note: z.string().max(255).nullable().optional().openapi({ example: 'Tarik tunai ATM' }),
  })
  .refine((b) => b.from_wallet_id !== b.to_wallet_id, {
    message: 'Dompet asal dan tujuan harus berbeda',
    path: ['to_wallet_id'],
  });

const BALANCE_COLUMNS =
  'id, name, type, icon, color, initial_balance, balance, is_default, archived, created_at';
const TRANSFER_COLUMNS =
  'id, from_wallet_id, to_wallet_id, amount, transfer_date, note, created_at, ' +
  'from_wallet:wallets!transfers_from_wallet_id_user_id_fkey(id, name, icon, color), ' +
  'to_wallet:wallets!transfers_to_wallet_id_user_id_fkey(id, name, icon, color)';

const DEFAULT_ICONS: Record<string, string> = {
  cash: 'payments',
  bank: 'account_balance',
  ewallet: 'phone_iphone',
  other: 'account_balance_wallet',
};

export const walletsRouter = Router();

// ---------------- Transfer (didaftarkan sebelum /:id) ----------------

registry.registerPath({
  method: 'get',
  path: '/wallets/transfers',
  tags: ['Wallets'],
  summary: 'Riwayat transfer antar dompet',
  security,
  request: { query: TransferQuery },
  responses: { 200: ok(z.array(TransferSchema)), 401: errors[401] },
});
walletsRouter.get('/transfers', async (req, res) => {
  const query = validate(TransferQuery, req.query);
  let q = req.db
    .from('transfers')
    .select(TRANSFER_COLUMNS)
    .order('transfer_date', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(200);
  if (query.start_date) q = q.gte('transfer_date', query.start_date);
  if (query.end_date) q = q.lte('transfer_date', query.end_date);
  if (query.wallet_id) q = q.or(`from_wallet_id.eq.${query.wallet_id},to_wallet_id.eq.${query.wallet_id}`);
  res.json(unwrap(await q));
});

registry.registerPath({
  method: 'post',
  path: '/wallets/transfers',
  tags: ['Wallets'],
  summary: 'Pindahkan uang antar dompet (mis. tarik tunai, top up e-wallet)',
  security,
  request: { body: jsonBody(TransferBody) },
  responses: { 201: ok(TransferSchema, 'Transfer dicatat'), 400: errors[400] },
});
walletsRouter.post('/transfers', async (req, res) => {
  const body = validate(TransferBody, req.body);
  const created = unwrap(
    await req.db
      .from('transfers')
      .insert({ ...body, transfer_date: body.transfer_date ?? today(), user_id: req.user.id })
      .select(TRANSFER_COLUMNS)
      .single(),
  );
  res.status(201).json(created);
});

registry.registerPath({
  method: 'delete',
  path: '/wallets/transfers/{id}',
  tags: ['Wallets'],
  summary: 'Hapus transfer',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
walletsRouter.delete('/transfers/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('transfers').delete().eq('id', id).select('id').single(), 'Transfer');
  res.status(204).end();
});

// ---------------- Dompet ----------------

registry.registerPath({
  method: 'get',
  path: '/wallets',
  tags: ['Wallets'],
  summary: 'Daftar dompet + saldo masing-masing & total',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(WalletsResponse), 401: errors[401] },
});
walletsRouter.get('/', async (req, res) => {
  const query = validate(ListQuery, req.query);
  let q = req.db
    .from('wallet_balances')
    .select(BALANCE_COLUMNS)
    .order('is_default', { ascending: false })
    .order('created_at');
  if (query.include_archived !== 'true') q = q.eq('archived', false);
  const wallets = unwrap(await q.returns<{ balance: number; archived: boolean }[]>());
  const total = wallets.filter((w) => !w.archived).reduce((s, w) => s + Number(w.balance), 0);
  res.json({ total_balance: total, wallets });
});

async function getWallet(db: Express.Request['db'], id: string) {
  return unwrap(await db.from('wallet_balances').select(BALANCE_COLUMNS).eq('id', id).single(), 'Dompet');
}

/** Jadikan dompet ini satu-satunya dompet utama. */
async function makeDefault(db: Express.Request['db'], id: string) {
  unwrap(await db.from('wallets').update({ is_default: false }).eq('is_default', true).neq('id', id).select('id'));
  unwrap(await db.from('wallets').update({ is_default: true, archived: false }).eq('id', id).select('id').single(), 'Dompet');
}

registry.registerPath({
  method: 'post',
  path: '/wallets',
  tags: ['Wallets'],
  summary: 'Tambah dompet',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(WalletSchema, 'Dompet dibuat'), 400: errors[400], 409: errors[409] },
});
walletsRouter.post('/', async (req, res) => {
  const { is_default, ...body } = validate(CreateBody, req.body);
  const created = unwrap(
    await req.db
      .from('wallets')
      .insert({ ...body, icon: body.icon ?? DEFAULT_ICONS[body.type], user_id: req.user.id })
      .select('id')
      .single<{ id: string }>(),
  );
  if (is_default) await makeDefault(req.db, created.id);
  res.status(201).json(await getWallet(req.db, created.id));
});

registry.registerPath({
  method: 'patch',
  path: '/wallets/{id}',
  tags: ['Wallets'],
  summary: 'Ubah dompet (nama, ikon, saldo awal, jadikan utama, arsipkan)',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(WalletSchema), 400: errors[400], 404: errors[404], 409: errors[409] },
});
walletsRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const { is_default, ...body } = validate(UpdateBody, req.body);

  const current = (await getWallet(req.db, id)) as { is_default: boolean };
  if (body.archived && (current.is_default || is_default)) {
    throw new HttpError(400, 'Dompet utama tidak bisa diarsipkan. Jadikan dompet lain sebagai utama dulu.');
  }

  if (Object.keys(body).length) {
    unwrap(await req.db.from('wallets').update(body).eq('id', id).select('id').single(), 'Dompet');
  }
  if (is_default) await makeDefault(req.db, id);
  res.json(await getWallet(req.db, id));
});

registry.registerPath({
  method: 'delete',
  path: '/wallets/{id}',
  tags: ['Wallets'],
  summary: 'Hapus dompet',
  description: 'Hanya bisa kalau belum pernah dipakai. Dompet yang punya riwayat sebaiknya diarsipkan.',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404], 409: errors[409] },
});
walletsRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const current = (await getWallet(req.db, id)) as { is_default: boolean };
  if (current.is_default) throw new HttpError(400, 'Dompet utama tidak bisa dihapus');
  unwrap(await req.db.from('wallets').delete().eq('id', id).select('id').single(), 'Dompet');
  res.status(204).end();
});
