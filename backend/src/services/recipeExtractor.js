import { extractPageContent } from './browserExtractor.js';
import { extractHttpPageContent } from './httpPageExtractor.js';
import {
  extractRecipeWithDeterministicParser,
  hasRecipeJsonLd,
} from './deterministicRecipeExtractor.js';
import { extractRecipeWithOpenAi } from './openAiRecipeExtractor.js';
import { normalizeRecipe } from '../utils/normalizeRecipe.js';

const PLAYWRIGHT_TIMEOUT_MS = 12_000;
const INCOMPLETE_URL_ERROR = 'URL incomplète : colle le lien complet de la recette.';
const MARMITON_INCOMPLETE_ERROR = 'Import Marmiton incomplet : essaie de copier la recette manuellement.';

export async function extractRecipeFromUrl(rawUrl, dependencies = {}) {
  const {
    extractHttpPageContent: httpExtractor = extractHttpPageContent,
    extractPageContent: browserExtractor = extractPageContent,
    extractRecipeWithOpenAi: openAiExtractor = extractRecipeWithOpenAi,
  } = dependencies;
  const url = validateUrl(rawUrl);
  const isMarmiton = isMarmitonUrl(url);
  const httpPageContent = await tryExtractHttpPageContent(url, httpExtractor);
  const fastJsonLdStartedAt = Date.now();
  const httpRecipe = tryExtractDeterministicRecipe({
    url: httpPageContent?.pageUrl || url,
    pageContent: httpPageContent,
  });

  if (hasUsableRecipeJsonLd(httpPageContent, httpRecipe)) {
    logFastJsonLdHit(httpPageContent, httpRecipe, fastJsonLdStartedAt);
    return finalizeRecipe(httpRecipe, httpPageContent);
  }
  logImportPath('fast-jsonld', fastJsonLdStartedAt, 'miss');

  if (isMarmiton) {
    if (isUsableRecipe(httpRecipe) && !isPollutedRecipe(httpRecipe)) {
      logImportPath('fast-http-recipe', fastJsonLdStartedAt, 'hit');
      return finalizeRecipe(httpRecipe, httpPageContent);
    }

    const aiRecipe = await tryExtractOpenAiRecipe({
      url: httpPageContent?.pageUrl || url,
      pageContent: httpPageContent,
      openAiExtractor,
      failedWarning: 'OpenAI extraction failed for Marmiton fast HTTP content.',
    });

    if (aiRecipe) {
      return finalizeRecipe(aiRecipe, httpPageContent);
    }

    throw marmitonIncompleteError();
  }

  const bestPreviousRecipe = isUsableRecipe(httpRecipe) && !isPollutedRecipe(httpRecipe)
    ? httpRecipe
    : null;

  let aiRecipe = await tryExtractOpenAiRecipe({
    url: httpPageContent?.pageUrl || url,
    pageContent: httpPageContent,
    openAiExtractor,
    failedWarning: 'OpenAI extraction failed, falling back to browser extraction.',
  });

  if (aiRecipe) {
    return finalizeRecipe(aiRecipe, httpPageContent);
  }

  const playwrightStartedAt = Date.now();
  let pageContent;
  try {
    pageContent = await withTimeout(
      browserExtractor(url),
      PLAYWRIGHT_TIMEOUT_MS,
      'Playwright extraction timed out.',
    );
  } catch (error) {
    logImportPath('playwright', playwrightStartedAt, 'failed');
    if (bestPreviousRecipe) {
      console.warn('Playwright extraction failed, returning best previous recipe.', error);
      return finalizeRecipe(bestPreviousRecipe, httpPageContent);
    }

    throw error;
  }
  const finalUrl = pageContent?.pageUrl || url;
  const fallbackRecipe = extractRecipeWithDeterministicParser({
    url: finalUrl,
    pageContent,
  });
  const requiresAiCleanup = isPollutedRecipe(fallbackRecipe) || isPollutedPageContent(pageContent);

  if (!requiresAiCleanup && isUsableRecipe(fallbackRecipe)) {
    logImportPath('playwright', playwrightStartedAt, 'hit');
    return finalizeRecipe(fallbackRecipe, pageContent);
  }
  logImportPath('playwright', playwrightStartedAt, 'miss');

  if (process.env.OPENAI_API_KEY && (!isUsableRecipe(fallbackRecipe) || requiresAiCleanup)) {
    const startedAt = Date.now();
    try {
      aiRecipe = await openAiExtractor({
        url: finalUrl,
        pageContent,
      });
      aiRecipe = validateAiRecipe(aiRecipe);
      logImportPath('openai', startedAt, 'hit');
    } catch (error) {
      logImportPath('openai', startedAt, 'failed');
      console.warn('OpenAI extraction failed after browser extraction.', error);
    }
  }

  if (aiRecipe) {
    return finalizeRecipe(aiRecipe, pageContent);
  }

  if (isPollutedRecipe(fallbackRecipe)) {
    throw importRequiresAiError();
  }

  const mergedRecipe = {
    ...fallbackRecipe,
  };

  return finalizeRecipe(mergedRecipe, pageContent);
}

