// Pintu masuk untuk Vercel (serverless).
// Vercel menjalankan `npm run build` (TypeScript -> dist/), lalu file ini memakai hasilnya.
// Semua URL diarahkan ke sini oleh vercel.json, jadi seluruh API Express tetap sama.
const { createApp } = require('../dist/app');

module.exports = createApp();
