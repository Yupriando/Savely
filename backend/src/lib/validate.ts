import type { z } from 'zod';
import { fromZodError } from './errors';

/** Validasi data (body/query/params) dengan schema zod, lempar 400 kalau tidak valid. */
export function validate<T extends z.ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const result = schema.safeParse(data);
  if (!result.success) throw fromZodError(result.error);
  return result.data;
}