async function tryExtractOpenAiRecipe({
  url,
  pageContent,
  openAiExtractor,
  failedWarning,
}) {
  if (!process.env.OPENAI_API_KEY || !pageContent) {
    return null;
  }

  const startedAt = Date.now();
  try {
    const recipe = await openAiExtractor({
      url,
      pageContent,
    });
    const validatedRecipe = validateAiRecipe(recipe);
    logImportPath('openai', startedAt, 'hit');
    return validatedRecipe;
  } catch (error) {
    logImportPath('openai', startedAt, 'failed');
    console.warn(failedWarning, error);
    return null;
  }
}

async function tryExtractHttpPageContent(url, httpExtractor) {
  const startedAt = Date.now();
  try {
    const pageContent = await httpExtractor(url);
    logImportPath('fast-http', startedAt, 'hit');
    return pageContent;
  } catch (error) {
    logImportPath('fast-http', startedAt, 'failed');
    console.warn('Fast HTTP extraction failed, falling back.', error);
    return null;
  }
}

function tryExtractDeterministicRecipe({ url, pageContent }) {
  if (!pageContent) {
    return null;
  }

  try {
    return extractRecipeWithDeterministicParser({ url, pageContent });
  } catch {
    return null;
  }
}

function hasUsableRecipeJsonLd(pageContent, recipe) {
  return hasRecipeJsonLd(pageContent?.jsonLd) && isUsableRecipe(recipe) && !isPollutedRecipe(recipe);
}

function logFastJsonLdHit(pageContent, recipe, startedAt) {
  if (recipe?.imageUrl && !hasRecipeJsonLdImage(pageContent?.jsonLd)) {
    logImportPath('fast-jsonld-html-image', startedAt, 'hit');
    return;
  }

  logImportPath('fast-jsonld', startedAt, 'hit');
}

function logImportPath(path, startedAt, status) {
  console.info(`[recipe-import] path=${path} status=${status} durationMs=${Date.now() - startedAt}`);
}

function finalizeRecipe(recipe, pageContent) {
  const normalized = normalizeRecipe(recipe);
  console.info(`[recipe-import] finalImageUrlSource=${getFinalImageUrlSource(normalized, pageContent)}`);
  return normalized;
}

function getFinalImageUrlSource(recipe, pageContent) {
  const imageUrl = recipe?.imageUrl;
  if (!imageUrl) {
    return 'none';
  }

  if (hasRecipeJsonLdImageUrl(pageContent?.jsonLd, imageUrl, pageContent?.pageUrl)) {
    return 'schema-image';
  }

  const matchingCandidate = (pageContent?.imageCandidates ?? []).find((candidate) =>
    urlsMatch(candidate?.src, imageUrl),
  );
  if (!matchingCandidate) {
    return 'none';
  }

  if (matchingCandidate.source === 'og-image' || matchingCandidate.source === 'og:image') {
    return 'og-image';
  }

  if (matchingCandidate.source === 'twitter-image' || matchingCandidate.source === 'twitter:image') {
    return 'twitter-image';
  }

  if (matchingCandidate.source === 'html-img') {
    return 'html-img';
  }

  return 'none';
}

async function withTimeout(promise, timeoutMs, message) {
  let timeoutId;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => reject(new Error(message)), timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeoutId);
  }
}

function hasRecipeJsonLdImage(blocks) {
  return (blocks ?? []).some((rawBlock) => {
    try {
      return findRecipeNodeWithImage(JSON.parse(rawBlock));
    } catch {
      return false;
    }
  });
}

function hasRecipeJsonLdImageUrl(blocks, imageUrl, baseUrl) {
  return (blocks ?? []).some((rawBlock) => {
    try {
      return recipeNodeHasImageUrl(JSON.parse(rawBlock), imageUrl, baseUrl);
    } catch {
      return false;
    }
  });
}

function findRecipeNodeWithImage(value) {
  if (Array.isArray(value)) {
    return value.some(findRecipeNodeWithImage);
  }

  if (!value || typeof value !== 'object') {
    return false;
  }

  if (isRecipeNode(value) && hasImageValue(value.image)) {
    return true;
  }

  if (value['@graph'] && findRecipeNodeWithImage(value['@graph'])) {
    return true;
  }

  return ['mainEntity', 'itemListElement'].some((key) => findRecipeNodeWithImage(value[key]));
}

function recipeNodeHasImageUrl(value, imageUrl, baseUrl = '') {
  if (Array.isArray(value)) {
    return value.some((entry) => recipeNodeHasImageUrl(entry, imageUrl, baseUrl));
  }

  if (!value || typeof value !== 'object') {
    return false;
  }

  if (isRecipeNode(value) && imageValueHasUrl(value.image, imageUrl, baseUrl)) {
    return true;
  }

  if (value['@graph'] && recipeNodeHasImageUrl(value['@graph'], imageUrl, baseUrl)) {
    return true;
  }

  return ['mainEntity', 'itemListElement'].some((key) =>
    recipeNodeHasImageUrl(value[key], imageUrl, baseUrl),
  );
}

