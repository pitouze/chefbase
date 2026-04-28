import { chromium } from 'playwright';

const NAVIGATION_TIMEOUT_MS = 12_000;
const PAGE_WAIT_AFTER_LOAD_MS = 500;
const MAX_VISIBLE_TEXT_LENGTH = 24_000;

export async function extractPageContent(url) {
  const browser = await chromium.launch({
    headless: true,
  });

  try {
    const context = await browser.newContext({
      locale: 'fr-FR',
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 ChefBaseImportBot/1.0',
      viewport: { width: 1440, height: 2200 },
    });

    const page = await context.newPage();
    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: NAVIGATION_TIMEOUT_MS,
    });

    await page.waitForLoadState('networkidle', {
      timeout: 2_000,
    }).catch(() => {});
    await page.waitForTimeout(PAGE_WAIT_AFTER_LOAD_MS);

    const extracted = await page.evaluate(({ maxVisibleTextLength }) => {
      const resolveImageUrl = (value) => {
        if (!value) {
          return '';
        }

        try {
          return new URL(value, window.location.href).toString();
        } catch {
          return '';
        }
      };

      const jsonLd = Array.from(
        document.querySelectorAll('script[type="application/ld+json"]'),
      )
        .map((node) => node.textContent?.trim())
        .filter(Boolean);

      const selectorsToDrop = [
        'script',
        'style',
        'noscript',
        'svg',
        'nav',
        'footer',
        'header',
        'form',
        'iframe',
        '[aria-hidden="true"]',
        '[hidden]',
        '.cookie',
        '.cookies',
        '#cookie',
        '#cookies',
        '.advert',
        '.ads',
      ];

      for (const selector of selectorsToDrop) {
        for (const node of document.querySelectorAll(selector)) {
          node.remove();
        }
      }

      const metaImageCandidates = Array.from(document.querySelectorAll('meta[property], meta[name]'))
        .map((meta) => ({
          key: (meta.getAttribute('property') || meta.getAttribute('name') || '').toLowerCase(),
          content: meta.getAttribute('content') || '',
        }))
        .filter((meta) => ['og:image', 'og:image:url', 'twitter:image', 'twitter:image:src'].includes(meta.key))
        .map((meta) => ({
          src: resolveImageUrl(meta.content),
          alt: '',
          width: 0,
          height: 0,
          source: meta.key.startsWith('og:') ? 'og:image' : 'twitter:image',
        }))
        .filter((image) => image.src);

      const linkImageCandidates = Array.from(document.querySelectorAll('link[rel]'))
        .filter((link) => (link.getAttribute('rel') || '').toLowerCase().split(/\s+/).includes('image_src'))
        .map((link) => ({
          src: resolveImageUrl(link.getAttribute('href') || ''),
          alt: '',
          width: 0,
          height: 0,
          source: 'link:image_src',
        }))
        .filter((image) => image.src);

      const htmlImageCandidates = Array.from(document.images)
        .map((image) => ({
          src: image.currentSrc || image.src || '',
          alt: image.alt?.trim() || '',
          width: Number(image.naturalWidth || image.width || 0),
          height: Number(image.naturalHeight || image.height || 0),
          source: 'html-img',
        }))
        .filter((image) => image.src)
        .sort((left, right) => (right.width * right.height) - (left.width * left.height))
        .slice(0, 12);

      const imageCandidates = [
        ...metaImageCandidates,
        ...linkImageCandidates,
        ...htmlImageCandidates,
      ].slice(0, 12);

      const textNodes = [];
      const walker = document.createTreeWalker(document.body ?? document.documentElement, NodeFilter.SHOW_TEXT);

      while (walker.nextNode()) {
        const text = walker.currentNode.textContent?.replace(/\s+/g, ' ').trim();
        const parent = walker.currentNode.parentElement;
        if (!text || !parent) {
          continue;
        }

        const style = window.getComputedStyle(parent);
        if (
          style.display === 'none' ||
          style.visibility === 'hidden' ||
          parent.closest('script, style, noscript')
        ) {
          continue;
        }

        textNodes.push(text);
      }

      const uniqueLines = [];
      const seen = new Set();
      for (const line of textNodes) {
        if (seen.has(line)) {
          continue;
        }
        seen.add(line);
        uniqueLines.push(line);
      }

      return {
        pageTitle: document.title?.trim() || '',
        pageUrl: window.location.href,
        jsonLd,
        visibleText: uniqueLines.join('\n').slice(0, maxVisibleTextLength),
        imageCandidates,
      };
    }, { maxVisibleTextLength: MAX_VISIBLE_TEXT_LENGTH });

    await context.close();

    return extracted;
  } finally {
    await browser.close();
  }
}
