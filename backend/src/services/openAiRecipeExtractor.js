const OPENAI_MODEL = process.env.OPENAI_MODEL ?? 'gpt-4.1-mini';
const OPENAI_API_URL = process.env.OPENAI_API_URL ?? 'https://api.openai.com/v1/chat/completions';
const OPENAI_TIMEOUT_MS = 20_000;

const recipeJsonSchema = {
  name: 'chefbase_recipe_import',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      title: { type: 'string' },
      description: { type: 'string' },
      ingredients: {
        type: 'array',
        items: { type: 'string' },
      },
      instructions: {
        type: 'array',
        items: { type: 'string' },
      },
      prepTime: { type: 'string' },
      cookTime: { type: 'string' },
      servings: { type: 'integer' },
      imageUrl: { type: 'string' },
      category: { type: 'string' },
      notes: { type: 'string' },
    },
    required: [
      'title',
      'description',
      'ingredients',
      'instructions',
      'prepTime',
      'cookTime',
      'servings',
      'imageUrl',
      'category',
      'notes',
    ],
  },
};

export async function extractRecipeWithOpenAi({ url, pageContent }) {
  const response = await fetch(OPENAI_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      temperature: 0.1,
      response_format: {
        type: 'json_schema',
        json_schema: recipeJsonSchema,
      },
      messages: [
        {
          role: 'system',
          content:
            'Extract ONLY the actual recipe from the provided webpage data. Ignore cookie banners, consent text, ads, partner text, utensils, affiliate shopping text, site navigation, comments, and newsletter content. ' +
            'Return strict JSON matching the schema: title, description, ingredients, instructions, prepTime, cookTime, servings, imageUrl, category, notes. ' +
            'Ingredients must be clean display strings such as "125 g farine", "200 g chocolat noir", or "4 œufs"; do not return merged blocks or shopping/utensil lines. ' +
            'Instructions must be complete cooking steps only, in order, without "Étape X", metadata, comments, or section labels. ' +
            'The title must be the actual recipe title, never cookie, partner, consent, or personal data text. ' +
            'imageUrl must be the real food image if identifiable; otherwise return an empty string. ' +
            'If the recipe is missing a field, return an empty string, empty array, or 0 for servings.',
        },
        {
          role: 'user',
          content: JSON.stringify({
            url: pageContent.pageUrl || url,
            requestedUrl: url,
            title: pageContent.pageTitle,
            jsonLd: pageContent.jsonLd,
            visibleText: pageContent.visibleText,
            imageCandidates: pageContent.imageCandidates,
          }),
        },
      ],
    }),
    signal: AbortSignal.timeout(OPENAI_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(`OpenAI request failed with status ${response.status}.`);
  }

  const payload = await response.json();
  const content = payload.choices?.[0]?.message?.content;
  if (typeof content !== 'string' || !content.trim()) {
    throw new Error('OpenAI response did not contain JSON content.');
  }

  const parsed = JSON.parse(content);
  return {
    ...parsed,
    categories: parsed.category ? [parsed.category] : undefined,
  };
}
