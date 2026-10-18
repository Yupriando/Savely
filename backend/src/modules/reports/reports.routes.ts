import { Router } from 'express';
import type { SupabaseClient } from '@supabase/supabase-js';
import { dateString, errors, monthString, ok, rupiah, security, transactionType } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { addMonths, monthRange, today } from '../../lib/dates';
import { HttpError, unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';

const Summary = registry.register(
  'ReportSummary',
  z.object({
    total_income: rupiah,
    total_expense: rupiah,
    total_saved: rupiah.openapi({ description: 'Bersih disetor ke tabungan wishlist' }),
    balance: rupiah.openapi({ description: 'Sisa uang: pemasukan - pengeluaran - ditabung' }),
    cashflow: rupiah.openapi({ description: 'Pemasukan - pengeluaran' }),
    transaction_count: z.number().int(),
  }),
);

const CategoryTotal = registry.register(
  'CategoryTotal',
  z.object({
    category_id: z.string().uuid(),
    category_name: z.string(),
    icon: z.string(),
    color: z.string(),
    total: rupiah,
    transaction_count: z.number().int(),
    percentage: z.number().openapi({ description: 'Persentase dari total tipe ini' }),
  }),
);

const DailyTotal = z.object({ day: dateString, income: rupiah, expense: rupiah });
const MonthlyTotal = z.object({ month: monthString, income: rupiah, expense: rupiah, balance: rupiah });

const DailyTransaction = z.object({
  id: z.string().uuid(),
  type: transactionType,
  amount: rupiah,
  note: z.string().nullable(),
  created_at: z.string(),
  category: z.object({ id: z.string().uuid(), name: z.string(), icon: z.string(), color: z.string() }),
});

const RangeQuery = z
  .object({ start_date: dateString, end_date: dateString })
  .refine((q) => q.start_date <= q.end_date, { message: 'start_date harus <= end_date', path: ['end_date'] });
const DailyQuery = z.object({ date: dateString.optional().openapi({ description: 'Default: hari ini' }) });
const MonthlyQuery = z.object({ month: monthString.optional().openapi({ description: 'Default: bulan ini' }) });
const TrendQuery = z.object({
  months: z.coerce.number().int().min(1).max(24).default(6).openapi({ description: 'Jumlah bulan ke belakang' }),
  end_month: monthString.optional().openapi({ description: 'Default: bulan ini' }),
});

const MAX_RANGE_DAYS = 366;

// ---------- helper pemanggil fungsi SQL ----------

export async function getSummary(db: SupabaseClient, start: string, end: string) {
  return unwrap(await db.rpc('get_period_summary', { p_start: start, p_end: end }).single());
}

export async function getBreakdown(db: SupabaseClient, start: string, end: string, type: 'income' | 'expense') {
  const rows = unwrap(
    await db.rpc('get_category_breakdown', { p_start: start, p_end: end, p_type: type }),
  ) as { total: number }[];
  const grandTotal = rows.reduce((sum, r) => sum + Number(r.total), 0);
  return rows.map((r) => ({
    ...r,
    percentage: grandTotal ? Math.round((Number(r.total) / grandTotal) * 10000) / 100 : 0,
  }));
}

export const reportsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/reports/summary',
  tags: ['Reports'],
  summary: 'Ringkasan untuk rentang tanggal bebas',
  security,
  request: { query: RangeQuery },
  responses: {
    200: ok(
      z.object({
        start_date: dateString,
        end_date: dateString,
        summary: Summary,
        expense_by_category: z.array(CategoryTotal),
        income_by_category: z.array(CategoryTotal),
      }),
    ),
    400: errors[400],
  },
});
reportsRouter.get('/summary', async (req, res) => {
  const { start_date, end_date } = validate(RangeQuery, req.query);
  const days = (Date.parse(end_date) - Date.parse(start_date)) / 86_400_000;
  if (days > MAX_RANGE_DAYS) throw new HttpError(400, `Rentang maksimal ${MAX_RANGE_DAYS} hari`);

  const [summary, expense, income] = await Promise.all([
    getSummary(req.db, start_date, end_date),
    getBreakdown(req.db, start_date, end_date, 'expense'),
    getBreakdown(req.db, start_date, end_date, 'income'),
  ]);
  res.json({ start_date, end_date, summary, expense_by_category: expense, income_by_category: income });
});

