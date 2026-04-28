const RECIPE_KEYS = [
  'title',
  'description',
  'ingredients',
  'instructions',
  'prepTime',
  'cookTime',
  'servings',
  'imageUrl',
  'notes',
  'categories',
];

export function normalizeRecipe(recipe) {
  const normalized = {
    title: cleanTitle(recipe?.title),
    description: cleanContentString(recipe?.description),
    ingredients: normalizeIngredients(recipe?.ingredients),
    instructions: normalizeInstructions(recipe?.instructions),
    prepTime: normalizeDuration(recipe?.prepTime),
    cookTime: normalizeDuration(recipe?.cookTime),
    servings: normalizeServings(recipe?.servings),
    imageUrl: cleanImageUrl(recipe?.imageUrl ?? recipe?.image),
    notes: cleanContentString(recipe?.notes),
    categories: normalizeStringList(recipe?.categories),
  };

  return Object.fromEntries(
    RECIPE_KEYS
      .map((key) => [key, normalized[key]])
      .filter(([, value]) => isUsefulValue(value)),
  );
}

function normalizeIngredients(value) {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const normalized = value
    .map((entry) => {
      if (typeof entry === 'string') {
        return normalizeIngredientDisplayString(entry);
      }

      if (!entry || typeof entry !== 'object') {
        return null;
      }

      const name = cleanIngredientName(entry.name);
      if (!name) {
        return null;
      }

      const quantity = normalizeQuantity(entry.quantity);
      const unit = normalizeUnit(entry.unit);
      const display = formatIngredientDisplay({ name, quantity, unit });
      return Object.fromEntries(
        [
          ['name', name],
          ['quantity', quantity],
          ['unit', unit],
          ['display', display],
        ].filter(([, itemValue]) => itemValue !== undefined),
      );
    })
    .filter(Boolean);

  return normalized.length ? normalized : undefined;
}

function normalizeIngredientDisplayString(value) {
  const cleaned = cleanString(value);
  if (!cleaned || isNoiseText(cleaned)) {
    return null;
  }

  const parsed = parseIngredientDisplayString(cleaned);
  const name = cleanIngredientName(parsed.name);
  if (!name) {
    return null;
  }

  const quantity = normalizeQuantity(parsed.quantity);
  const unit = normalizeUnit(parsed.unit);
  const display = formatIngredientDisplay({ name, quantity, unit });
  return Object.fromEntries(
    [
      ['name', name],
      ['quantity', quantity],
      ['unit', unit],
      ['display', display],
    ].filter(([, itemValue]) => itemValue !== undefined),
  );
}

function parseIngredientDisplayString(value) {
  const match = value.match(/^(\d+(?:[.,]\d+)?)\s+(\S+)(?:\s+(.+))?$/);
  if (!match) {
    return { name: value };
  }

  const [, quantity, secondToken, rest] = match;
  if (rest && INGREDIENT_DISPLAY_UNITS.has(normalizeComparableText(secondToken))) {
    return {
      quantity,
      unit: secondToken,
      name: rest,
    };
  }

  return {
    quantity,
    name: [secondToken, rest].filter(Boolean).join(' '),
  };
}

function normalizeStringList(value) {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const normalized = value
    .map((entry) => cleanString(entry))
    .filter((entry) => !isNoiseText(entry))
    .filter(Boolean);

  return normalized.length ? [...new Set(normalized)] : undefined;
}

function normalizeInstructions(value) {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const seen = new Set();
  const normalized = value
    .flatMap((entry) => splitInstruction(cleanString(entry)))
    .map(cleanInstruction)
    .filter(Boolean)
    .filter((instruction) => {
      const key = normalizeComparableText(instruction);
      if (seen.has(key)) {
        return false;
      }

      seen.add(key);
      return true;
    });

  return normalized.length ? normalized : undefined;
}

function normalizeServings(value) {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
    return Math.round(value);
  }

  if (typeof value === 'string') {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }

  return undefined;
}

function normalizeDuration(value) {
  const text = cleanString(value);
  if (!text) {
    return undefined;
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
  ].filter(Boolean).join(' ') || undefined;
}

function normalizeQuantity(value) {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
    return value;
  }

  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.replace(',', '.'));
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }

  return undefined;
}

function normalizeUnit(value) {
  const unit = cleanString(value);
  if (!unit) {
    return undefined;
  }

  const comparable = normalizeComparableText(unit.replace(/\./g, ''));
  if (/^cuilleres?(?: a soupe)?$/.test(comparable) || comparable === 'cas') {
    return 'càs';
  }

  if (/^cuilleres? a cafe$/.test(comparable) || comparable === 'cac') {
    return 'càc';
  }

  if (/^grammes?$/.test(comparable)) {
    return 'g';
  }

  return normalizeApostrophes(unit);
}

