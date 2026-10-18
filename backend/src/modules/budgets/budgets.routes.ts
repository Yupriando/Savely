import { Router } from 'express';
import type { SupabaseClient } from '@supabase/supabase-js';
import { errors, IdParams, jsonBody, monthString, ok, rupiah, security } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { monthRange, today } from '../../lib/dates';
import { unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';

const budgetStatus = z.enum(['safe', 'warning', 'over']).openapi({
  description: 'safe < 80%, warning 80–99%, over >= 100% terpakai',
});

const BudgetSchema = registry.register(
  'Budget',
  z.object({
    id: z.string().uuid(),
    category_id: z.string().uuid(),
    amount: rupiah.openapi({ description: 'Batas per bulan', example: 1500000 }),
    spent: rupiah.openapi({ description: 'Terpakai di bulan ini' }),
    remaining: rupiah.openapi({ description: 'Sisa (negatif = melebihi)' }),
    percent: z.number().openapi({ example: 72.5 }),
    status: budgetStatus,
    category: z.object({ id: z.string(), name: z.string(), icon: z.string(), color: z.string() }),
  }),
);

const BudgetsResponse = z.object({
  month: monthString,
  total_budget: rupiah,
  total_spent: rupiah,
  items: z.array(BudgetSchema),
});

const ListQuery = z.object({ month: monthString.optional().openapi({ description: 'Default: bulan ini' }) });

const CreateBody = z.object({
  category_id: z.string().uuid().openapi({ description: 'Harus kategori pengeluaran' }),
  amount: rupiah.positive().openapi({ example: 1500000 }),
});

const UpdateBody = CreateBody.pick({ amount: true });

const statusOf = (percent: number) => (percent >= 100 ? 'over' : percent >= 80 ? 'warning' : 'safe');

/** Anggaran + pemakaian di bulan tertentu. Dipakai juga oleh insight. */
export async function getBudgetReport(db: SupabaseClient, month: string) {
  const { start, end } = monthRange(month);
  const [budgets, spentRows] = await Promise.all([
    db
      .from('budgets')
      .select('id, category_id, amount, category:categories(id, name, icon, color)')
      .order('created_at')
      .then(unwrap),
    db
      .rpc('get_category_breakdown', { p_start: start, p_end: end, p_type: 'expense' })
      .then(unwrap),
  ]);

  const spentBy = new Map(
    (spentRows as { category_id: string; total: number }[]).map((r) => [r.category_id, Number(r.total)]),
  );

  const items = (budgets as unknown as { id: string; category_id: string; amount: number }[])
    .map((b) => {
      const spent = spentBy.get(b.category_id) ?? 0;
      const percent = Math.round((spent / Number(b.amount)) * 1000) / 10;
      return { ...b, spent, remaining: Number(b.amount) - spent, percent, status: statusOf(percent) };
    })
    .sort((a, b) => b.percent - a.percent);

  return {
    month,
    total_budget: items.reduce((s, b) => s + Number(b.amount), 0),
    total_spent: items.reduce((s, b) => s + b.spent, 0),
    items,
  };
}

export const budgetsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/budgets',
  tags: ['Budgets'],
  summary: 'Anggaran per kategori + pemakaian bulan ini (paling kritis di atas)',
  security,
  request: { query: ListQuery },
  responses: { 200: ok(BudgetsResponse), 401: errors[401] },
});
budgetsRouter.get('/', async (req, res) => {
  const month = validate(ListQuery, req.query).month ?? today().slice(0, 7);
  res.json(await getBudgetReport(req.db, month));
});

registry.registerPath({
  method: 'post',
  path: '/budgets',
  tags: ['Budgets'],
  summary: 'Buat anggaran bulanan untuk satu kategori pengeluaran',
  security,
  request: { body: jsonBody(CreateBody) },
  responses: { 201: ok(z.object({ id: z.string().uuid() }), 'Anggaran dibuat'), 400: errors[400], 409: errors[409] },
});
budgetsRouter.post('/', async (req, res) => {
  const body = validate(CreateBody, req.body);
  const created = unwrap(
    await req.db.from('budgets').insert({ ...body, user_id: req.user.id }).select('id').single(),
  );
  res.status(201).json(created);
});

registry.registerPath({
  method: 'patch',
  path: '/budgets/{id}',
  tags: ['Budgets'],
  summary: 'Ubah batas anggaran',
  security,
  request: { params: IdParams, body: jsonBody(UpdateBody) },
  responses: { 200: ok(z.object({ id: z.string().uuid() })), 400: errors[400], 404: errors[404] },
});
budgetsRouter.patch('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  const body = validate(UpdateBody, req.body);
  res.json(unwrap(await req.db.from('budgets').update(body).eq('id', id).select('id').single(), 'Anggaran'));
});

registry.registerPath({
  method: 'delete',
  path: '/budgets/{id}',
  tags: ['Budgets'],
  summary: 'Hapus anggaran',
  security,
  request: { params: IdParams },
  responses: { 204: { description: 'Terhapus' }, 404: errors[404] },
});
budgetsRouter.delete('/:id', async (req, res) => {
  const { id } = validate(IdParams, req.params);
  unwrap(await req.db.from('budgets').delete().eq('id', id).select('id').single(), 'Anggaran');
  res.status(204).end();
});
