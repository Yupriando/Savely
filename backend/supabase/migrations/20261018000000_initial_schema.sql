-- =============================================================
-- Savely - initial schema
-- Semua nominal uang disimpan dalam Rupiah sebagai BIGINT (tanpa desimal).
-- =============================================================

-- -------------------------------------------------------------
-- Enum
-- -------------------------------------------------------------
create type public.transaction_type as enum ('income', 'expense');
create type public.wishlist_status as enum ('active', 'achieved', 'cancelled');

-- -------------------------------------------------------------
-- Helper: auto update kolom updated_at
-- -------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -------------------------------------------------------------
-- categories
-- -------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 50),
  type        public.transaction_type not null,
  icon        text not null default 'category',  -- nama Material Icon di Flutter
  color       text not null default '#9E9E9E' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  unique (user_id, name, type),
  -- dipakai foreign key komposit di transactions
  unique (id, user_id, type)
);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------
-- transactions (pemasukan & pengeluaran)
-- -------------------------------------------------------------
create table public.transactions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  category_id      uuid not null,
  type             public.transaction_type not null,
  amount           bigint not null check (amount > 0),
  note             text check (char_length(note) <= 255),
  transaction_date date not null default current_date,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Menjamin kategori milik user yang sama DAN tipenya cocok
  -- (transaksi expense tidak bisa pakai kategori income, dan sebaliknya).
  -- Kategori yang masih dipakai transaksi tidak bisa dihapus.
  foreign key (category_id, user_id, type)
    references public.categories (id, user_id, type)
    on delete restrict
);

create index transactions_user_date_idx
  on public.transactions (user_id, transaction_date desc);
create index transactions_category_idx
  on public.transactions (category_id);

create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------
-- wishlists
-- -------------------------------------------------------------
create table public.wishlists (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 100),
  target_amount  bigint not null check (target_amount > 0),
  target_date    date not null,
  note           text check (char_length(note) <= 255),
  image_url      text,
  status         public.wishlist_status not null default 'active',
  achieved_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  unique (id, user_id)
);

create index wishlists_user_status_idx
  on public.wishlists (user_id, status);

create trigger wishlists_set_updated_at
  before update on public.wishlists
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------
-- wishlist_savings (setoran tabungan untuk wishlist)
-- amount positif = setor, negatif = tarik kembali
-- -------------------------------------------------------------
create table public.wishlist_savings (
  id           uuid primary key default gen_random_uuid(),
  wishlist_id  uuid not null,
  user_id      uuid not null references auth.users (id) on delete cascade,
  amount       bigint not null check (amount <> 0),
  saving_date  date not null default current_date,
  note         text check (char_length(note) <= 255),
  created_at   timestamptz not null default now(),

  foreign key (wishlist_id, user_id)
    references public.wishlists (id, user_id)
    on delete cascade
);

create index wishlist_savings_wishlist_idx
  on public.wishlist_savings (wishlist_id, saving_date desc);

-- =============================================================
-- Row Level Security: user hanya bisa akses datanya sendiri
-- =============================================================
alter table public.categories       enable row level security;
alter table public.transactions     enable row level security;
alter table public.wishlists        enable row level security;
alter table public.wishlist_savings enable row level security;

