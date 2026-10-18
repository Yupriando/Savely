-- =============================================================
-- Savely v2: dompet, transfer, anggaran, tagihan rutin.
--
-- * Dompet (Tunai, Bank, e-wallet) dengan saldo awal.
-- * Setiap transaksi & tabungan wishlist terhubung ke satu dompet.
--   Data lama otomatis dimasukkan ke dompet "Tunai" (tidak ada yang hilang).
-- * Tabungan wishlist mengurangi saldo dompet & masuk ke ringkasan
--   sebagai "ditabung".
-- * Anggaran bulanan per kategori pengeluaran.
-- * Tagihan rutin bulanan (IPL, listrik, kiriman orang tua, dll.).
-- =============================================================

begin;

-- -------------------------------------------------------------
-- Dompet
-- -------------------------------------------------------------
create type public.wallet_type as enum ('cash', 'bank', 'ewallet', 'other');

create table public.wallets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  name             text not null check (char_length(name) between 1 and 50),
  type             public.wallet_type not null default 'cash',
  icon             text not null default 'account_balance_wallet',
  color            text not null default '#10B981' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  initial_balance  bigint not null default 0,
  is_default       boolean not null default false,
  archived         boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  unique (user_id, name),
  unique (id, user_id)
);

-- Maksimal satu dompet utama per user
create unique index wallets_one_default_per_user on public.wallets (user_id) where is_default;

create trigger wallets_set_updated_at
  before update on public.wallets
  for each row execute function public.set_updated_at();

create table public.transfers (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  from_wallet_id  uuid not null,
  to_wallet_id    uuid not null,
  amount          bigint not null check (amount > 0),
  transfer_date   date not null default current_date,
  note            text check (char_length(note) <= 255),
  created_at      timestamptz not null default now(),

  check (from_wallet_id <> to_wallet_id),
  foreign key (from_wallet_id, user_id) references public.wallets (id, user_id) on delete restrict,
  foreign key (to_wallet_id, user_id) references public.wallets (id, user_id) on delete restrict
);

create index transfers_user_date_idx on public.transfers (user_id, transfer_date desc);

