-- =============================================================
-- Perbarui kategori bawaan:
--   * "Listrik" + "Air" digabung jadi "Listrik & Air"
--     (transaksi lama dari kategori "Air" dipindah, tidak ada yang hilang)
--   * Pengeluaran baru: "IPL" (iuran pengelolaan lingkungan apartemen)
--   * Pemasukan baru: "Kiriman Orang Tua"
-- Aman dijalankan lebih dari sekali.
-- =============================================================

begin;

-- 1. "Listrik" -> "Listrik & Air"
update public.categories c
set name = 'Listrik & Air', icon = 'bolt'
where c.type = 'expense'
  and c.name = 'Listrik'
  and not exists (
    select 1 from public.categories x
    where x.user_id = c.user_id and x.type = 'expense' and x.name = 'Listrik & Air'
  );

-- 2. Pindahkan transaksi dari "Air" ke "Listrik & Air"
update public.transactions t
set category_id = merged.id
from public.categories air
join public.categories merged
  on merged.user_id = air.user_id and merged.type = 'expense' and merged.name = 'Listrik & Air'
where air.type = 'expense'
  and air.name = 'Air'
  and t.category_id = air.id;

-- 3. Hapus kategori "Air" yang sudah digabung
delete from public.categories air
where air.type = 'expense'
  and air.name = 'Air'
  and exists (
    select 1 from public.categories merged
    where merged.user_id = air.user_id and merged.type = 'expense' and merged.name = 'Listrik & Air'
  );

-- 4. User yang punya "Air" tapi tidak punya "Listrik": cukup ganti nama
update public.categories
set name = 'Listrik & Air', icon = 'bolt'
where type = 'expense' and name = 'Air';

-- 5. Daftar kategori bawaan yang baru (untuk user baru)
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
    ('Listrik & Air',     'expense', 'bolt',            '#FFCA28'),
    ('IPL',               'expense', 'apartment',       '#0EA5E9'),
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
    ('Kiriman Orang Tua', 'income',  'family_restroom', '#F06292'),
    ('Bonus',             'income',  'redeem',          '#26A69A'),
    ('Usaha / Freelance', 'income',  'work',            '#42A5F5'),
    ('Hadiah',            'income',  'card_giftcard',   '#FFA726'),
    ('Lainnya',           'income',  'more_horiz',      '#9E9E9E')
  ) as c(name, type, icon, color)
  on conflict (user_id, name, type) do nothing;
$$;

revoke execute on function public.create_default_categories(uuid) from public, anon, authenticated;

-- 6. Tambahkan kategori baru (IPL, Kiriman Orang Tua) ke user yang sudah ada.
--    Kategori yang sudah dimiliki tidak berubah (on conflict do nothing).
select public.create_default_categories(id) from auth.users;

commit;
