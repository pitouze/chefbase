const MAX_HTML_LENGTH = 1_500_000;
const MAX_VISIBLE_TEXT_LENGTH = 24_000;

export async function extractHttpPageContent(url) {
  const response = await fetch(url, {
    headers: {
      accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'fr-FR,fr;q=0.9,en;q=0.7',
      'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 ChefBaseImportBot/1.0',
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(4_000),
  });

  if (!response.ok) {
    throw new Error(`HTTP fetch failed with status ${response.status}.`);
  }

  const contentType = response.headers.get('content-type') ?? '';
  if (contentType && !contentType.toLowerCase().includes('html')) {
    throw new Error(`HTTP fetch returned unsupported content type: ${contentType}.`);
  }

  const html = (await response.text()).slice(0, MAX_HTML_LENGTH);
  return extractPageContentFromHtml({
    html,
    url: response.url || url,
  });
}

export function extractPageContentFromHtml({ html, url }) {
  const source = String(html ?? '');
  const withoutDroppedNodes = source
    .replace(/<script\b(?![^>]*type=["']application\/ld\+json["'])[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<svg\b[\s\S]*?<\/svg>/gi, ' ');

  return {
    pageTitle: extractTitle(source),
    pageUrl: url,
    jsonLd: extractJsonLdBlocks(source),
    visibleText: htmlToVisibleText(withoutDroppedNodes).slice(0, MAX_VISIBLE_TEXT_LENGTH),
    imageCandidates: extractImageCandidates(source, url),
  };
}

function extractJsonLdBlocks(html) {
  return [...html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)]
    .map((match) => decodeHtmlEntities(match[1]).trim())
    .filter(Boolean);
}

function extractTitle(html) {
  const match = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  return cleanText(match?.[1]) ?? '';
}

function htmlToVisibleText(html) {
  const lines = decodeHtmlEntities(html)
    .replace(/<\/(?:p|li|div|section|article|h[1-6]|tr)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]*>/g, ' ')
    .split('\n')
    .map(cleanText)
    .filter(Boolean);

  const uniqueLines = [];
  const seen = new Set();
  for (const line of lines) {
    if (seen.has(line)) {
      continue;
    }

    seen.add(line);
    uniqueLines.push(line);
  }

  return uniqueLines.join('\n');
}

function extractImageCandidates(html, baseUrl) {
  const metaCandidates = [
    ...extractMetaImageCandidates(html, baseUrl),
    ...extractLinkImageCandidates(html, baseUrl),
  ];
  const imgCandidates = [...html.matchAll(/<img\b[^>]*>/gi)]
    .map((match) => {
      const attributes = parseAttributes(match[0]);
      return {
        src: resolveUrl(attributes.src ?? attributes['data-src'] ?? attributes.srcset?.split(/\s+/)[0], baseUrl),
        alt: attributes.alt ?? '',
        width: Number.parseInt(attributes.width ?? '0', 10) || 0,
        height: Number.parseInt(attributes.height ?? '0', 10) || 0,
        source: 'html-img',
      };
    })
    .filter((image) => image.src)
    .sort((left, right) => (right.width * right.height) - (left.width * left.height));

  return [...metaCandidates, ...imgCandidates]
    .slice(0, 12);
}

function extractMetaImageCandidates(html, baseUrl) {
  return [...html.matchAll(/<meta\b[^>]*>/gi)]
    .map((match) => parseAttributes(match[0]))
    .map((attributes) => {
      const key = (attributes.property ?? attributes.name ?? '').toLowerCase();
      if (!['og:image', 'og:image:url', 'og:image:secure_url', 'twitter:image', 'twitter:image:src'].includes(key)) {
        return null;
      }

      return {
        src: resolveUrl(attributes.content, baseUrl),
        alt: attributes.alt ?? '',
        width: 0,
        height: 0,
        source: key.startsWith('og:') ? 'og-image' : 'twitter-image',
      };
    })
    .filter((image) => image?.src);
}

function extractLinkImageCandidates(html, baseUrl) {
  return [...html.matchAll(/<link\b[^>]*>/gi)]
    .map((match) => parseAttributes(match[0]))
    .map((attributes) => {
      const rels = String(attributes.rel ?? '').toLowerCase().split(/\s+/);
      if (!rels.includes('image_src')) {
        return null;
      }

      return {
        src: resolveUrl(attributes.href, baseUrl),
        alt: '',
        width: 0,
        height: 0,
        source: 'link:image_src',
      };
    })
    .filter((image) => image?.src);
}

function parseAttributes(tag) {
  return Object.fromEntries(
    [...tag.matchAll(/\s([a-zA-Z_:.-]+)(?:=(["'])(.*?)\2|=([^\s>]+))?/g)].map((match) => [
      match[1].toLowerCase(),
      decodeHtmlEntities(match[3] ?? match[4] ?? ''),
    ]),
  );
}

function resolveUrl(value, baseUrl) {
  if (!value) {
    return '';
  }

  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return '';
  }
}

function cleanText(value) {
  const cleaned = decodeHtmlEntities(String(value ?? ''))
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned || null;
}

function decodeHtmlEntities(value) {
  return String(value ?? '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'");
}
