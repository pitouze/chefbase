import { chromium } from 'playwright';

const NAVIGATION_TIMEOUT_MS = 30_000;
const PAGE_WAIT_AFTER_LOAD_MS = 1_500;
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
      timeout: 10_000,
    }).catch(() => {});
    await page.waitForTimeout(PAGE_WAIT_AFTER_LOAD_MS);

    const extracted = await page.evaluate(({ maxVisibleTextLength }) => {
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

      const imageCandidates = Array.from(document.images)
        .map((image) => ({
          src: image.currentSrc || image.src || '',
          alt: image.alt?.trim() || '',
          width: Number(image.naturalWidth || image.width || 0),
          height: Number(image.naturalHeight || image.height || 0),
        }))
        .filter((image) => image.src)
        .sort((left, right) => (right.width * right.height) - (left.width * left.height))
        .slice(0, 12);

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
