// Membuat efek suara Savely secara sintetis (tanpa file dari internet, bebas lisensi).
// Jalankan dari folder frontend:  node tool/generate_sounds.mjs
// Hasil: assets/sounds/*.wav (mono, 16-bit, 44.1 kHz)
import { mkdirSync, writeFileSync } from 'node:fs';

const RATE = 44100;
const OUT = new URL('../assets/sounds/', import.meta.url);
mkdirSync(OUT, { recursive: true });

/** Buffer kosong sepanjang [seconds]. */
const buffer = (seconds) => new Float32Array(Math.ceil(seconds * RATE));

/**
 * Nada lonceng: gelombang sinus + harmonik, serangan cepat, meluruh eksponensial.
 * [partials] = [[rasio frekuensi, kekuatan], ...]
 */
function bell(buf, { freq, start = 0, amp = 0.5, decay = 0.18, attack = 0.004, partials = [[1, 1], [2, 0.25], [3, 0.08]] }) {
  const s0 = Math.floor(start * RATE);
  for (let i = s0; i < buf.length; i++) {
    const t = (i - s0) / RATE;
    const env = Math.min(1, t / attack) * Math.exp(-t / decay);
    if (env < 1e-4 && t > attack) break;
    let v = 0;
    for (const [ratio, gain] of partials) v += gain * Math.sin(2 * Math.PI * freq * ratio * t);
    buf[i] += amp * env * v;
  }
}

/** Sapuan frekuensi (mis. turun untuk efek "hapus"). */
function sweep(buf, { from, to, start = 0, dur, amp = 0.5 }) {
  const s0 = Math.floor(start * RATE);
  let phase = 0;
  for (let i = s0; i < Math.min(buf.length, s0 + dur * RATE); i++) {
    const t = (i - s0) / RATE;
    const p = t / dur;
    const f = from * Math.pow(to / from, p);
    phase += (2 * Math.PI * f) / RATE;
    const env = Math.min(1, t / 0.006) * Math.pow(1 - p, 2);
    buf[i] += amp * env * (Math.sin(phase) + 0.2 * Math.sin(2 * phase));
  }
}

/** Normalisasi ke puncak [peak], fade-out pendek, lalu simpan sebagai WAV 16-bit. */
function save(name, buf, peak = 0.55) {
  const max = buf.reduce((m, v) => Math.max(m, Math.abs(v)), 0) || 1;
  const fade = Math.floor(0.01 * RATE);
  const pcm = Buffer.alloc(44 + buf.length * 2);
  pcm.write('RIFF', 0);
  pcm.writeUInt32LE(36 + buf.length * 2, 4);
  pcm.write('WAVEfmt ', 8);
  pcm.writeUInt32LE(16, 16); // ukuran chunk fmt
  pcm.writeUInt16LE(1, 20); // PCM
  pcm.writeUInt16LE(1, 22); // mono
  pcm.writeUInt32LE(RATE, 24);
  pcm.writeUInt32LE(RATE * 2, 28);
  pcm.writeUInt16LE(2, 32);
  pcm.writeUInt16LE(16, 34);
  pcm.write('data', 36);
  pcm.writeUInt32LE(buf.length * 2, 40);
  for (let i = 0; i < buf.length; i++) {
    const tail = i > buf.length - fade ? (buf.length - i) / fade : 1;
    const v = Math.max(-1, Math.min(1, (buf[i] / max) * peak * tail));
    pcm.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  writeFileSync(new URL(`${name}.wav`, OUT), pcm);
  console.log(`assets/sounds/${name}.wav  ${(buf.length / RATE).toFixed(2)} dtk`);
}

const NOTE = { C6: 1046.5, E6: 1318.5, G6: 1568.0, B5: 987.8, C7: 2093.0, E7: 2637.0, G7: 3136.0, A4: 440, E4: 329.6, C4: 261.6 };

// tap: "tik" halus & singkat untuk ganti tab / pilihan
{
  const b = buffer(0.06);
  sweep(b, { from: 1900, to: 1100, dur: 0.045, amp: 0.6 });
  save('tap', b, 0.32);
}

// success: dua nada naik (C6 -> G6), cerah tapi lembut
{
  const b = buffer(0.6);
  bell(b, { freq: NOTE.C6, start: 0, decay: 0.16 });
  bell(b, { freq: NOTE.G6, start: 0.09, decay: 0.22 });
  save('success', b, 0.5);
}

// coin: bunyi koin (B5 lalu E6) dengan kilau logam
{
  const b = buffer(0.7);
  const metal = [[1, 1], [2.76, 0.35], [5.4, 0.12]];
  bell(b, { freq: NOTE.B5, start: 0, decay: 0.05, partials: metal });
  bell(b, { freq: NOTE.E6, start: 0.075, decay: 0.24, partials: metal });
  save('coin', b, 0.5);
}

// celebrate: arpeggio C6-E6-G6-C7 + kilau tinggi (target tercapai)
{
  const b = buffer(1.4);
  [NOTE.C6, NOTE.E6, NOTE.G6, NOTE.C7].forEach((f, i) => bell(b, { freq: f, start: i * 0.075, decay: 0.3 }));
  [NOTE.E7, NOTE.G7, NOTE.E7, NOTE.C7].forEach((f, i) =>
    bell(b, { freq: f, start: 0.36 + i * 0.09, amp: 0.18, decay: 0.2, partials: [[1, 1]] }),
  );
  save('celebrate', b, 0.5);
}

// delete: "wus" turun, singkat
{
  const b = buffer(0.3);
  sweep(b, { from: 900, to: 220, dur: 0.24, amp: 0.6 });
  save('delete', b, 0.4);
}

// error: dua nada rendah turun, tidak mengagetkan
{
  const b = buffer(0.45);
  const soft = [[1, 1], [2, 0.3]];
  bell(b, { freq: NOTE.E4, start: 0, decay: 0.09, partials: soft });
  bell(b, { freq: NOTE.C4, start: 0.13, decay: 0.12, partials: soft });
  save('error', b, 0.42);
}
