# Render Free Deployment

This bridge can run on Render Free as a small Node web service.

## Service setup

- Service type: `Web Service`
- Instance type: `Free`
- Root directory: `youtube-extractor-bridge`
- Build command: `npm install`
- Start command: `npm run start`

## Why this works

- Local development stays on `npm run dev`
- Production startup stays on `npm run start`
- `npm run start` triggers `prestart`, which builds TypeScript before launching `dist/server.js`
- The server listens on `process.env.PORT` when Render injects one
- Local fallback remains `8080`

## Environment variables

Required:

- none

Optional:

- `NODE_ENV=production`
- `YT_DLP_PYTHON_PATH`
- `HOST`

Notes:

- Do not set `PORT` manually on Render. Render provides it automatically.
- Do not commit a real `.env` file.
- `.env.example` is only a local template.

## Health check

- Health check path: `/health`
- Expected full URL pattern: `https://<your-render-service>.onrender.com/health`
- Expected response:

```json
{
  "ok": true,
  "service": "youtube-extractor-bridge"
}
```

## Local pre-deploy checks

From the repo root:

```bash
cd youtube-extractor-bridge
npm install
npm test
npm run start
```

In another terminal:

```bash
curl http://127.0.0.1:8080/health
```

If you want to verify the production-style resolve route too:

```bash
curl -X POST http://127.0.0.1:8080/resolve \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}'
```

## Phase 8 pass criteria

Phase 8 is a pass when all of the following are true:

- `npm install` succeeds
- `npm test` succeeds
- `npm run dev` remains usable for local development
- `npm run start` launches the production server
- `GET /health` returns the expected JSON
- Render can build with `npm install`
- Render can start with `npm run start`
- The deployed service responds at `https://<your-render-service>.onrender.com/health`
