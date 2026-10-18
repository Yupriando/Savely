import { extendZodWithOpenApi, OpenAPIRegistry } from '@asteasolutions/zod-to-openapi';
import { z } from 'zod';

// Harus dipanggil sekali sebelum schema lain memakai .openapi()
extendZodWithOpenApi(z);

/** Semua schema & endpoint didaftarkan ke sini, lalu dijadikan dokumen Swagger. */
export const registry = new OpenAPIRegistry();

export const bearerAuth = registry.registerComponent('securitySchemes', 'bearerAuth', {
  type: 'http',
  scheme: 'bearer',
  bearerFormat: 'JWT',
  description: 'access_token dari POST /auth/login',
});

export { z };
