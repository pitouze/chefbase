import { normalizeRecipe } from '../utils/normalizeRecipe.js';

export function extractRecipeWithDeterministicParser({ url, pageContent }) {
  const isMarmiton = isMarmitonUrl(url);
  const jsonLdRecipe = findRecipeInJsonLd(pageContent?.jsonLd);

  if (jsonLdRecipe) {
    const jsonLdExtracted = extractFromJsonLdRecipe(jsonLdRecipe, url);
    return normalizeRecipe(cleanExtractedRecipe(jsonLdExtracted, { isMarmiton }));
  }

  const visibleRecipe = extractFromVisibleText(pageContent?.visibleText, { isMarmiton });
  const fallbackRecipe = {
    ...visibleRecipe,
    title: visibleRecipe.title ?? cleanTitle(pageContent?.pageTitle, { isMarmiton }),
    imageUrl: pickFallbackImage(pageContent?.imageCandidates),
  };

  return normalizeRecipe(cleanExtractedRecipe(fallbackRecipe, { isMarmiton }));
}

export function hasRecipeJsonLd(blocks) {
  return Boolean(findRecipeInJsonLd(blocks));
}

function extractFromJsonLdRecipe(recipe, url) {
  return {
    title: getString(recipe?.name),
    description: getString(recipe?.description),
    ingredients: extractIngredientsFromJsonLd(recipe),
    instructions: extractInstructionsFromJsonLd(recipe),
    prepTime: formatDuration(recipe?.prepTime ?? recipe?.totalTime),
    cookTime: formatDuration(recipe?.cookTime),
    servings: parseServings(recipe?.recipeYield),
    imageUrl: pickImageFromJsonLd(recipe, url),
    categories: extractCategories(recipe?.recipeCategory),
  };
}

function findRecipeInJsonLd(blocks) {
  for (const rawBlock of blocks ?? []) {
    try {
      const parsed = JSON.parse(rawBlock);
      const recipeNode = findRecipeNode(parsed);
      if (recipeNode) {
        return recipeNode;
      }
    } catch {
      // Ignore malformed JSON-LD.
    }
  }

  return null;
}

function findRecipeNode(value) {
  const candidates = collectRecipeNodes(value);
  return pickBestRecipeNode(candidates);
}

function collectRecipeNodes(value) {
  if (Array.isArray(value)) {
    return value.flatMap((item) => collectRecipeNodes(item));
  }

  if (!value || typeof value !== 'object') {
    return [];
  }

  if (value['@graph']) {
    const graphNodes = Array.isArray(value['@graph']) ? value['@graph'] : [value['@graph']];
    return graphNodes.flatMap((item) => collectRecipeNodes(item));
  }

  if (isRecipeNode(value)) {
    return [value];
  }

  return ['mainEntity', 'itemListElement'].flatMap((key) => collectRecipeNodes(value[key]));
}

function isRecipeNode(value) {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const type = value['@type'];
  const types = Array.isArray(type) ? type : [type];
  return types.some((entry) => normalizeSchemaType(entry) === 'recipe');
}

function pickBestRecipeNode(candidates) {
  const validCandidates = candidates
    .map((candidate, index) => ({ ...scoreRecipeNode(candidate), index }))
    .filter((candidate) => candidate.isValid);

  validCandidates.sort((left, right) =>
    right.ingredientCount - left.ingredientCount ||
    right.score - left.score ||
    left.index - right.index,
  );

  return validCandidates[0]?.recipe ?? null;
}

function scoreRecipeNode(recipe) {
  const ingredientCount = asStringArray(recipe?.recipeIngredient).length;
  const instructionCount = extractInstructionLines(recipe?.recipeInstructions).length;
  const hasIngredients = ingredientCount > 0;
  const hasInstructions = instructionCount > 0;
  const title = getString(recipe?.name) ?? getString(recipe?.headline);
  const score =
    (hasIngredients ? 1 : 0) +
    (hasInstructions ? 1 : 0) +
    (ingredientCount > 3 ? 1 : 0) +
    (instructionCount > 2 ? 1 : 0);

  return {
    recipe,
    score,
    ingredientCount,
    isValid: !isBadTitle(title) && hasIngredients && hasInstructions,
  };
}

