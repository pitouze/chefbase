import { extractPageContent } from './browserExtractor.js';
import {
  extractRecipeWithDeterministicParser,
  hasRecipeJsonLd,
} from './deterministicRecipeExtractor.js';
import { extractRecipeWithOpenAi } from './openAiRecipeExtractor.js';
import { normalizeRecipe } from '../utils/normalizeRecipe.js';

export async function extractRecipeFromUrl(rawUrl) {
  const url = validateUrl(rawUrl);
  const pageContent = await extractPageContent(url);
  const finalUrl = pageContent?.pageUrl || url;
  const fallbackRecipe = extractRecipeWithDeterministicParser({
    url: finalUrl,
    pageContent,
  });
  const requiresAiCleanup =
    isMarmitonUrl(finalUrl) ||
    isPollutedRecipe(fallbackRecipe) ||
    isPollutedPageContent(pageContent);

  if (!requiresAiCleanup && hasRecipeJsonLd(pageContent.jsonLd)) {
    return fallbackRecipe;
  }

  let aiRecipe = null;
  if (process.env.OPENAI_API_KEY && (requiresAiCleanup || !hasRecipeJsonLd(pageContent.jsonLd))) {
    try {
      aiRecipe = await extractRecipeWithOpenAi({
        url: finalUrl,
        pageContent,
      });
      aiRecipe = validateAiRecipe(aiRecipe);
    } catch (error) {
      console.warn('OpenAI extraction failed, falling back to deterministic parser.', error);
    }
  }

  if (aiRecipe) {
    return normalizeRecipe(aiRecipe);
  }

  if (isPollutedRecipe(fallbackRecipe)) {
    throw importRequiresAiError();
  }

  const mergedRecipe = {
    ...fallbackRecipe,
  };

  return normalizeRecipe(mergedRecipe);
}

function validateUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || !rawUrl.trim()) {
    throw badRequest('The request body must include a non-empty "url" string.');
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(rawUrl.trim());
  } catch {
    throw badRequest('The provided URL is invalid.');
  }

  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw badRequest('Only http and https URLs are supported.');
  }

  return parsedUrl.toString();
}

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function importRequiresAiError() {
  const error = new Error('Import incomplet : ce site nécessite l’import IA.');
  error.statusCode = 422;
  return error;
}

function isMarmitonUrl(url) {
  try {
    return new URL(url).hostname.toLowerCase().includes('marmiton.org');
  } catch {
    return false;
  }
}

function validateAiRecipe(recipe) {
  const rawTitle = comparableText(recipe?.title);
  if (!rawTitle || POLLUTED_TEXT_PATTERN.test(rawTitle)) {
    throw new Error('OpenAI extraction returned a polluted title.');
  }

  const rawIngredients = Array.isArray(recipe?.ingredients) ? recipe.ingredients : [];
  const pollutedIngredient = rawIngredients.find((ingredient) =>
    AI_INGREDIENT_REJECT_PATTERN.test(comparableText(formatIngredientForValidation(ingredient))),
  );

  if (pollutedIngredient) {
    throw new Error('OpenAI extraction returned polluted ingredients.');
  }

  const normalized = normalizeRecipe(recipe);
  const title = comparableText(normalized.title);

  if (!title || POLLUTED_TEXT_PATTERN.test(title)) {
    throw new Error('OpenAI extraction returned a polluted title.');
  }

  const ingredients = Array.isArray(normalized.ingredients) ? normalized.ingredients : [];
  const normalizedPollutedIngredient = ingredients.find((ingredient) =>
    AI_INGREDIENT_REJECT_PATTERN.test(
      comparableText([ingredient.display, ingredient.name].filter(Boolean).join(' ')),
    ),
  );

  if (normalizedPollutedIngredient) {
    throw new Error('OpenAI extraction returned polluted ingredients.');
  }

  if (normalized.imageUrl && IMAGE_REJECT_PATTERN.test(comparableText(normalized.imageUrl))) {
    delete normalized.imageUrl;
  }

  return normalized;
}

function isPollutedRecipe(recipe) {
  const title = comparableText(recipe?.title);
  const description = comparableText(recipe?.description);
  return POLLUTED_TEXT_PATTERN.test(title) || POLLUTED_TEXT_PATTERN.test(description);
}

function isPollutedPageContent(pageContent) {
  const title = comparableText(pageContent?.pageTitle);
  const visibleText = comparableText(pageContent?.visibleText?.slice(0, 4_000));
  return POLLUTED_TEXT_PATTERN.test(title) || POLLUTED_TEXT_PATTERN.test(visibleText);
}

function formatIngredientForValidation(ingredient) {
  if (typeof ingredient === 'string') {
    return ingredient;
  }

  if (!ingredient || typeof ingredient !== 'object') {
    return '';
  }

  return [ingredient.display, ingredient.quantity, ingredient.unit, ingredient.name]
    .filter((value) => value !== undefined && value !== null)
    .join(' ');
}

function comparableText(value) {
  if (typeof value !== 'string') {
    return '';
  }

  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

const POLLUTED_TEXT_PATTERN = /\b(partenaires?|cookies?|donnees personnelles)\b/;
const AI_INGREDIENT_REJECT_PATTERN = /\b(casseroles?|fouets?|four|balance|acheter|top|meilleurs?)\b/;
const IMAGE_REJECT_PATTERN = /\b(logo|banner|banniere|advert|publicite|ads?|cookie|consent|consentement|partenaires?|sprite|icon|favicon|placeholder)\b|\.svg(?:[?#]|$)/;
