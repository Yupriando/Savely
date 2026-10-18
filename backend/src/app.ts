import cors from 'cors';
import express, { Router } from 'express';
import helmet from 'helmet';
import swaggerUi from 'swagger-ui-express';
import { env } from './config/env';
import { buildOpenApiDocument } from './docs/openapi';
import { requireAuth } from './middleware/auth';
import { errorHandler, notFoundHandler } from './middleware/error';
import { authRouter } from './modules/auth/auth.routes';
import { categoriesRouter } from './modules/categories/categories.routes';
import { reportsRouter } from './modules/reports/reports.routes';
import { transactionsRouter } from './modules/transactions/transactions.routes';
import { wishlistsRouter } from './modules/wishlists/wishlists.routes';

export function createApp() {
  const app = express();

  // Swagger UI butuh inline script, jadi CSP helmet dimatikan
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(cors({ origin: env.CORS_ORIGIN === '*' ? '*' : env.CORS_ORIGIN.split(',').map((o) => o.trim()) }));
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  const api = Router();
  api.use('/auth', authRouter);
  api.use('/categories', requireAuth, categoriesRouter);
  api.use('/transactions', requireAuth, transactionsRouter);
  api.use('/wishlists', requireAuth, wishlistsRouter);
  api.use('/reports', requireAuth, reportsRouter);
  app.use('/api', api);

  const openApiDocument = buildOpenApiDocument();
  app.get('/docs.json', (_req, res) => {
    res.json(openApiDocument);
  });
  app.use(
    '/docs',
    swaggerUi.serve,
    swaggerUi.setup(openApiDocument, {
      customSiteTitle: 'Savely API Docs',
      swaggerOptions: { persistAuthorization: true },
    }),
  );

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
