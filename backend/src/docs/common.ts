import type { ResponseConfig } from '@asteasolutions/zod-to-openapi';
import { bearerAuth, registry, z } from './registry';

export const ErrorResponse = registry.register(
  'ErrorResponse',
  z.object({
    error: z.object({
      message: z.string(),
      details: z.unknown().optional(),
    }),
  }),
);

export const security = [{ [bearerAuth.name]: [] }];

export const dateString = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Format tanggal harus YYYY-MM-DD')
  .refine((s) => !Number.isNaN(Date.parse(s)), 'Tanggal tidak valid')
  .openapi({ example: '2026-10-18' });

export const monthString = z
  .string()
  .regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Format bulan harus YYYY-MM')
  .openapi({ example: '2026-10' });

/** Nominal Rupiah (bilangan bulat). */
export const rupiah = z.number().int().openapi({ example: 25000 });

export const IdParams = z.object({
  id: z.string().uuid().openapi({ param: { name: 'id', in: 'path' } }),
});

export const transactionType = z.enum(['income', 'expense']).openapi({
  description: 'income = pemasukan, expense = pengeluaran',
});

const errorContent = (description: string): ResponseConfig => ({
  description,
  content: { 'application/json': { schema: ErrorResponse } },
});

export const jsonBody = <T extends z.ZodTypeAny>(schema: T) => ({
  content: { 'application/json': { schema } },
});

export const ok = <T extends z.ZodTypeAny>(schema: T, description = 'Berhasil'): ResponseConfig => ({
  description,
  content: { 'application/json': { schema } },
});

export const errors = {
  400: errorContent('Input tidak valid'),
  401: errorContent('Belum login / token tidak valid'),
  404: errorContent('Data tidak ditemukan'),
  409: errorContent('Konflik data'),
};
