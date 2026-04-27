import assert from 'node:assert/strict';
import { test } from 'node:test';

import { extractRecipeWithDeterministicParser } from '../src/services/deterministicRecipeExtractor.js';
import { normalizeRecipe } from '../src/utils/normalizeRecipe.js';

test('formats structured ingredients and cleans instruction steps deterministically', () => {
  const result = normalizeRecipe({
    ingredients: [
      '125 g farine',
      '4 œufs',
      { name: 'farine', quantity: 100, unit: 'grammes' },
      { name: "huile d'olive", quantity: 4, unit: 'cuillères' },
      { name: 'œufs', quantity: 4 },
      { name: 'sel' },
    ],
    instructions: [
      'Étape 1. Mélanger la farine. Mélanger la farine.',
      'Ajouter l’huile. Voir toutes les recettes Marmiton Mag',
      'Cuire 20 min.',
    ],
  });

  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.display),
    ['125 g farine', '4 œufs', '100 g farine', '4 càs huile d’olive', '4 œufs', 'sel'],
  );
  assert.deepEqual(result.instructions, [
    'Mélanger la farine.',
    'Ajouter l’huile.',
    'Cuire 20 min.',
  ]);
});

test('extracts clean Marmiton-like Recipe JSON-LD without page noise', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        name: 'Noisy page wrapper',
      },
      {
        '@type': ['Recipe'],
        name: 'Gâteau au yaourt',
        description: '<p>Un gâteau simple et moelleux.</p>',
        image: {
          '@type': 'ImageObject',
          url: '/images/gateau.jpg',
        },
        recipeYield: '6 personnes',
        prepTime: 'PT15M',
        cookTime: 'PT30M',
        recipeCategory: 'Dessert',
        recipeIngredient: [
          '125 g yaourt nature',
          '200 g sucre',
          '250 g farine',
          'Publicité Amazon ustensiles',
          'Cookies et confidentialité',
        ],
        recipeInstructions: [
          {
            '@type': 'HowToSection',
            name: 'Préparation',
            itemListElement: [
              {
                '@type': 'HowToStep',
                text: '<p>Préchauffer le four à 180°C.</p>',
              },
              {
                '@type': 'HowToStep',
                text: 'Mélanger le yaourt, le sucre et la farine.',
              },
            ],
          },
          {
            '@type': 'HowToStep',
            name: 'Verser dans un moule et cuire 30 min.',
          },
          'Voir toutes les recettes Marmiton Mag',
        ],
      },
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_gateau-au-yaourt.aspx',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      visibleText: [
        'Cookies',
        'Amazon',
        'Ingrédients',
        '999 g texte de navigation',
        'Préparation',
        'Voir toutes les recettes',
      ].join('\n'),
      pageTitle: 'Page title should not override JSON-LD',
      imageCandidates: [{ src: 'https://example.com/fallback.jpg' }],
    },
  });

  assert.equal(result.title, 'Gâteau au yaourt');
  assert.equal(
    result.imageUrl,
    'https://www.marmiton.org/images/gateau.jpg',
  );
  assert.deepEqual(result.categories, ['Dessert']);
  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.name),
    ['yaourt nature', 'sucre', 'farine'],
  );
  assert.equal(result.prepTime, '15 min');
  assert.equal(result.cookTime, '30 min');
  assert.deepEqual(result.instructions, [
    'Préchauffer le four à 180°C.',
    'Mélanger le yaourt, le sucre et la farine.',
    'Verser dans un moule et cuire 30 min.',
  ]);

  const serialized = JSON.stringify(result).toLowerCase();
  assert.equal(serialized.includes('cookies'), false);
  assert.equal(serialized.includes('amazon'), false);
  assert.equal(serialized.includes('ustensiles'), false);
  assert.equal(serialized.includes('voir toutes les recettes'), false);
  assert.equal(serialized.includes('999 g texte de navigation'), false);
});

test('converts schema.org ISO durations to French readable values', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Soupe de légumes',
    prepTime: 'PT20M',
    cookTime: 'PT1H30M',
    recipeIngredient: [
      '2 carottes',
      '1 pomme de terre',
      '1 l eau',
    ],
    recipeInstructions: [
      { '@type': 'HowToStep', text: 'Couper les légumes.' },
      { '@type': 'HowToStep', text: 'Cuire la soupe 1 h 30 min.' },
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://example.com/soupe',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      visibleText: '',
      pageTitle: '',
      imageCandidates: [],
    },
  });

  assert.equal(result.prepTime, '20 min');
  assert.equal(result.cookTime, '1 h 30 min');
});

