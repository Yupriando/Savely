import { Router } from 'express';
import { errors, monthString, ok, security } from '../../docs/common';
import { registry, z } from '../../docs/registry';
import { addMonths, monthRange, today } from '../../lib/dates';
import { unwrap } from '../../lib/errors';
import { validate } from '../../lib/validate';
import { getBudgetReport } from '../budgets/budgets.routes';
import { getBreakdown, getSummary } from './reports.routes';

const Insight = registry.register(
  'Insight',
  z.object({
    id: z.string().openapi({ example: 'expense_change' }),
    tone: z.enum(['positive', 'negative', 'warning', 'neutral']),
    icon: z.string().openapi({ example: 'trending_up', description: 'Nama Material Icon' }),
    title: z.string().openapi({ example: 'Pengeluaran naik 25%' }),
    message: z.string(),
  }),
);

type InsightItem = z.infer<typeof Insight>;

const InsightQuery = z.object({ month: monthString.optional().openapi({ description: 'Default: bulan ini' }) });

const DAY_NAMES = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

const rp = (n: number) => `Rp${Math.round(n).toLocaleString('id-ID')}`;
const pct = (from: number, to: number) => Math.round(((to - from) / from) * 100);

type CatRow = { category_id: string; category_name: string; total: number; percentage: number };
type BudgetItem = { status: string; remaining: number; percent: number; category: { name: string } };

export const insightsRouter = Router();

