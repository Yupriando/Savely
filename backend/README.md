# Savely Backend

REST API (Express 5 + TypeScript) untuk Savely. Data disimpan di Supabase.

## Setup

```bash
npm install
cp .env.example .env   # isi SUPABASE_URL & SUPABASE_ANON_KEY
npm run dev            # http://localhost:3000
```

Skema database ada di `supabase/migrations/` (jalankan di Supabase SQL Editor).

## Swagger

Buka **http://localhost:3000/docs**. Spesifikasi OpenAPI mentahnya ada di `/docs.json`.

1. `POST /auth/register`, lalu `POST /auth/login`
2. Salin `session.access_token`
3. Klik **Authorize**, tempel token

## Scripts

| Perintah | Fungsi |
|---|---|
| `npm run dev` | Jalan dengan auto-reload |
| `npm run build` | Compile ke `dist/` |
| `npm start` | Jalankan hasil build |
| `npm run typecheck` | Cek tipe TypeScript |

## Struktur

```
src/
  index.ts              entry point
  app.ts                setup express, route, swagger
  config/env.ts         validasi .env
  lib/                  supabase client, error, validasi, util tanggal
  middleware/           auth (Bearer token) & error handler
  docs/                 registry OpenAPI & schema umum
  modules/<fitur>/      route + schema zod + dokumentasi swagger per fitur
```

Setiap request memakai Supabase client dengan token user, jadi Row Level Security
di database memastikan user hanya bisa akses datanya sendiri.