test('prioritizes schema recipe fields over Marmiton consent, affiliate, and logo noise', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Moelleux au chocolat',
    image: [
      'https://www.marmiton.org/assets/logo-marmiton.svg',
      {
        '@type': 'ImageObject',
        url: 'https://www.marmiton.org/images/recette/moelleux-chocolat.jpg',
      },
    ],
    recipeCategory: ['Dessert', 'Gâteau'],
    recipeIngredient: [
      '125 g farine',
      '200 g chocolat noir',
      '150 g sucre',
      '4 œufs',
      '100 g beurre doux',
      '1 sachet levure',
      'Casserole',
      'Four top',
      'Fouet cuisine',
      'Balance de cuisine',
      'Acheter sur Amazon',
      'Top des meilleurs ustensiles',
    ],
    recipeInstructions: [
      { '@type': 'HowToStep', text: 'Étape 1 Faire fondre le chocolat avec le beurre.' },
      { '@type': 'HowToStep', text: 'Étape 2 Mélanger les œufs et le sucre.' },
      { '@type': 'HowToStep', text: 'Incorporer la farine et la levure.' },
      { '@type': 'HowToStep', text: 'Verser dans un moule et cuire 20 min.' },
      { '@type': 'HowToStep', text: 'Commentaires Marmiton Mag newsletter' },
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_moelleux-au-chocolat.aspx',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      pageTitle: '1100 partenaires',
      visibleText: [
        '1100 partenaires',
        'Marmiton et ses partenaires utilisent des cookies.',
        'Acheter une casserole sur Amazon',
        'Top des meilleurs fouets cuisine',
      ].join('\n'),
      imageCandidates: [
        {
          src: 'https://www.marmiton.org/assets/logo-marmiton.svg',
          alt: 'Marmiton logo',
          width: 640,
          height: 180,
        },
      ],
    },
  });

  assert.equal(result.title, 'Moelleux au chocolat');
  assert.equal(
    result.imageUrl,
    'https://www.marmiton.org/images/recette/moelleux-chocolat.jpg',
  );
  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.display),
    [
      '125 g farine',
      '200 g chocolat noir',
      '150 g sucre',
      '4 œufs',
      '100 g beurre doux',
      '1 sachet levure',
    ],
  );
  assert.deepEqual(result.instructions, [
    'Faire fondre le chocolat avec le beurre.',
    'Mélanger les œufs et le sucre.',
    'Incorporer la farine et la levure.',
    'Verser dans un moule et cuire 20 min.',
  ]);

  const serialized = JSON.stringify(result).toLowerCase();
  assert.equal(serialized.includes('partenaires'), false);
  assert.equal(serialized.includes('casserole'), false);
  assert.equal(serialized.includes('four top'), false);
  assert.equal(serialized.includes('fouet'), false);
  assert.equal(serialized.includes('balance'), false);
  assert.equal(serialized.includes('acheter'), false);
  assert.equal(serialized.includes('top des meilleurs'), false);
  assert.equal(serialized.includes('étape'), false);
  assert.equal(serialized.includes('commentaires'), false);
});

test('chooses the usable Recipe node from a noisy Marmiton JSON-LD graph', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        name: '1100 partenaires',
        recipeIngredient: [
          '1100 partenaires',
          'cookies',
          'données personnelles',
          'publicité',
        ],
        recipeInstructions: 'Accepter les cookies.',
      },
      {
        '@type': 'Article',
        name: '1100 partenaires',
      },
      {
        '@type': 'Organization',
        name: 'Marmiton',
      },
      {
        '@type': 'Recipe',
        name: '1100 partenaires',
        recipeIngredient: [
          'cookies',
          'publicité',
          'données personnelles',
          'tracking',
          'consentement',
        ],
        recipeInstructions: [
          { '@type': 'HowToStep', text: 'Utiliser les cookies.' },
          { '@type': 'HowToStep', text: 'Accepter les partenaires.' },
          { '@type': 'HowToStep', text: 'Valider le consentement.' },
        ],
      },
      {
        '@type': 'Recipe',
        name: 'Cake moelleux au citron',
        recipeIngredient: [
          '180 g farine',
          '3 œufs',
          '120 g sucre',
          '1 citron',
          '1 sachet levure',
        ],
        recipeInstructions: [
          { '@type': 'HowToStep', text: 'Mélanger les œufs et le sucre.' },
          { '@type': 'HowToStep', text: 'Ajouter la farine, la levure et le citron.' },
          { '@type': 'HowToStep', text: 'Cuire le cake 35 min.' },
        ],
      },
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_cake-moelleux-citron.aspx',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      pageTitle: '1100 partenaires',
      visibleText: '1100 partenaires\nMarmiton et ses partenaires utilisent des cookies.',
      imageCandidates: [],
    },
  });

  assert.notEqual(result.title, '1100 partenaires');
  assert.equal(result.title.toLowerCase().includes('partenaires'), false);
  assert.match(result.title, /cake|moelleux|gâteau|gateau|cuire|recette/i);
  assert.equal(result.title, 'Cake moelleux au citron');
  assert.deepEqual(result.instructions, [
    'Mélanger les œufs et le sucre.',
    'Ajouter la farine, la levure et le citron.',
    'Cuire le cake 35 min.',
  ]);
});

