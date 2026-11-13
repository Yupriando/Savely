# frontend

A new Flutter project.

## Versi web (Try It Live di portofolio)
Online di **https://savely-app-six.vercel.app** (project Vercel `savely-app`).
Akun demo bersama: `demo@savely.app` / `savely-demo` (sudah berisi contoh transaksi, dompet, anggaran & wishlist).
Password & email akun demo dikunci di backend (`DEMO_EMAIL` di `backend/src/modules/auth/auth.routes.ts`).

Update versi web:
```bash
cd frontend
flutter build web --release --dart-define=API_URL=https://savely-api.vercel.app/api
npx vercel deploy build/web --prod --yes --project savely-app
```
