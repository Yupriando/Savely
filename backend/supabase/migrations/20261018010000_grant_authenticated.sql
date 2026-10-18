-- =============================================================
-- Izin akses untuk user yang login (role "authenticated").
-- Proyek Supabase baru tidak lagi otomatis memberi GRANT ke tabel baru.
-- Row Level Security tetap membatasi: user hanya bisa akses datanya sendiri.
-- =============================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete on table
  public.categories,
  public.transactions,
  public.wishlists,
  public.wishlist_savings
to authenticated;

grant select on public.wishlist_progress to authenticated;

grant usage on type public.transaction_type, public.wishlist_status to authenticated;

grant execute on function
  public.get_period_summary(date, date),
  public.get_daily_totals(date, date),
  public.get_monthly_totals(date, date),
  public.get_category_breakdown(date, date, public.transaction_type)
to authenticated;