function isBadTitle(title) {
  const comparableTitle = removeDiacritics(title ?? '').toLowerCase();
  const badTitleWords = ['partenaires', 'cookies', 'utiliser', 'rgpd'];
  return badTitleWords.some((word) => comparableTitle.includes(word));
}

function extractIngredientsFromJsonLd(recipe) {
  const lines = asStringArray(recipe?.recipeIngredient);
  if (!lines.length) {
    return null;
  }

  return lines.map(parseIngredientLine).filter(isPlausibleIngredient);
}

function extractInstructionsFromJsonLd(recipe) {
  const source = recipe?.recipeInstructions;
  if (!source) {
    return null;
  }

  const steps = extractInstructionLines(source);
  return steps.length ? steps : null;
}

function extractInstructionLines(value) {
  if (typeof value === 'string') {
    return cleanInstructionLines(splitIntoLines(value));
  }

  if (Array.isArray(value)) {
    return value.flatMap((entry) => extractInstructionLines(entry));
  }

  if (value && typeof value === 'object') {
    if (value.itemListElement) {
      return extractInstructionLines(value.itemListElement);
    }

    return extractInstructionLines(value.text ?? value.name);
  }

  return [];
}

function extractCategories(value) {
  return asStringArray(value)
    .flatMap((entry) => entry.split(/[|,/]/))
    .map(cleanText)
    .filter(Boolean);
}

function formatDuration(value) {
  const text = getString(value);
  if (!text) {
    return null;
  }

  const match = text.match(/^P(?:T)?(?:(\d+)H)?(?:(\d+)M)?$/i);
  if (!match) {
    return text;
  }

  const hours = Number.parseInt(match[1] ?? '0', 10);
  const minutes = Number.parseInt(match[2] ?? '0', 10);
  return [
    hours ? `${hours} h` : null,
    minutes ? `${minutes} min` : null,
  ].filter(Boolean).join(' ') || null;
}

function extractFromVisibleText(visibleText, { isMarmiton = false } = {}) {
  const lines = splitIntoLines(visibleText).filter((line) => cleanIngredientLine(line) || isCleanRecipeLine(line));
  const lowerLines = lines.map((line) => line.toLowerCase());

  const ingredientLines = isMarmiton ? collectMarmitonIngredientLines(lines) : collectSection(lines, lowerLines, [
    'ingredients',
    'ingrédients',
  ], [
    'instructions',
    'préparation',
    'preparation',
    'method',
    'méthode',
    'etapes',
    'étapes',
  ]);

  const instructionLines = isMarmiton ? collectMarmitonInstructionLines(lines) : collectSection(lines, lowerLines, [
    'instructions',
    'préparation',
    'preparation',
    'method',
    'méthode',
    'etapes',
    'étapes',
  ], [
    'notes',
    'nutrition',
    'commentaires',
  ]);

  return {
    title: findVisibleTitle(lines, { isMarmiton }),
    description: cleanDescription(lines.find((line, index) => index > 0 && line.length > 32)),
    ingredients: ingredientLines.map(parseIngredientLine).filter(isPlausibleIngredient),
    instructions: cleanInstructionLines(instructionLines),
    servings: parseServings(visibleText, { isMarmiton }),
  };
}

function collectSection(lines, lowerLines, headings, stopHeadings) {
  const normalizedHeadings = new Set(headings);
  const normalizedStops = new Set(stopHeadings);
  const collected = [];
  let inSection = false;

  for (let index = 0; index < lines.length; index += 1) {
    const lowerLine = lowerLines[index];

    if (normalizedHeadings.has(lowerLine)) {
      inSection = true;
      continue;
    }

    if (inSection && normalizedStops.has(lowerLine)) {
      break;
    }

    if (!inSection) {
      continue;
    }

    if (
      (lines[index].length < 2 && !isQuantityToken(lines[index]) && !isKnownIngredientUnit(lines[index])) ||
      isMetadataLine(lines[index])
    ) {
      continue;
    }

    collected.push(lines[index]);
  }

  return collected.slice(0, 30);
}