-- -------------------------------------------------------------
-- Dompet bawaan "Tunai" untuk semua user (lama & baru)
-- -------------------------------------------------------------
create or replace function public.create_default_wallet(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.wallets (user_id, name, type, icon, color, is_default)
  select p_user_id, 'Tunai', 'cash', 'payments', '#10B981', true
  where not exists (select 1 from public.wallets w where w.user_id = p_user_id);
$$;

revoke execute on function public.create_default_wallet(uuid) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.create_default_categories(new.id);
  perform public.create_default_wallet(new.id);
  return new;
end;
$$;

select public.create_default_wallet(id) from auth.users;

-- -------------------------------------------------------------
-- Transaksi & tabungan wishlist terhubung ke dompet
-- -------------------------------------------------------------
alter table public.transactions add column wallet_id uuid;
alter table public.wishlist_savings add column wallet_id uuid;

update public.transactions t
set wallet_id = w.id
from public.wallets w
where w.user_id = t.user_id and w.is_default and t.wallet_id is null;

update public.wishlist_savings s
set wallet_id = w.id
from public.wallets w
where w.user_id = s.user_id and w.is_default and s.wallet_id is null;

alter table public.transactions
  alter column wallet_id set not null,
  add constraint transactions_wallet_fk
    foreign key (wallet_id, user_id) references public.wallets (id, user_id) on delete restrict;

alter table public.wishlist_savings
  alter column wallet_id set not null,
  add constraint wishlist_savings_wallet_fk
    foreign key (wallet_id, user_id) references public.wallets (id, user_id) on delete restrict;

create index transactions_wallet_idx on public.transactions (wallet_id);
create index wishlist_savings_wallet_idx on public.wishlist_savings (wallet_id);

-- -------------------------------------------------------------
-- Anggaran bulanan per kategori pengeluaran
-- -------------------------------------------------------------
create table public.budgets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  category_id    uuid not null,
  -- selalu 'expense': dipakai foreign key agar hanya kategori pengeluaran yang bisa dianggarkan
  category_type  public.transaction_type not null default 'expense' check (category_type = 'expense'),
  amount         bigint not null check (amount > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  unique (user_id, category_id),
  foreign key (category_id, user_id, category_type)
    references public.categories (id, user_id, type) on delete cascade
);

create trigger budgets_set_updated_at
  before update on public.budgets
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------
-- Tagihan / pemasukan rutin bulanan
-- -------------------------------------------------------------
create table public.bills (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  type         public.transaction_type not null default 'expense',
  category_id  uuid not null,
  wallet_id    uuid,
  amount       bigint not null check (amount > 0),
  due_day      smallint not null check (due_day between 1 and 31),
  remind_days  smallint not null default 3 check (remind_days between 0 and 14),
  note         text check (char_length(note) <= 255),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  unique (id, user_id),
  foreign key (category_id, user_id, type)
    references public.categories (id, user_id, type) on delete restrict,
  foreign key (wallet_id, user_id)
    references public.wallets (id, user_id) on delete set null (wallet_id)
);

create trigger bills_set_updated_at
  before update on public.bills
  for each row execute function public.set_updated_at();

-- Transaksi hasil "bayar tagihan" menyimpan tagihan & bulan yang dibayar
alter table public.transactions
  add column bill_id uuid,
  add column bill_month date,
  add constraint transactions_bill_fk
    foreign key (bill_id, user_id) references public.bills (id, user_id) on delete set null (bill_id),
  add constraint transactions_bill_month_check
    check (bill_month is null or extract(day from bill_month) = 1);

-- Satu tagihan hanya bisa dibayar sekali per bulan
create unique index transactions_bill_month_unique
  on public.transactions (bill_id, bill_month) where bill_id is not null;

-- -------------------------------------------------------------
-- Row Level Security
-- -------------------------------------------------------------
alter table public.wallets   enable row level security;
alter table public.transfers enable row level security;
alter table public.budgets   enable row level security;
alter table public.bills     enable row level security;

create policy "own wallets" on public.wallets
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own transfers" on public.transfers
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own budgets" on public.budgets
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own bills" on public.bills
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- -------------------------------------------------------------
-- Saldo per dompet
-- -------------------------------------------------------------
create view public.wallet_balances
with (security_invoker = true)
as
select
  w.id,
  w.user_id,
  w.name,
  w.type,
  w.icon,
  w.color,
  w.initial_balance,
  w.is_default,
  w.archived,
  w.created_at,
  (
    w.initial_balance
    + coalesce((select sum(case when t.type = 'income' then t.amount else -t.amount end)
                from public.transactions t where t.wallet_id = w.id), 0)
    + coalesce((select sum(tr.amount) from public.transfers tr where tr.to_wallet_id = w.id), 0)
    - coalesce((select sum(tr.amount) from public.transfers tr where tr.from_wallet_id = w.id), 0)
    - coalesce((select sum(s.amount) from public.wishlist_savings s where s.wallet_id = w.id), 0)
  )::bigint as balance
from public.wallets w;

-- -------------------------------------------------------------
-- Ringkasan periode: tambah "ditabung" (setoran wishlist bersih)
-- balance   = pemasukan - pengeluaran - ditabung (uang yang benar-benar tersisa)
-- cashflow  = pemasukan - pengeluaran
-- -------------------------------------------------------------
drop function public.get_period_summary(date, date);

create function public.get_period_summary(p_start date, p_end date)
returns table (
  total_income bigint,
  total_expense bigint,
  total_saved bigint,
  balance bigint,
  cashflow bigint,
  transaction_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with t as (
    select
      coalesce(sum(amount) filter (where type = 'income'), 0)::bigint  as income,
      coalesce(sum(amount) filter (where type = 'expense'), 0)::bigint as expense,
      count(*) as cnt
    from public.transactions
    where user_id = auth.uid() and transaction_date between p_start and p_end
  ),
  s as (
    select coalesce(sum(amount), 0)::bigint as saved
    from public.wishlist_savings
    where user_id = auth.uid() and saving_date between p_start and p_end
  )
  select t.income, t.expense, s.saved, t.income - t.expense - s.saved, t.income - t.expense, t.cnt
  from t, s;
$$;

-- -------------------------------------------------------------
-- Izin akses (lihat juga 20261018010000_grant_authenticated.sql)
-- -------------------------------------------------------------
grant select, insert, update, delete on table
  public.wallets, public.transfers, public.budgets, public.bills
to authenticated;
grant select on public.wallet_balances to authenticated;
grant usage on type public.wallet_type to authenticated;
grant execute on function public.get_period_summary(date, date) to authenticated;

commit;