create policy "own categories" on public.categories
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own transactions" on public.transactions
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own wishlists" on public.wishlists
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own wishlist savings" on public.wishlist_savings
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- =============================================================
-- Kategori bawaan untuk setiap user baru
-- =============================================================
create or replace function public.create_default_categories(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.categories (user_id, name, type, icon, color, is_default)
  select p_user_id, c.name, c.type::public.transaction_type, c.icon, c.color, true
  from (values
    -- pengeluaran
    ('Makanan & Minuman', 'expense', 'restaurant',      '#FF7043'),
    ('Listrik',           'expense', 'bolt',            '#FFCA28'),
    ('Air',               'expense', 'water_drop',      '#29B6F6'),
    ('Internet & Pulsa',  'expense', 'wifi',            '#5C6BC0'),
    ('Transportasi',      'expense', 'directions_car',  '#8D6E63'),
    ('Belanja',           'expense', 'shopping_bag',    '#EC407A'),
    ('Kesehatan',         'expense', 'local_hospital',  '#EF5350'),
    ('Pendidikan',        'expense', 'school',          '#7E57C2'),
    ('Hiburan',           'expense', 'movie',           '#AB47BC'),
    ('Tagihan Lainnya',   'expense', 'receipt_long',    '#78909C'),
    ('Lainnya',           'expense', 'more_horiz',      '#9E9E9E'),
    -- pemasukan
    ('Gaji',              'income',  'payments',        '#66BB6A'),
    ('Bonus',             'income',  'redeem',          '#26A69A'),
    ('Usaha / Freelance', 'income',  'work',            '#42A5F5'),
    ('Hadiah',            'income',  'card_giftcard',   '#FFA726'),
    ('Lainnya',           'income',  'more_horiz',      '#9E9E9E')
  ) as c(name, type, icon, color)
  on conflict (user_id, name, type) do nothing;
$$;

-- Fungsi ini security definer, jadi jangan bisa dipanggil langsung dari client
revoke execute on function public.create_default_categories(uuid) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.create_default_categories(new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- User yang sudah terdaftar sebelum migration ini dijalankan
select public.create_default_categories(id) from auth.users;

-- =============================================================
-- View: progres wishlist
-- security_invoker = RLS tetap berlaku sesuai user yang memanggil
-- =============================================================
create view public.wishlist_progress
with (security_invoker = true)
as
select
  w.id,
  w.user_id,
  w.name,
  w.target_amount,
  w.target_date,
  w.note,
  w.image_url,
  w.status,
  w.achieved_at,
  w.created_at,
  coalesce(s.saved, 0)::bigint                                   as saved_amount,
  greatest(w.target_amount - coalesce(s.saved, 0), 0)::bigint    as remaining_amount,
  least(round(coalesce(s.saved, 0) * 100.0 / w.target_amount, 2), 100) as progress_percent,
  (w.target_date - current_date)                                 as days_left
from public.wishlists w
left join (
  select wishlist_id, sum(amount) as saved
  from public.wishlist_savings
  group by wishlist_id
) s on s.wishlist_id = w.id;

-- =============================================================
-- Fungsi laporan (dipanggil backend via supabase.rpc)
-- security invoker -> RLS berlaku, hanya data user yang login
-- =============================================================

-- Ringkasan total untuk rentang tanggal (harian: p_start = p_end)
create or replace function public.get_period_summary(p_start date, p_end date)
returns table (total_income bigint, total_expense bigint, balance bigint, transaction_count bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    coalesce(sum(amount) filter (where type = 'income'), 0)::bigint,
    coalesce(sum(amount) filter (where type = 'expense'), 0)::bigint,
    coalesce(sum(case when type = 'income' then amount else -amount end), 0)::bigint,
    count(*)
  from public.transactions
  where user_id = auth.uid()
    and transaction_date between p_start and p_end;
$$;

-- Total per hari dalam rentang (hari tanpa transaksi tetap muncul dengan 0)
create or replace function public.get_daily_totals(p_start date, p_end date)
returns table (day date, income bigint, expense bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    d::date,
    coalesce(sum(t.amount) filter (where t.type = 'income'), 0)::bigint,
    coalesce(sum(t.amount) filter (where t.type = 'expense'), 0)::bigint
  from generate_series(p_start::timestamp, p_end::timestamp, interval '1 day') as d
  left join public.transactions t
    on t.transaction_date = d::date
   and t.user_id = auth.uid()
  group by d
  order by d;
$$;

-- Total per bulan dalam rentang (untuk grafik tren)
create or replace function public.get_monthly_totals(p_start date, p_end date)
returns table (month date, income bigint, expense bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    m::date,
    coalesce(sum(t.amount) filter (where t.type = 'income'), 0)::bigint,
    coalesce(sum(t.amount) filter (where t.type = 'expense'), 0)::bigint
  from generate_series(date_trunc('month', p_start::timestamp), date_trunc('month', p_end::timestamp), interval '1 month') as m
  left join public.transactions t
    on date_trunc('month', t.transaction_date::timestamp) = m
   and t.user_id = auth.uid()
  group by m
  order by m;
$$;

-- Rincian per kategori dalam rentang (untuk pie chart)
create or replace function public.get_category_breakdown(
  p_start date,
  p_end   date,
  p_type  public.transaction_type
)
returns table (
  category_id       uuid,
  category_name     text,
  icon              text,
  color             text,
  total             bigint,
  transaction_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    c.id,
    c.name,
    c.icon,
    c.color,
    sum(t.amount)::bigint,
    count(*)
  from public.transactions t
  join public.categories c on c.id = t.category_id
  where t.user_id = auth.uid()
    and t.type = p_type
    and t.transaction_date between p_start and p_end
  group by c.id, c.name, c.icon, c.color
  order by sum(t.amount) desc;
$$;