registry.registerPath({
  method: 'get',
  path: '/reports/insights',
  tags: ['Reports'],
  summary: 'Insight otomatis: perbandingan bulan lalu, kategori naik, proyeksi, anggaran, dll.',
  description:
    'Bulan berjalan dibandingkan dengan periode yang sama bulan lalu (mis. tgl 1–18 vs 1–18), supaya adil.',
  security,
  request: { query: InsightQuery },
  responses: { 200: ok(z.object({ month: monthString, items: z.array(Insight) })), 400: errors[400] },
});
insightsRouter.get('/insights', async (req, res) => {
  const month = validate(InsightQuery, req.query).month ?? today().slice(0, 7);
  const now = today();
  const { start, end } = monthRange(month);
  const isCurrent = month === now.slice(0, 7);
  const cutoff = isCurrent ? now : end;
  const cutoffDay = Number(cutoff.slice(8, 10));
  const lastDay = Number(end.slice(8, 10));

  // Periode pembanding: bulan lalu sampai tanggal yang sama
  const prevMonth = addMonths(month, -1);
  const prev = monthRange(prevMonth);
  const prevEndDay = Math.min(cutoffDay, Number(prev.end.slice(8, 10)));
  const prevCutoff = `${prevMonth}-${String(prevEndDay).padStart(2, '0')}`;

  const [cur, old, curCats, oldCats, daily, budgets] = await Promise.all([
    getSummary(req.db, start, cutoff) as Promise<Record<string, number>>,
    getSummary(req.db, prev.start, prevCutoff) as Promise<Record<string, number>>,
    getBreakdown(req.db, start, cutoff, 'expense') as unknown as Promise<CatRow[]>,
    getBreakdown(req.db, prev.start, prevCutoff, 'expense') as unknown as Promise<CatRow[]>,
    req.db.rpc('get_daily_totals', { p_start: start, p_end: cutoff }).then(unwrap) as Promise<
      { day: string; expense: number }[]
    >,
    getBudgetReport(req.db, month),
  ]);

  const income = Number(cur.total_income);
  const expense = Number(cur.total_expense);
  const saved = Number(cur.total_saved);
  const oldExpense = Number(old.total_expense);
  const budgetItems = budgets.items as unknown as BudgetItem[];
  const items: InsightItem[] = [];

  // 1. Anggaran terlewati / hampir habis
  const over = budgetItems.filter((b) => b.status === 'over');
  const warn = budgetItems.filter((b) => b.status === 'warning');
  if (over.length) {
    const names = over.map((b) => b.category.name);
    items.push({
      id: 'budget_over',
      tone: 'negative',
      icon: 'report',
      title: over.length === 1 ? `Anggaran ${names[0]} terlewati` : `${over.length} anggaran terlewati`,
      message: `Lebih ${rp(-over.reduce((s, b) => s + b.remaining, 0))} dari batas: ${names.join(', ')}.`,
    });
  } else if (warn.length) {
    const b = warn[0];
    items.push({
      id: 'budget_warning',
      tone: 'warning',
      icon: 'warning_amber',
      title: `Anggaran ${b.category.name} hampir habis`,
      message: `Sudah terpakai ${b.percent}%, sisa ${rp(b.remaining)} untuk bulan ini.`,
    });
  }

  // 2. Pengeluaran melebihi pemasukan
  if (income > 0 && expense > income) {
    items.push({
      id: 'overspend',
      tone: 'negative',
      icon: 'trending_down',
      title: 'Pengeluaran melebihi pemasukan',
      message: `Selisihnya ${rp(expense - income)}. Coba kurangi pengeluaran yang tidak mendesak.`,
    });
  }

  // 3. Total pengeluaran vs bulan lalu
  if (oldExpense > 0 && expense > 0) {
    const change = pct(oldExpense, expense);
    if (Math.abs(change) >= 5) {
      items.push({
        id: 'expense_change',
        tone: change > 0 ? 'negative' : 'positive',
        icon: change > 0 ? 'trending_up' : 'trending_down',
        title: `Pengeluaran ${change > 0 ? 'naik' : 'turun'} ${Math.abs(change)}%`,
        message: `${rp(oldExpense)} → ${rp(expense)} dibanding periode yang sama bulan lalu.`,
      });
    }
  }

  // 4. Kategori yang paling naik
  const oldBy = new Map(oldCats.map((c) => [c.category_id, Number(c.total)]));
  const rising = curCats
    .map((c) => {
      const before = oldBy.get(c.category_id) ?? 0;
      return { name: c.category_name, before, now: Number(c.total), delta: Number(c.total) - before };
    })
    .filter((c) => c.before > 0 && c.delta > 0 && pct(c.before, c.now) >= 20)
    .sort((a, b) => b.delta - a.delta)[0];
  if (rising) {
    items.push({
      id: 'category_rising',
      tone: 'warning',
      icon: 'insights',
      title: `${rising.name} naik ${pct(rising.before, rising.now)}%`,
      message: `${rp(rising.delta)} lebih banyak dari bulan lalu di periode yang sama.`,
    });
  }

  // 5. Proyeksi akhir bulan (bulan berjalan saja)
  if (isCurrent && cutoffDay >= 3 && expense > 0) {
    const perDay = expense / cutoffDay;
    const projection = perDay * lastDay;
    const overBudget = budgets.total_budget > 0 && projection > budgets.total_budget;
    items.push({
      id: 'projection',
      tone: overBudget ? 'warning' : 'neutral',
      icon: 'query_stats',
      title: `Rata-rata ${rp(perDay)} per hari`,
      message: overBudget
        ? `Kalau begini terus, pengeluaran akhir bulan sekitar ${rp(projection)}, melebihi total anggaran ${rp(budgets.total_budget)}.`
        : `Kalau begini terus, pengeluaran akhir bulan sekitar ${rp(projection)}.`,
    });
  }

  // 6. Menabung
  if (income > 0 && saved > 0) {
    items.push({
      id: 'saving_rate',
      tone: 'positive',
      icon: 'savings',
      title: `Kamu menabung ${Math.round((saved / income) * 100)}% dari pemasukan`,
      message: `${rp(saved)} masuk ke tabungan wishlist bulan ini. Pertahankan!`,
    });
  }

  // 7. Hari tanpa pengeluaran
  const noSpend = daily.filter((d) => Number(d.expense) === 0).length;
  if (noSpend >= 2 && expense > 0) {
    items.push({
      id: 'no_spend_days',
      tone: 'positive',
      icon: 'emoji_events',
      title: `${noSpend} hari tanpa pengeluaran 💪`,
      message: `Dari ${daily.length} hari ${isCurrent ? 'sejauh ini di bulan ini' : 'di bulan ini'}.`,
    });
  }

  // 8. Hari paling boros (rata-rata per hari dalam seminggu)
  const byWeekday = new Map<number, { total: number; count: number }>();
  for (const d of daily) {
    const wd = new Date(`${d.day}T00:00:00Z`).getUTCDay();
    const acc = byWeekday.get(wd) ?? { total: 0, count: 0 };
    byWeekday.set(wd, { total: acc.total + Number(d.expense), count: acc.count + 1 });
  }
  const topDay = [...byWeekday.entries()]
    .map(([wd, v]) => ({ wd, avg: v.total / v.count }))
    .sort((a, b) => b.avg - a.avg)[0];
  if (topDay && topDay.avg > 0 && byWeekday.size >= 5) {
    items.push({
      id: 'top_weekday',
      tone: 'neutral',
      icon: 'event',
      title: `Hari paling boros: ${DAY_NAMES[topDay.wd]}`,
      message: `Rata-rata ${rp(topDay.avg)} tiap hari ${DAY_NAMES[topDay.wd]}.`,
    });
  }

  // 9. Kategori terbesar
  const top = curCats[0];
  if (top && top.percentage >= 30) {
    items.push({
      id: 'top_category',
      tone: 'neutral',
      icon: 'pie_chart',
      title: `${top.category_name} = ${top.percentage}% pengeluaran`,
      message: 'Kategori dengan pengeluaran terbesar bulan ini.',
    });
  }

  res.json({ month, items: items.slice(0, 6) });
});