function parseIngredientLine(line) {
  const cleaned = cleanIngredientLine(line);
  if (!cleaned || !isCleanRecipeLine(cleaned) || isIngredientRejectLine(cleaned)) {
    return null;
  }

  const tokens = cleaned.split(/\s+/);
  if (!isQuantityToken(tokens[0])) {
    return isPlausibleIngredientName(cleaned) ? { name: cleaned } : null;
  }

  const quantity = parseQuantity(tokens[0]);
  const unitMatch = matchIngredientUnit(tokens, 1);
  const unit = unitMatch?.unit;
  const nameStart = unitMatch?.nextIndex ?? 1;

  const name = cleanText(tokens.slice(nameStart).join(' '));

  if (!isPlausibleIngredientName(name)) {
    return null;
  }

  return normalizeRecipe({
    ingredients: [
      {
        name,
        quantity,
        unit,
      },
    ],
  }).ingredients?.[0] ?? null;
}

function cleanIngredientLine(value) {
  const cleaned = cleanText(value);
  if (!cleaned) {
    return null;
  }

  return cleanText(
    cleaned
      .replace(INGREDIENT_GARBAGE_CUT_PATTERN, '')
      .replace(/\s+\d+(?:[.,]\d+)?(?:\/\d+)?\s*$/, ''),
  );
}

function parseServings(value, { isMarmiton = false } = {}) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(1, Math.round(value));
  }

  const text = getString(value);
  if (!text) {
    return null;
  }

  const servingMatch = text.match(/(\d{1,2})\s*(?:personnes?|portions?|parts?)/i);
  if (servingMatch) {
    return Number.parseInt(servingMatch[1], 10);
  }

  if (isMarmiton) {
    return null;
  }

  const match = text.match(/(\d{1,3})/);
  return match ? Number.parseInt(match[1], 10) : null;
}

function pickImageFromJsonLd(recipe, baseUrl) {
  return flattenImageCandidates(recipe?.image)
    .map((entry) => imageCandidateFromJsonLd(entry, baseUrl))
    .filter(Boolean)
    .sort((left, right) => right.score - left.score)
    .map((candidate) => candidate.url)[0] ?? null;
}

function imageCandidateFromJsonLd(value, baseUrl) {
  if (typeof value === 'string') {
    const url = cleanImageUrl(resolveUrl(value, baseUrl));
    return url ? { url, score: scoreImageCandidate({ url }) } : null;
  }

  if (!value || typeof value !== 'object') {
    return null;
  }

  const width = Number(value.width ?? 0);
  const height = Number(value.height ?? 0);
  const url = cleanImageUrl(resolveUrl(value.url ?? value.contentUrl, baseUrl), {
    alt: value.caption ?? value.name ?? value.alt,
    width,
    height,
  });

  if (!url) {
    return null;
  }

  return {
    url,
    score: scoreImageCandidate({
      url,
      alt: value.caption ?? value.name ?? value.alt,
      width,
      height,
    }),
  };
}

function flattenImageCandidates(value) {
  if (Array.isArray(value)) {
    return value.flatMap(flattenImageCandidates);
  }

  if (value === undefined || value === null) {
    return [];
  }

  return [value];
}

function pickFallbackImage(candidates) {
  if (!Array.isArray(candidates)) {
    return null;
  }

  const picked = candidates.find((candidate) => {
    const src = cleanImageUrl(candidate?.src, candidate);
    return Boolean(src);
  });

  return picked ? cleanImageUrl(picked.src, picked) : null;
}