registry.registerPath({
  method: 'get',
  path: '/reports/daily',
  tags: ['Reports'],
  summary: 'Laporan harian: total, per kategori & daftar transaksi hari itu',
  security,
  request: { query: DailyQuery },
  responses: {
    200: ok(
      z.object({
        date: dateString,
        summary: Summary,
        expense_by_category: z.array(CategoryTotal),
        income_by_category: z.array(CategoryTotal),
        transactions: z.array(DailyTransaction),
      }),
    ),
    400: errors[400],
  },
});
reportsRouter.get('/daily', async (req, res) => {
  const date = validate(DailyQuery, req.query).date ?? today();

  const [summary, expense, income, transactions] = await Promise.all([
    getSummary(req.db, date, date),
    getBreakdown(req.db, date, date, 'expense'),
    getBreakdown(req.db, date, date, 'income'),
    req.db
      .from('transactions')
      .select('id, type, amount, note, created_at, category:categories(id, name, icon, color)')
      .eq('transaction_date', date)
      .order('created_at', { ascending: false })
      .then(unwrap),
  ]);
  res.json({ date, summary, expense_by_category: expense, income_by_category: income, transactions });
});

registry.registerPath({
  method: 'get',
  path: '/reports/monthly',
  tags: ['Reports'],
  summary: 'Laporan bulanan: total, total per hari (untuk grafik) & per kategori',
  security,
  request: { query: MonthlyQuery },
  responses: {
    200: ok(
      z.object({
        month: monthString,
        start_date: dateString,
        end_date: dateString,
        summary: Summary,
        daily_totals: z.array(DailyTotal),
        expense_by_category: z.array(CategoryTotal),
        income_by_category: z.array(CategoryTotal),
      }),
    ),
    400: errors[400],
  },
});
reportsRouter.get('/monthly', async (req, res) => {
  const month = validate(MonthlyQuery, req.query).month ?? today().slice(0, 7);
  const { start, end } = monthRange(month);

  const [summary, dailyTotals, expense, income] = await Promise.all([
    getSummary(req.db, start, end),
    req.db.rpc('get_daily_totals', { p_start: start, p_end: end }).then(unwrap),
    getBreakdown(req.db, start, end, 'expense'),
    getBreakdown(req.db, start, end, 'income'),
  ]);
  res.json({
    month,
    start_date: start,
    end_date: end,
    summary,
    daily_totals: dailyTotals,
    expense_by_category: expense,
    income_by_category: income,
  });
});

registry.registerPath({
  method: 'get',
  path: '/reports/trend',
  tags: ['Reports'],
  summary: 'Tren pemasukan & pengeluaran beberapa bulan terakhir',
  security,
  request: { query: TrendQuery },
  responses: { 200: ok(z.array(MonthlyTotal)), 400: errors[400] },
});
reportsRouter.get('/trend', async (req, res) => {
  const query = validate(TrendQuery, req.query);
  const endMonth = query.end_month ?? today().slice(0, 7);
  const startMonth = addMonths(endMonth, -(query.months - 1));

  const rows = unwrap(
    await req.db.rpc('get_monthly_totals', {
      p_start: monthRange(startMonth).start,
      p_end: monthRange(endMonth).end,
    }),
  ) as { month: string; income: number; expense: number }[];
  res.json(
    rows.map((r) => ({
      month: r.month.slice(0, 7),
      income: r.income,
      expense: r.expense,
      balance: r.income - r.expense,
    })),
  );
});
