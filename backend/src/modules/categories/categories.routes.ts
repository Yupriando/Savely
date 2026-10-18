import { Router } from 'express';
import { errors, IdParams, jsonBody, ok, security, transactionType } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';

export const CategorySchema = registry.register(
  'Category',
  z.object({
    id: z.string().uuid(),
    name: z.string().openapi({ example: 'Makanan & Minuman' }),
    type: transactionType,
    icon: z.string().openapi({ example: 'restaurant', description: 'Nama Material Icon di Flutter' }),
    color: z.string().openapi({ example: '#FF7043' }),
    is_default: z.boolean(),
    created_at: z.string(),
    updated_at: z.string(),
  }),
);

const ListQuery = z.object({ type: transactionType.optional() });

const CreateBody = z.object({
  name: z.string().trim().min(1).max(50).openapi({ example: 'Kopi' }),
  type: transactionType,
  icon: z.string().min(1).max(50).optional().openapi({ example: 'local_cafe' }),
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/, 'Warna harus format #RRGGBB')
    .optional()
    .openapi({ example: '#6D4C41' }),
});

// Tipe tidak bisa diubah setelah dibuat (transaksi lama bergantung padanya)
const UpdateBody = CreateBody.omit({ type: true }).partial();

const COLUMNS = 'id, name, type, icon, color, is_default, created_at, updated_at';

export const categoriesRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/categories',
  tags: ['Categories'],
  summary: 'Daftar kategori',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(z.array(CategorySchema)), 401: errors[401] },
});
categoriesRouter.get('/', async (req, res) => {
  const query = validate(ListQuery, req.query);
  let q = req.db.from('categories').select(COLUMNS).order('type').order('name');
  if (query.type) q = q.eq('type', query.type);
  res.json(unwrap(await q));
});

registry.registerPath({
  method: 'post',
  path: '/categories',
  tags: ['Categories'],
  summary: 'Buat kategori baru',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(CategorySchema, 'Kategori dibuat'), 400: errors[400], 409: errors[409] },
});
categoriesRouter.post('/', async (req, res) => {
  const body = validate(CreateBody, req.body);
  const created = unwrap(
    await req.db
      .from('categories')
      .insert({ ...body, user_id: req.user.id })
      .select(COLUMNS)
      .single(),
  );
  res.status(201).json(created);
});

registry.registerPath({
  method: 'patch',
  path: '/categories/{id}',
  tags: ['Categories'],
  summary: 'Ubah nama/ikon/warna kategori',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(CategorySchema), 400: errors[400], 404: errors[404], 409: errors[409] },
});
categoriesRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(UpdateBody, req.body);
  const updated = unwrap(
    await req.db.from('categories').update(body).eq('id', id).select(COLUMNS).single(),
    'Kategori',
  );
  res.json(updated);
});

registry.registerPath({
  method: 'delete',
  path: '/categories/{id}',
  tags: ['Categories'],
  summary: 'Hapus kategori',
  description: 'Gagal (409) kalau kategori masih dipakai oleh transaksi.',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404], 409: errors[409] },
});
categoriesRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('categories').delete().eq('id', id).select('id').single(), 'Kategori');
  res.status(204).end();
});
