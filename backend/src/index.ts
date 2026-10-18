import { createApp } from './app';
import { env } from './config/env';

createApp().listen(env.PORT, () => {
  console.log(`Savely API jalan di http://localhost:${env.PORT}`);
  console.log(`Swagger docs:    http://localhost:${env.PORT}/docs`);
});
