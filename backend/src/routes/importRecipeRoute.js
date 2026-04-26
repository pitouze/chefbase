import express from 'express';

import { extractRecipeFromUrl } from '../services/recipeExtractor.js';

export const importRecipeRoute = express.Router();

importRecipeRoute.post('/import-recipe', async (request, response, next) => {
  try {
    const { url } = request.body ?? {};
    const recipe = await extractRecipeFromUrl(url);

    response.json(recipe);
  } catch (error) {
    next(error);
  }
});
