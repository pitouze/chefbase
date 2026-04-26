# Backend Recipe Import

Standalone Node/Express backend for universal recipe import. It uses Playwright to load a recipe page in a real browser, extracts page content, then uses AI-based structured extraction for Marmiton/noisy pages when configured before falling back to a deterministic parser.

## What It Does

- `POST /import-recipe`
- request body: `{ "url": "https://..." }`
- Playwright extraction:
  - page title
  - JSON-LD blocks
  - visible page text
  - image candidates
- recipe normalization output:

```json
{
  "title": "Quiche Lorraine",
  "description": "Classic savory tart with bacon and cream.",
  "ingredients": [
    { "name": "lardons", "quantity": 200, "unit": "g" }
  ],
  "instructions": ["Preheat the oven.", "Bake until golden."],
  "prepTime": "20 min",
  "cookTime": "35 min",
  "servings": 6,
  "imageUrl": "https://example.com/quiche.jpg",
  "notes": "Serve warm.",
  "categories": ["Main course", "French"]
}
```

Unknown or empty fields are omitted from the response.

## Install

From the project root:

```bash
cd backend
npm install
```

Playwright may ask for browser installation on first use. If needed:

```bash
npx playwright install chromium
```

## Run Locally

```bash
cd backend
npm start
```

Default port:

```bash
http://localhost:8787
```

Health check:

```bash
curl http://localhost:8787/health
```

Recipe import:

```bash
curl -X POST http://localhost:8787/import-recipe \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.marmiton.org/recettes/recette_quiche-lorraine_30289.aspx"}'
```

## Deploy to Render

Create a new Render Web Service from this repository and use these settings:

- Root directory: `backend`
- Build command: `npm install && npx playwright install --with-deps`
- Start command: `npm start`
- Environment variables:
  - `OPENAI_API_KEY`: your OpenAI API key
  - `OPENAI_MODEL`: the model to use, for example `gpt-4.1-mini`

The server listens on `process.env.PORT` and `0.0.0.0`, so Render can route public traffic to it. After deployment, verify:

```bash
curl https://your-service.onrender.com/health
```

Flutter should point at the deployed service URL, for example:

```bash
flutter build ios --dart-define=CHEFBASE_BACKEND_URL=https://your-service.onrender.com
```

## OpenAI Configuration

If `OPENAI_API_KEY` is present, the backend sends extracted page content to OpenAI and requests strict JSON output. Marmiton pages and pages polluted by cookie/partner/personal-data consent text use OpenAI cleanup first. Without a key, deterministic parsing is used as a fallback; if that output is still polluted, the route returns:

```json
{ "error": "Import incomplet : ce site nécessite l’import IA." }
```

Example:

```bash
export OPENAI_API_KEY="<your-openai-api-key>"
export OPENAI_MODEL="gpt-4.1-mini"
```

Recommended model:

```bash
export OPENAI_MODEL="gpt-4.1-mini"
```

Restart the backend after changing environment variables:

```bash
cd backend
npm start
```

If a backend process is already running, stop it first with `Ctrl+C`, then start it again. In development mode, restart the `npm run dev` process the same way.

## Flutter Integration

Flutter calls:

```text
POST https://your-service.onrender.com/import-recipe
Content-Type: application/json
```

with:

```json
{ "url": "https://..." }
```

Set the production backend URL with `CHEFBASE_BACKEND_URL` via `--dart-define`.

## Validation

Basic syntax validation:

```bash
cd backend
npm test
npm run check
```
