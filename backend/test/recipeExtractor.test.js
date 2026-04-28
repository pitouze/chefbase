import assert from 'node:assert/strict';
import { test } from 'node:test';

import { extractRecipeFromUrl } from '../src/services/recipeExtractor.js';

test('imports Marmiton-like JSON-LD from fast HTTP without Playwright or OpenAI', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Cake rapide aux pommes',
    prepTime: 'PT1H',
    cookTime: 'PT20M',
    image: [
      'https://example.com/logo.svg',
      {
        '@type': 'ImageObject',
        url: 'https://example.com/cake-pommes.jpg',
        width: 1200,
        height: 800,
      },
    ],
    recipeIngredient: [
      '200 g farine',
      '3 pommes',
      '100 g sucre',
      '1 sachet levure',
      'Acheter casserole détails',
      'Top des meilleurs fouets',
    ],
    recipeInstructions: [
      { '@type': 'HowToStep', text: 'Étape 1 Mélanger la farine, le sucre et la levure.' },
      { '@type': 'HowToStep', text: 'Étape 2 Ajouter les pommes.' },
      { '@type': 'HowToStep', text: 'Verser dans un moule et cuire 20 min.' },
    ],
  };

  globalThis.fetch = async (url) => {
    assert.equal(
      url,
      'https://www.marmiton.org/recettes/recette_cake-rapide.aspx',
    );

    return new Response(`<!doctype html>
      <html>
        <head>
          <title>Cookies et partenaires</title>
          <script type="application/ld+json">${JSON.stringify(recipeJsonLd)}</script>
        </head>
        <body>
          <div>1100 partenaires utilisent des cookies.</div>
          <div>Acheter une casserole top meilleurs détails.</div>
        </body>
      </html>`, {
      status: 200,
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  };

  const result = await extractRecipeFromUrl(
    'https://www.marmiton.org/recettes/recette_cake-rapide.aspx',
  );

  assert.equal(result.title, 'Cake rapide aux pommes');
  assert.equal(result.prepTime, '1 h');
  assert.equal(result.cookTime, '20 min');
  assert.equal(result.imageUrl, 'https://example.com/cake-pommes.jpg');
  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.display),
    ['200 g farine', '3 pommes', '100 g sucre', '1 sachet levure'],
  );
  assert.deepEqual(result.instructions, [
    'Mélanger la farine, le sucre et la levure.',
    'Ajouter les pommes.',
    'Verser dans un moule et cuire 20 min.',
  ]);

  const serialized = JSON.stringify(result).toLowerCase();
  for (const forbidden of ['étape', 'cookies', 'partenaires', 'acheter', 'casserole', 'fouet', 'détails']) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('imports Marmiton-like JSON-LD @graph image from fast HTTP', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        name: 'Marmiton',
      },
      {
        '@type': 'Recipe',
        name: 'Gratin de courgettes',
        image: {
          '@type': 'ImageObject',
          thumbnail: {
            cdnUrl: 'https://assets.afcdn.com/recipe/20260428/145000_w1200h900c1cx2000cy1333.webp',
          },
        },
        recipeIngredient: ['3 courgettes', '2 œufs', '20 cl crème'],
        recipeInstructions: [
          { '@type': 'HowToStep', text: 'Couper les courgettes.' },
          { '@type': 'HowToStep', text: 'Mélanger les œufs et la crème.' },
          { '@type': 'HowToStep', text: 'Verser dans un plat et cuire 30 min.' },
        ],
      },
    ],
  };

  const result = await extractRecipeFromUrl('marmiton.org/recettes/recette_gratin-courgettes.aspx', {
    extractHttpPageContent: async (url) => {
      assert.equal(url, 'https://www.marmiton.org/recettes/recette_gratin-courgettes.aspx');
      return {
        pageUrl: url,
        pageTitle: 'Gratin de courgettes',
        jsonLd: [JSON.stringify(recipeJsonLd)],
        visibleText: '',
        imageCandidates: [],
      };
    },
    extractPageContent: async () => {
      throw new Error('Playwright should not be called.');
    },
  });

  assert.equal(result.title, 'Gratin de courgettes');
  assert.equal(
    result.imageUrl,
    'https://assets.afcdn.com/recipe/20260428/145000_w1200h900c1cx2000cy1333.webp',
  );
});

test('JSON-LD recipe without image uses og:image and returns from fast HTTP', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'test-key';
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  let fetchCount = 0;
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Tarte rapide aux tomates',
    recipeIngredient: ['1 pâte brisée', '4 tomates', '2 càs moutarde'],
    recipeInstructions: [
      { '@type': 'HowToStep', text: 'Préchauffer le four à 180°C.' },
      { '@type': 'HowToStep', text: 'Étaler la moutarde sur la pâte.' },
      { '@type': 'HowToStep', text: 'Ajouter les tomates et cuire 30 min.' },
    ],
  };

  globalThis.fetch = async (url) => {
    fetchCount += 1;
    assert.equal(url, 'https://example.com/recette/tarte-tomates');

    return new Response(`<!doctype html>
      <html>
        <head>
          <title>Tarte rapide aux tomates</title>
          <meta property="og:image" content="/images/tarte-tomates-1200x800.jpg">
          <meta name="twitter:image" content="/images/logo.svg">
          <script type="application/ld+json">${JSON.stringify(recipeJsonLd)}</script>
        </head>
      </html>`, {
      status: 200,
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  };

  const result = await extractRecipeFromUrl('https://example.com/recette/tarte-tomates');

  assert.equal(fetchCount, 1);
  assert.equal(result.title, 'Tarte rapide aux tomates');
  assert.equal(result.imageUrl, 'https://example.com/images/tarte-tomates-1200x800.jpg');
  assert.deepEqual(result.instructions, [
    'Préchauffer le four à 180°C.',
    'Étaler la moutarde sur la pâte.',
    'Ajouter les tomates et cuire 30 min.',
  ]);
});

