import { OpenApiGeneratorV3 } from '@asteasolutions/zod-to-openapi';
import { registry } from './registry';

/** Dipanggil setelah semua router di-import, supaya semua path sudah terdaftar. */
export function buildOpenApiDocument() {
  return new OpenApiGeneratorV3(registry.definitions).generateDocument({
    openapi: '3.0.3',
    info: {
      title: 'Savely API',
      version: '1.0.0',
      description: [
        'API pencatat pemasukan, pengeluaran, wishlist & laporan keuangan.',
        '',
        '**Cara mencoba:**',
        '1. `POST /auth/register` (sekali saja), lalu `POST /auth/login`',
        '2. Salin `session.access_token` dari response',
        '3. Klik **Authorize** di kanan atas, tempel token-nya',
        '',
        'Semua nominal dalam Rupiah (bilangan bulat). Semua tanggal format `YYYY-MM-DD`.',
      ].join('\n'),
    },
    servers: [{ url: '/api' }],
    tags: [
      { name: 'Auth', description: 'Daftar, login, token' },
      { name: 'Categories', description: 'Kategori pemasukan & pengeluaran' },
      { name: 'Transactions', description: 'Catatan pemasukan & pengeluaran' },
      { name: 'Wishlists', description: 'Barang impian & tabungannya' },
      { name: 'Reports', description: 'Laporan harian, bulanan, tren & insight' },
      { name: 'Wallets', description: 'Dompet (tunai, bank, e-wallet) & transfer antar dompet' },
      { name: 'Budgets', description: 'Anggaran bulanan per kategori' },
      { name: 'Bills', description: 'Tagihan & pemasukan rutin bulanan' },
    ],
  });
}