function cleanImageUrl(value, candidate = {}) {
  const url = getString(value);
  if (!url) {
    return null;
  }

  const comparable = removeDiacritics(`${url} ${candidate.alt ?? ''}`).toLowerCase();
  if (IMAGE_REJECT_PATTERN.test(comparable)) {
    return null;
  }

  const width = Number(candidate.width ?? 0);
  const height = Number(candidate.height ?? 0);
  if ((width && width < 220) || (height && height < 160)) {
    return null;
  }

  try {
    const parsed = new URL(url);
    if (IMAGE_EXTENSION_REJECT_PATTERN.test(parsed.pathname)) {
      return null;
    }
  } catch {
    return null;
  }

  return url;
}

function scoreImageCandidate({ url, alt = '', width = 0, height = 0 }) {
  const area = width && height ? width * height : 0;
  const comparable = removeDiacritics(`${url} ${alt}`).toLowerCase();
  const sizeHint = extractImageSizeHint(comparable);
  const querySizeHint = extractImageQuerySizeHint(url);
  const hintedArea = Math.max(
    sizeHint ? sizeHint.width * sizeHint.height : 0,
    querySizeHint ? querySizeHint.width * querySizeHint.height : 0,
  );
  const recipeLikeScore = IMAGE_RECIPE_HINT_PATTERN.test(comparable) ? 500_000 : 0;
  const foodLikeScore = IMAGE_FOOD_HINT_PATTERN.test(comparable) ? 250_000 : 0;
  return Math.max(area, hintedArea) + recipeLikeScore + foodLikeScore;
}

function extractImageSizeHint(value) {
  const match = value.match(/(?:^|[^\d])(\d{3,4})[x_-](\d{3,4})(?:[^\d]|$)/);
  if (!match) {
    return null;
  }

  const width = Number.parseInt(match[1], 10);
  const height = Number.parseInt(match[2], 10);
  return width && height ? { width, height } : null;
}

function extractImageQuerySizeHint(value) {
  try {
    const params = new URL(value).searchParams;
    const width = Number.parseInt(params.get('w') ?? params.get('width') ?? '0', 10);
    const height = Number.parseInt(params.get('h') ?? params.get('height') ?? '0', 10);
    return width && height ? { width, height } : null;
  } catch {
    return null;
  }
}

function resolveUrl(value, baseUrl) {
  const text = getString(value);
  if (!text) {
    return null;
  }

  try {
    return new URL(text, baseUrl).toString();
  } catch {
    return null;
  }
}