function imageValueHasUrl(value, imageUrl, baseUrl) {
  if (Array.isArray(value)) {
    return value.some((entry) => imageValueHasUrl(entry, imageUrl, baseUrl));
  }

  if (typeof value === 'string') {
    return urlsMatch(resolvePossibleUrl(value, baseUrl), imageUrl);
  }

  if (!value || typeof value !== 'object') {
    return false;
  }

  const directValues = [
    value.url,
    value.contentUrl,
    value.src,
    value.secure_url,
    value.secureUrl,
    value.cdnUrl,
    value.cdnURL,
    value.originalUrl,
    value.originalURL,
  ];

  return directValues.some((entry) => urlsMatch(resolvePossibleUrl(entry, baseUrl), imageUrl)) ||
    imageValueHasUrl(value.image, imageUrl, baseUrl) ||
    imageValueHasUrl(value.thumbnail, imageUrl, baseUrl) ||
    imageValueHasUrl(value.thumbnailUrl, imageUrl, baseUrl) ||
    imageValueHasUrl(value.primaryImageOfPage, imageUrl, baseUrl);
}

function resolvePossibleUrl(value, baseUrl) {
  if (typeof value !== 'string' || !value.trim()) {
    return '';
  }

  try {
    return new URL(value, baseUrl || undefined).toString();
  } catch {
    return value.trim();
  }
}

function urlsMatch(left, right) {
  if (!left || !right) {
    return false;
  }

  return stripTrailingSlash(left) === stripTrailingSlash(right);
}

function stripTrailingSlash(value) {
  return String(value).replace(/\/$/, '');
}

function isRecipeNode(value) {
  const type = value?.['@type'];
  const types = Array.isArray(type) ? type : [type];
  return types.some((entry) => String(entry ?? '').split('/').pop().split(':').pop().toLowerCase() === 'recipe');
}

function hasImageValue(value) {
  if (Array.isArray(value)) {
    return value.some(hasImageValue);
  }

  if (typeof value === 'string') {
    return Boolean(value.trim());
  }

  return Boolean(
    value?.url ||
    value?.contentUrl ||
    value?.src ||
    value?.secure_url ||
    value?.secureUrl ||
    value?.cdnUrl ||
    value?.cdnURL ||
    value?.originalUrl ||
    value?.originalURL ||
    hasImageValue(value?.image) ||
    hasImageValue(value?.thumbnail) ||
    hasImageValue(value?.thumbnailUrl) ||
    hasImageValue(value?.primaryImageOfPage)
  );
}

function validateUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || !rawUrl.trim()) {
    throw badRequest('The request body must include a non-empty "url" string.');
  }

  const normalizedRawUrl = normalizeRawUrl(rawUrl.trim());
  let parsedUrl;
  try {
    parsedUrl = new URL(normalizedRawUrl);
  } catch {
    throw badRequest(INCOMPLETE_URL_ERROR);
  }

  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw badRequest('Only http and https URLs are supported.');
  }

  return parsedUrl.toString();
}

function normalizeRawUrl(rawUrl) {
  if (/^www\./i.test(rawUrl)) {
    return `https://${rawUrl}`;
  }

  if (/^marmiton\.org(?:[/?#]|$)/i.test(rawUrl)) {
    return `https://www.${rawUrl}`;
  }

  if (!/^[a-z][a-z\d+.-]*:\/\//i.test(rawUrl)) {
    throw badRequest(INCOMPLETE_URL_ERROR);
  }

  return rawUrl;
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

function marmitonIncompleteError() {
  const error = new Error(MARMITON_INCOMPLETE_ERROR);
  error.statusCode = 422;
  return error;
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

function isUsableRecipe(recipe) {
  return Boolean(
    recipe?.title &&
    Array.isArray(recipe.ingredients) &&
    recipe.ingredients.length > 0 &&
    Array.isArray(recipe.instructions) &&
    recipe.instructions.length > 0,
  );
}

function isMarmitonUrl(url) {
  try {
    return new URL(url).hostname.toLowerCase().includes('marmiton.org');
  } catch {
    return false;
  }
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

const POLLUTED_TEXT_PATTERN = /\b(partenaires?|cookies?|rgpd|donnees personnelles|consentement|confidentialite|privacy)\b/;
const AI_INGREDIENT_REJECT_PATTERN = /\b(casseroles?|fouets?|four|balance|acheter|top|meilleurs?|details?)\b/;
const IMAGE_REJECT_PATTERN = /\b(logo|banner|banniere|advert|publicite|ads?|cookie|consent|consentement|partenaires?|sprite|icon|favicon|placeholder)\b|\.svg(?:[?#]|$)/;
