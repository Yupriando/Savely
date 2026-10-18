-- =============================================================
-- Mode offline: transaksi yang dicatat tanpa internet diberi client_id (UUID)
-- oleh aplikasi. Kalau pengiriman terulang (mis. koneksi putus tepat setelah
-- server menyimpan), server mengenali client_id yang sama sehingga transaksi
-- tidak tercatat dua kali.
-- Aman dijalankan lebih dari sekali.
-- =============================================================

alter table public.transactions add column if not exists client_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_user_client_id_key'
  ) then
    alter table public.transactions
      add constraint transactions_user_client_id_key unique (user_id, client_id);
  end if;
end $$;