function splitIntoLines(value) {
  return String(value ?? '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(?:p|li|div|section|h[1-6])>/gi, '\n')
    .split('\n')
    .map(cleanText)
    .filter(Boolean)
    .slice(0, 300);
}

function cleanText(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const cleaned = decodeHtmlEntities(value)
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned || null;
}

function asStringArray(value) {
  if (typeof value === 'string') {
    return splitIntoLines(value);
  }

  if (Array.isArray(value)) {
    return value
      .flatMap((entry) => splitIntoLines(getString(entry)))
      .filter(Boolean);
  }

  return [];
}

function getString(value) {
  if (typeof value === 'string') {
    return cleanText(value);
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }

  return null;
}

function normalizeSchemaType(value) {
  return String(value ?? '')
    .split('/')
    .pop()
    .split(':')
    .pop()
    .toLowerCase();
}

function isCleanRecipeLine(value) {
  const text = removeDiacritics(cleanText(value) ?? '').toLowerCase();
  if (!text) {
    return false;
  }

  return !NOISE_LINE_PATTERN.test(text);
}

function cleanExtractedRecipe(recipe, { isMarmiton = false } = {}) {
  return {
    ...recipe,
    title: cleanTitle(recipe?.title, { isMarmiton }),
    description: cleanDescription(recipe?.description),
    ingredients: Array.isArray(recipe?.ingredients)
      ? recipe.ingredients.filter(isPlausibleIngredient)
      : recipe?.ingredients,
    instructions: cleanInstructionLines(recipe?.instructions),
    servings: recipe?.servings && recipe.servings <= 24 ? recipe.servings : undefined,
  };
}

function cleanTitle(value, { isMarmiton = false } = {}) {
  const title = cleanText(value);
  if (!title) {
    return null;
  }

  const comparable = removeDiacritics(title).toLowerCase();
  if (
    TITLE_REJECT_PATTERN.test(comparable) ||
    (isMarmiton && (comparable.includes('marmiton et ses') || comparable === 'marmiton'))
  ) {
    return null;
  }

  return title;
}

function findVisibleTitle(lines, { isMarmiton = false } = {}) {
  for (const line of lines.slice(0, 40)) {
    const title = cleanTitle(line, { isMarmiton });
    if (title && !isMetadataLine(title) && !SECTION_BOUNDARY_PATTERN.test(removeDiacritics(title).toLowerCase())) {
      return title;
    }
  }

  return null;
}

function cleanDescription(value) {
  const description = cleanText(value);
  if (!description || !isCleanRecipeLine(description)) {
    return null;
  }

  const comparable = removeDiacritics(description).toLowerCase();
  if (COOKIE_TEXT_PATTERN.test(comparable)) {
    return null;
  }

  return description;
}

function cleanInstructionLines(value) {
  if (!Array.isArray(value)) {
    return null;
  }

  const cleaned = value
    .map((line) => cleanText(line))
    .filter(Boolean)
    .flatMap(splitEmbeddedInstructionLabels)
    .map(stripInstructionPrefix)
    .filter((line) => line && isCleanRecipeLine(line))
    .filter((line) => !isMetadataLine(line))
    .filter(isCookingActionLine);

  return [...new Set(cleaned)];
}

function splitEmbeddedInstructionLabels(line) {
  return line
    .replace(/\b(?:étape|etape)\s*\d+\b/gi, '\n')
    .split('\n')
    .map(cleanText)
    .filter(Boolean);
}

function stripInstructionPrefix(line) {
  return cleanText(line.replace(/^(?:étape|etape)\s*\d+\s*[:.-]?\s*/i, ''));
}

function isCookingActionLine(line) {
  const comparable = removeDiacritics(line).toLowerCase();
  if (comparable.length < 8) {
    return false;
  }

  return COOKING_ACTION_PATTERN.test(comparable);
}

function isMetadataLine(value) {
  const text = removeDiacritics(cleanText(value) ?? '').toLowerCase();
  if (!text) {
    return false;
  }

  return METADATA_LINE_PATTERN.test(text);
}

function collectMarmitonIngredientLines(lines) {
  const sectionLines = collectSection(lines, lines.map((line) => line.toLowerCase()), [
    'ingredients',
    'ingrédients',
  ], [
    'préparation',
    'preparation',
    'étape 1',
    'etape 1',
    'ustensiles',
  ]).filter(cleanIngredientLine);

  const grouped = groupSplitIngredientTokens(sectionLines);
  return grouped.length ? grouped : sectionLines;
}

function collectMarmitonInstructionLines(lines) {
  const lowerLines = lines.map((line) => removeDiacritics(line).toLowerCase());
  let startIndex = lowerLines.findIndex((line) => /^etape\s*1$/.test(line));

  if (startIndex === -1) {
    startIndex = lowerLines.findLastIndex((line) => line === 'preparation');
  }

  if (startIndex === -1) {
    return collectSection(lines, lowerLines, [
      'instructions',
      'preparation',
      'etapes',
    ], [
      'notes',
      'nutrition',
      'commentaires',
    ]);
  }

  const collected = [];
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const lowerLine = lowerLines[index];
    if (/^(?:commentaires?|notes?|nutrition|vous aimerez aussi)$/.test(lowerLine)) {
      break;
    }

    if (!isMetadataLine(lines[index])) {
      collected.push(lines[index]);
    }
  }

  return collected;
}

