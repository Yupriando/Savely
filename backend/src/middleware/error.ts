import type { ErrorRequestHandler, RequestHandler } from 'express';
import { MulterError } from 'multer';
import { HttpError } from '../lib/errors';

export const notFoundHandler: RequestHandler = (req, res) => {
  res.status(404).json({ error: { message: `Endpoint ${req.method} ${req.path} tidak ditemukan` } });
};

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof HttpError) {
    if (err.status >= 500) console.error(err);
    res.status(err.status).json({ error: { message: err.message, details: err.details } });
    return;
  }

  if (err instanceof MulterError) {
    const message = err.code === 'LIMIT_FILE_SIZE' ? 'Ukuran foto maksimal 2 MB' : `Upload gagal: ${err.message}`;
    res.status(400).json({ error: { message } });
    return;
  }

  // Body JSON rusak
  if (err?.type === 'entity.parse.failed') {
    res.status(400).json({ error: { message: 'Body bukan JSON yang valid' } });
    return;
  }

  console.error(err);
  res.status(500).json({ error: { message: 'Terjadi kesalahan pada server' } });
};