test('cuts ingredient strings at Marmiton shopping and utensil garbage', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Cake moelleux aux œufs',
    recipeIngredient: [
      '4 œufs 1 casserole Top 3 meilleurs ustensiles acheter détails',
      '200 g farine casserole Top 2',
      '120 g sucre acheter en promotion',
      '1 sachet levure balance de cuisine',
    ],
    recipeInstructions: [
      { '@type': 'HowToStep', text: 'Mélanger les ingrédients.' },
      { '@type': 'HowToStep', text: 'Cuire le cake 35 min.' },
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_cake-moelleux-oeufs.aspx',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      visibleText: '',
      pageTitle: '1100 partenaires',
      imageCandidates: [],
    },
  });

  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.display),
    ['4 œufs', '200 g farine', '120 g sucre', '1 sachet levure'],
  );

  const ingredientText = JSON.stringify(result.ingredients).toLowerCase();
  for (const forbidden of ['casserole', 'top', 'acheter']) {
    assert.equal(ingredientText.includes(forbidden), false);
  }
});

test('uses only Marmiton Recipe JSON-LD and never rebuilds from noisy visible HTML', () => {
  const recipeJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    name: 'Cake moelleux aux olives',
    headline: '1100 partenaires',
    image: [
      'https://www.marmiton.org/assets/logo-marmiton.svg',
      {
        '@type': 'ImageObject',
        url: 'https://www.marmiton.org/images/small-cake.jpg',
        width: 120,
        height: 90,
      },
      {
        '@type': 'ImageObject',
        url: 'https://www.marmiton.org/images/large-cake.jpg',
        width: 1200,
        height: 800,
      },
      {
        '@type': 'ImageObject',
        url: 'https://www.marmiton.org/images/medium-cake.jpg',
        width: 640,
        height: 427,
      },
    ],
    recipeCategory: 'Cake',
    recipeIngredient: [
      '200 g farine',
      '3 œufs',
      '10 cl huile d’olive',
      '1 sachet levure',
      'four',
      'casserole',
      'fouet',
      'balance de cuisine',
      'top des meilleurs moules',
      'acheter olives en promotion',
    ],
    recipeInstructions: [
      'Étape 1 Préchauffer le four à 180°C.',
      { '@type': 'HowToStep', text: 'Étape 2 Mélanger la farine, les œufs et l’huile.' },
      { '@type': 'HowToStep', text: 'Étape 2 Mélanger la farine, les œufs et l’huile.' },
      {
        '@type': 'HowToSection',
        itemListElement: [
          { '@type': 'HowToStep', name: 'Incorporer la levure.' },
          { '@type': 'HowToStep', text: 'Verser dans un moule et cuire 40 min.' },
        ],
      },
      '',
    ],
  };

  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_cake-moelleux-aux-olives.aspx',
    pageContent: {
      jsonLd: [JSON.stringify(recipeJsonLd)],
      pageTitle: '1100 partenaires',
      visibleText: [
        '1100 partenaires',
        'Marmiton et ses partenaires utilisent des cookies et des données.',
        'Ingrédients',
        '999 g publicité',
        'acheter une casserole',
        'top des meilleurs fouets',
        'Préparation',
        'Texte visible qui ne doit jamais être utilisé',
      ].join('\n'),
      imageCandidates: [
        {
          src: 'https://www.marmiton.org/assets/logo-marmiton.svg',
          alt: 'logo',
          width: 1200,
          height: 300,
        },
      ],
    },
  });

  assert.match(result.title, /moelleux|cake/i);
  assert.equal(result.title, 'Cake moelleux aux olives');
  assert.equal(result.imageUrl, 'https://www.marmiton.org/images/large-cake.jpg');
  assert.deepEqual(
    result.ingredients.map((ingredient) => ingredient.display),
    [
      '200 g farine',
      '3 œufs',
      '10 cl huile d’olive',
      '1 sachet levure',
    ],
  );
  assert.deepEqual(result.instructions, [
    'Préchauffer le four à 180°C.',
    'Mélanger la farine, les œufs et l’huile.',
    'Incorporer la levure.',
    'Verser dans un moule et cuire 40 min.',
  ]);

  const ingredientText = JSON.stringify(result.ingredients).toLowerCase();
  assert.equal(ingredientText.includes('four'), false);

  const serialized = JSON.stringify(result).toLowerCase();
  for (const forbidden of ['casserole', 'fouet', 'balance', 'top', 'acheter', '999 g publicité']) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('cleans real noisy Marmiton visible output without OpenAI', () => {
  const result = extractRecipeWithDeterministicParser({
    url: 'https://www.marmiton.org/recettes/recette_cake-aux-olives_12345.aspx',
    pageContent: {
      jsonLd: [],
      pageTitle: 'Marmiton et ses partenaires',
      visibleText: [
        'Marmiton et ses partenaires utilisent des cookies pour mesurer l’audience et personnaliser les contenus.',
        'Cake aux olives',
        'Très facile',
        'Bon marché',
        'Temps total',
        '1 h 10 min',
        'Préparation',
        '20 min',
        'Repos',
        '10 min',
        'Cuisson',
        '40 min',
        'Ingrédients',
        'personnes',
        '100',
        'g',
        'farine',
        '3',
        'oeufs',
        '10',
        'cl',
        "huile d'olive",
        '165',
        'g',
        'gruyère râpé',
        '1',
        'sachet',
        'levure',
        '200',
        'g',
        'olives vertes',
        '200',
        'g',
        'olives noires',
        '10',
        'cl',
        'lait',
        'de',
        "d'",
        'Top',
        'ustensiles',
        'Amazon',
        'Préparation',
        'Temps total',
        'Repos',
        'Cuisson',
        'Étape 1',
        'Préchauffer le four à 180°C.',
        'Étape 2',
        'Mélanger la farine, les oeufs et le lait.',
        'Étape 3',
        "Rajouter l'huile d'olive.",
        'Étape 4',
        'Incorporer le gruyère râpé et les olives.',
        'Étape 5',
        'Beurrer un moule à cake.',
        'Étape 6',
        'Enfourner 40 min.',
        'Étape 7',
        'Sortir le cake du four et laisser tiédir.',
        'commentaires',
      ].join('\n'),
      imageCandidates: [],
    },
  });

  assert.notEqual(result.title, 'Marmiton et ses partenaires');
  assert.equal(result.title, 'Cake aux olives');
  assert.equal(JSON.stringify(result).toLowerCase().includes('cookies'), false);
  assert.notEqual(result.servings, 110);
  assert.deepEqual(result.ingredients, [
    { name: 'farine', quantity: 100, unit: 'g', display: '100 g farine' },
    { name: 'oeufs', quantity: 3, display: '3 oeufs' },
    { name: 'huile d’olive', quantity: 10, unit: 'cl', display: '10 cl huile d’olive' },
    { name: 'gruyère râpé', quantity: 165, unit: 'g', display: '165 g gruyère râpé' },
    { name: 'levure', quantity: 1, unit: 'sachet', display: '1 sachet levure' },
    { name: 'olives vertes', quantity: 200, unit: 'g', display: '200 g olives vertes' },
    { name: 'olives noires', quantity: 200, unit: 'g', display: '200 g olives noires' },
    { name: 'lait', quantity: 10, unit: 'cl', display: '10 cl lait' },
  ]);
  assert.deepEqual(result.instructions, [
    'Préchauffer le four à 180°C.',
    'Mélanger la farine, les oeufs et le lait.',
    'Rajouter l’huile d’olive.',
    'Incorporer le gruyère râpé et les olives.',
    'Beurrer un moule à cake.',
    'Enfourner 40 min.',
    'Sortir le cake du four et laisser tiédir.',
  ]);
  assert.equal(result.instructions.includes('Étape 1'), false);
  assert.equal(result.instructions.includes('Temps total'), false);
});
