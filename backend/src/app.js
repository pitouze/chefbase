import express from 'express';

import { importRecipeRoute } from './routes/importRecipeRoute.js';

export const app = express();

app.use((_request, response, next) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type,Accept');
  next();
});

app.options('*', (_request, response) => {
  response.sendStatus(204);
});

app.use(express.json({ limit: '1mb' }));

app.get('/health', (_request, response) => {
  response.json({ ok: true });
});

app.use(importRecipeRoute);

app.use((error, _request, response, _next) => {
  console.error(error);

  response.status(error.statusCode ?? 500).json({
    error: error.message ?? 'Unexpected server error.',
  });
});