test('og:image:secure_url fallback returns imageUrl', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const result = await extractRecipeFromUrl('https://example.com/recette/clafoutis', {
    extractHttpPageContent: async (url) => ({
      pageUrl: url,
      pageTitle: 'Clafoutis aux cerises',
      jsonLd: [
        JSON.stringify({
          '@context': 'https://schema.org',
          '@type': 'Recipe',
          name: 'Clafoutis aux cerises',
          recipeIngredient: ['500 g cerises', '3 œufs', '100 g farine'],
          recipeInstructions: [
            'Mélanger les œufs et la farine.',
            'Ajouter les cerises.',
            'Cuire 35 min.',
          ],
        }),
      ],
      visibleText: '',
      imageCandidates: [
        {
          src: 'https://example.com/images/clafoutis-1200x800.jpg',
          source: 'og-image',
        },
      ],
    }),
    extractPageContent: async () => {
      throw new Error('Playwright should not be called.');
    },
  });

  assert.equal(result.imageUrl, 'https://example.com/images/clafoutis-1200x800.jpg');
});

test('Playwright timeout does not fail if previous extraction has usable recipe', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const result = await extractRecipeFromUrl('https://example.com/recette/omelette', {
    extractHttpPageContent: async (url) => ({
      pageUrl: url,
      pageTitle: 'Omelette aux herbes',
      jsonLd: [],
      visibleText: [
        'Omelette aux herbes',
        'Ingrédients',
        '3 œufs',
        '1 pincée sel',
        '1 bouquet ciboulette',
        'Instructions',
        'Battre les œufs avec le sel.',
        'Ajouter la ciboulette.',
        'Cuire à la poêle 5 min.',
      ].join('\n'),
      imageCandidates: [
        {
          src: 'https://example.com/images/omelette-1200x800.jpg',
          source: 'html-img',
          width: 1200,
          height: 800,
        },
      ],
    }),
    extractPageContent: async () => {
      throw new Error('Playwright extraction timed out.');
    },
  });

  assert.equal(result.title, 'Omelette aux herbes');
  assert.equal(result.imageUrl, 'https://example.com/images/omelette-1200x800.jpg');
  assert.deepEqual(result.instructions, [
    'Battre les œufs avec le sel.',
    'Ajouter la ciboulette.',
    'Cuire à la poêle 5 min.',
  ]);
});

test('incomplete URL returns clear French error', async () => {
  await assert.rejects(
    () => extractRecipeFromUrl('/recettes/recette_cake.aspx'),
    {
      statusCode: 400,
      message: 'URL incomplète : colle le lien complet de la recette.',
    },
  );
});

test('valid JSON-LD does not call OpenAI', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'test-key';
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  let fetchCount = 0;
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Salade de pommes de terre',
    image: 'https://example.com/images/salade-pommes-de-terre.webp',
    recipeIngredient: ['500 g pommes de terre', '2 càs huile d’olive', '1 pincée sel'],
    recipeInstructions: [
      'Cuire les pommes de terre dans une casserole.',
      'Égoutter puis laisser tiédir.',
      'Ajouter l’huile, saler et servir.',
    ],
  };

  globalThis.fetch = async (url) => {
    fetchCount += 1;
    assert.equal(url, 'https://example.com/recette/salade');

    return new Response(`<!doctype html>
      <html>
        <head>
          <script type="application/ld+json">${JSON.stringify(recipeJsonLd)}</script>
        </head>
      </html>`, {
      status: 200,
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  };

  const result = await extractRecipeFromUrl('https://example.com/recette/salade');

  assert.equal(fetchCount, 1);
  assert.equal(result.imageUrl, 'https://example.com/images/salade-pommes-de-terre.webp');
});

test('valid JSON-LD does not call Playwright', async (t) => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;
  t.after(() => {
    if (originalOpenAiKey === undefined) {
      delete process.env.OPENAI_API_KEY;
    } else {
      process.env.OPENAI_API_KEY = originalOpenAiKey;
    }
  });

  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Soupe express aux légumes',
    image: 'https://example.com/images/soupe-legumes.png',
    recipeIngredient: ['3 carottes', '2 pommes de terre', '1 l bouillon'],
    recipeInstructions: [
      'Couper les légumes en morceaux.',
      'Mettre les légumes dans le bouillon.',
      'Cuire 25 min puis mixer.',
    ],
  };

  globalThis.fetch = async () => new Response(`<!doctype html>
    <html>
      <head>
        <script type="application/ld+json">${JSON.stringify(recipeJsonLd)}</script>
      </head>
    </html>`, {
    status: 200,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });

  const result = await extractRecipeFromUrl('https://example.com/recette/soupe');

  assert.equal(result.title, 'Soupe express aux légumes');
  assert.equal(result.imageUrl, 'https://example.com/images/soupe-legumes.png');
});