function groupSplitIngredientTokens(lines) {
  const grouped = [];
  let index = 0;

  while (index < lines.length) {
    const line = cleanIngredientLine(lines[index]);
    if (!line || isIngredientRejectLine(line)) {
      index += 1;
      continue;
    }

    if (!isQuantityToken(line)) {
      if (looksLikeWholeIngredientLine(line)) {
        grouped.push(line);
      }
      index += 1;
      continue;
    }

    const parts = [line];
    index += 1;

    if (index < lines.length && isKnownIngredientUnit(lines[index])) {
      parts.push(lines[index]);
      index += 1;
    }

    const nameParts = [];
    while (index < lines.length) {
      const next = cleanIngredientLine(lines[index]);
      if (!next || isIngredientRejectLine(next) || isMetadataLine(next)) {
        index += 1;
        continue;
      }

      if (isQuantityToken(next) || SECTION_BOUNDARY_PATTERN.test(removeDiacritics(next).toLowerCase())) {
        break;
      }

      nameParts.push(next);
      index += 1;
    }

    if (nameParts.length) {
      grouped.push([...parts, nameParts.join(' ')].join(' '));
    }
  }

  return grouped;
}

function looksLikeWholeIngredientLine(line) {
  return Boolean(line.match(/^\d/) && parseIngredientLine(line));
}

function isPlausibleIngredient(ingredient) {
  if (!ingredient || typeof ingredient !== 'object') {
    return false;
  }

  return isPlausibleIngredientName(ingredient.name);
}

function isPlausibleIngredientName(value) {
  const name = cleanText(value);
  if (!name || isIngredientRejectLine(name) || isMetadataLine(name)) {
    return false;
  }

  const comparable = removeDiacritics(name).toLowerCase();
  if (!/[a-zà-ÿ]/i.test(name) || INGREDIENT_REJECT_WORDS.has(comparable)) {
    return false;
  }

  return comparable.length > 2 || /^(oeufs?|ail|sel|eau|lait|riz)$/i.test(comparable);
}

function isIngredientRejectLine(value) {
  const text = removeDiacritics(cleanText(value) ?? '').toLowerCase();
  if (!text) {
    return true;
  }

  return INGREDIENT_REJECT_WORDS.has(text) ||
    INGREDIENT_REJECT_PATTERN.test(text) ||
    NOISE_LINE_PATTERN.test(text);
}