function formatIngredientDisplay({ name, quantity, unit }) {
  return [formatQuantity(quantity), unit, name].filter(Boolean).join(' ');
}

function formatQuantity(value) {
  if (value === undefined) {
    return undefined;
  }

  return Number.isInteger(value) ? String(value) : String(value).replace('.', ',');
}

function cleanIngredientName(value) {
  const cleaned = cleanString(value);
  if (!cleaned || isNoiseText(cleaned)) {
    return undefined;
  }

  return normalizeApostrophes(cleaned)
    .replace(/^(?:a|à)\s+(?:soupe|cafe|café)\s+/i, '')
    .trim() || undefined;
}

function splitInstruction(value) {
  if (!value) {
    return [];
  }

  return value
    .split(/(?<=[.!?])\s+(?=[A-ZÀ-ŸÉÈÊÎÔÛÇ])/)
    .flatMap((part) => part.split(/\s*(?:\n+|[•·])\s*/))
    .map((part) => part.trim());
}

function cleanInstruction(value) {
  const cleaned = cleanString(value)
    ?.replace(/^(?:é|e)tape\s*\d+\s*[:.\-]?\s*/i, '')
    .replace(/^(?:préparation|preparation|instructions?|méthode|methode)\s*[:.\-]?\s*/i, '')
    .replace(HARD_NOISE_PATTERN, '')
    .trim();

  if (!cleaned || isNoiseInstruction(cleaned)) {
    return undefined;
  }

  return normalizeApostrophes(cleaned);
}

function isNoiseInstruction(value) {
  return /^(?:temps total|préparation|preparation|repos|cuisson|commentaires?|étape\s*\d+|etape\s*\d+)$/i.test(value) ||
    isNoiseText(value);
}

function cleanTitle(value) {
  const title = cleanString(value);
  if (!title || isTitleNoise(title)) {
    return undefined;
  }

  return title;
}

function cleanContentString(value) {
  const cleaned = cleanString(value);
  if (!cleaned || isNoiseText(cleaned)) {
    return undefined;
  }

  return cleaned;
}

function cleanImageUrl(value) {
  const url = cleanString(extractImageUrlValue(value));
  if (!url || IMAGE_NOISE_PATTERN.test(normalizeComparableText(url))) {
    return undefined;
  }

  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return undefined;
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return undefined;
  }

  parsed.protocol = 'https:';
  return parsed.toString();
}

function extractImageUrlValue(value) {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(extractImageUrlValue).find(Boolean);
  }

  if (!value || typeof value !== 'object') {
    return undefined;
  }

  return extractImageUrlValue(
    value.url ??
    value.contentUrl ??
    value.thumbnailUrl ??
    value.thumbnail ??
    value.image,
  );
}

function cleanString(value) {
  if (typeof value !== 'string') {
    return undefined;
  }

  const cleaned = value.replace(/\s+/g, ' ').trim();
  return cleaned || undefined;
}

function normalizeApostrophes(value) {
  return value.replace(/([A-Za-zÀ-ÿ])'([A-Za-zÀ-ÿ])/g, '$1’$2');
}

function normalizeComparableText(value) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function isTitleNoise(value) {
  return /\b(partenaires?|cookies?|consentement|publicite|confidentialite)\b/.test(normalizeComparableText(value));
}

function isNoiseText(value) {
  const cleaned = cleanString(value);
  return Boolean(cleaned && HARD_NOISE_PATTERN.test(normalizeComparableText(cleaned)));
}

function isUsefulValue(value) {
  if (value === undefined || value === null) {
    return false;
  }

  if (Array.isArray(value)) {
    return value.length > 0;
  }

  return true;
}

const HARD_NOISE_PATTERN = /\b(partenaires?|cookies?|rgpd|privacy|ustensiles?|equipements?|materiels?|casseroles?|four top|fouets?|fouet cuisine|balance(?: de cuisine)?|acheter|details?|amazon|top des meilleurs|voir toutes les recettes|marmiton mag|commentaires?|publicite|newsletter)\b.*$/i;
const IMAGE_NOISE_PATTERN = /\b(logo|banner|banniere|advert|publicite|ads?|cookie|consent|consentement|partenaires?|sprite|icon|favicon|placeholder)\b|\.svg(?:[?#]|$)/;
const INGREDIENT_DISPLAY_UNITS = new Set([
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