function parseQuantity(value) {
  if (!value) {
    return undefined;
  }

  const fractionMatch = String(value).match(/^(\d+)\/(\d+)$/);
  if (fractionMatch) {
    const numerator = Number.parseInt(fractionMatch[1], 10);
    const denominator = Number.parseInt(fractionMatch[2], 10);
    return denominator ? numerator / denominator : undefined;
  }

  const parsed = Number.parseFloat(String(value).replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : undefined;
}

function isQuantityToken(value) {
  return /^\d+(?:[.,]\d+)?(?:\/\d+)?$/.test(cleanText(value) ?? '');
}

function isKnownIngredientUnit(value) {
  const unit = removeDiacritics(cleanText(value) ?? '').toLowerCase().replace(/\.$/, '');
  return KNOWN_UNITS.has(unit);
}

function matchIngredientUnit(tokens, startIndex) {
  const first = removeDiacritics(cleanText(tokens[startIndex]) ?? '').toLowerCase().replace(/\.$/, '');
  const second = removeDiacritics(cleanText(tokens[startIndex + 1]) ?? '').toLowerCase().replace(/\.$/, '');
  const third = removeDiacritics(cleanText(tokens[startIndex + 2]) ?? '').toLowerCase().replace(/\.$/, '');

  if (/^cuilleres?$/.test(first) && second === 'a' && third === 'cafe') {
    return { unit: 'cuillère à café', nextIndex: startIndex + 3 };
  }

  if (/^cuilleres?$/.test(first) && second === 'a' && third === 'soupe') {
    return { unit: 'cuillère', nextIndex: startIndex + 3 };
  }

  if (isKnownIngredientUnit(tokens[startIndex])) {
    return { unit: cleanText(tokens[startIndex]), nextIndex: startIndex + 1 };
  }

  return null;
}

function removeDiacritics(value) {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function decodeHtmlEntities(value) {
  return value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'");
}

const NOISE_LINE_PATTERN = /\b(partenaires?|cookies?|rgpd|privacy|confidentialite|consentement|donnees personnelles|publicite|amazon|ustensiles?|equipements?|materiels?|casseroles?|four top|fouets?|fouet cuisine|balance(?: de cuisine)?|acheter|details?|top des meilleurs|voir toutes les recettes|nos recettes|newsletter|sponsorise|partage|commentaires?|marmiton mag)\b/;
const COOKIE_TEXT_PATTERN = /\b(cookies?|partenaires?|rgpd|privacy|consentement|donnees personnelles|publicite personnalisee|confidentialite)\b/;
const METADATA_LINE_PATTERN = /^(?:temps total|préparation|preparation|repos|cuisson|temps de cuisson|temps de préparation|temps de preparation|difficulté|difficulte|budget|très facile|tres facile|facile|bon marché|bon marche|\d+\s*(?:h|min|mn|minutes?))(?:\s*:.*)?$/;
const SECTION_BOUNDARY_PATTERN = /^(?:preparation|etape\s*\d+|instructions?|methode|notes?|nutrition|commentaires?|ustensiles?|equipements?|materiels?)$/;
const COOKING_ACTION_PATTERN = /^(?:prechauffer|melanger|rajouter|ajouter|incorporer|beurrer|enfourner|sortir|verser|faire|cuire|laisser|mettre|placer|couper|hacher|emincer|battre|fouetter|remuer|servir|egoutter|rincer|chauffer|fondre|disposer|saler|poivrer|parsemer|recouvrir|reserver|preparer|former|deposer|retirer|piquer|etaler|garnir|peler|eplucher|laver)\b/;
const TITLE_REJECT_PATTERN = /\b(partenaires?|cookies?|rgpd|consentement|publicite|confidentialite|privacy)\b/;
const IMAGE_REJECT_PATTERN = /\b(logo|banner|banniere|advert|publicite|ads?|cookie|consent|consentement|partenaires?|sprite|icons?|favicon|placeholder|default|blank|tracking|pixel)\b|\.svg(?:[?#]|$)/;
const IMAGE_EXTENSION_REJECT_PATTERN = /\.(?:svg|ico)(?:[?#]|$)/i;
const IMAGE_RECIPE_HINT_PATTERN = /\b(?:recipe|recette|recettes|dish|plat|food|cuisine)\b/;
const IMAGE_FOOD_HINT_PATTERN = /\b(?:gateau|gâteau|cake|chocolat|pomme|pommes|tarte|soupe|salade|poulet|boeuf|poisson|dessert|moelleux|olive|olives)\b/;
const INGREDIENT_REJECT_PATTERN = /\b(casseroles?|fouets?|four|balance|acheter|top|meilleurs?|details?)\b/;
const INGREDIENT_GARBAGE_CUT_PATTERN = /\b(?:top\s*\d*|meilleurs?|acheter|d[ée]tails?|ustensiles?|equipements?|materiels?|casseroles?|four|balance|fouets?)\b[\s\S]*$/i;
const INGREDIENT_REJECT_WORDS = new Set([
  'acheter',
  "d'",
  'amazon',
  'balance',
  'balance de cuisine',
  'casserole',
  'casseroles',
  'commentaire',
  'commentaires',
  'cuillere',
  'cuilleres',
  'de',
  'du',
  'des',
  'ingredients',
  'ingredient',
  'marmiton',
  'personne',
  'personnes',
  'pour',
  'preparation',
  'recette',
  'top des meilleurs',
  'top',
  'ustensile',
  'ustensiles',
  'voir',
]);
const KNOWN_UNITS = new Set([
  'c',
  'cac',
  'cas',
  'cl',
  'cuillere',
  'cuilleres',
  'g',
  'gramme',
  'grammes',
  'kg',
  'l',
  'ml',
  'pincee',
  'pincees',
  'sachet',
  'sachets',
]);

function isMarmitonUrl(url) {
  try {
    return new URL(url).hostname.toLowerCase().includes('marmiton.org');
  } catch {
    return false;
  }
}
