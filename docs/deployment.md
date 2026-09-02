# Deployment (Issue 26)

HireFlow AI ships as three containers:

| Service    | What it is                          | Built from             | Port |
|------------|--------------------------------------|-------------------------|------|
| `api`      | FastAPI backend + LangGraph agents   | `Dockerfile` (root)     | 8000 |
| `db`       | PostgreSQL 16                        | `postgres:16-alpine`    | 5432 |
| `frontend` | React (Vite) dashboard, static build | `frontend/Dockerfile`   | 3000 |

## 1. Local Docker (verified working)

```bash
cp .env.example .env
# Fill in at least LLM_PROVIDER and one matching API key (e.g. GROQ_API_KEY).
# DATABASE_URL in .env is for host-side (non-Docker) dev only — inside
# docker-compose, api's DATABASE_URL is overridden to point at the `db`
# service (see docker-compose.yml). You don't need to edit it for Docker.

docker compose up --build
```

What happens on `up`:
1. `db` starts and waits until `pg_isready` passes (compose healthcheck) before `api` is allowed to start.
2. `api`'s container entrypoint runs `alembic upgrade head` against the `db` service, then starts uvicorn — so a brand-new Postgres volume ends up with a real schema, not an empty database.
3. `frontend` is a two-stage build: `npm ci && npm run build` in a `node:20-alpine` builder, then the static `dist/` output is served by `serve` in a second `node:20-alpine` stage on port 3000. The API base URL is baked into the JS bundle at build time via the `VITE_API_BASE_URL` build arg in `docker-compose.yml` (Vite inlines `VITE_*` vars at compile time — an `env_file` on the running container has no effect on already-built JS, which is why `frontend` does not use `env_file`).

Verify:
```bash
curl http://localhost:8000/docs    # FastAPI Swagger UI
open http://localhost:3000         # React dashboard
psql "postgresql://postgres:password@localhost:5432/hireflow" -c '\dt'
```

Known constraint: the root `Dockerfile` installs `texlive-xetex` + `texlive-latex-extra` (LaTeX for resume PDFs) and Playwright's Chromium (for scraping/form-filling), so the `api` image is large (~14GB) and the first build takes several minutes. Two things kept this from working at all before this fix, both addressed in the Dockerfile:
- `texlive-fonts-extra` isn't used by `src/templates/resume_latex/base_template.tex` and its font-cache postinstall step is heavy enough to OOM the build under Docker Desktop's default VM memory limit — removed.
- Installing without `--no-install-recommends` pulled in ~600MB of unrelated packages (a JRE, GTK, X11, a full DVI/PS toolchain) that a headless xelatex build never touches, which was enough extra `apt-get` time to make the build vulnerable to a mid-install network blip — fixed by adding the flag.

Verified end-to-end on 2026-09-02: `docker compose up --build` → `db` passes its healthcheck → `api` runs `alembic upgrade head` (all 7 tables created on a fresh volume) and serves `/docs` with `200` → `frontend` serves the built SPA on `:3000` with `200`.

## 2. Environment variables

All variables live in `.env.example` at the repo root; copy it to `.env`. The important ones for a working deploy:

| Variable | Required | Notes |
|---|---|---|
| `LLM_PROVIDER` | Yes | `groq`, `gemini`, `openai`, `anthropic`, or `ollama`. |
| `GROQ_API_KEY` / `GOOGLE_API_KEY` / `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | One, matching `LLM_PROVIDER` | Free tier: Groq or Gemini. |
| `DATABASE_URL` | Yes | Host-side value in `.env`; the platform's Postgres connection string in production (see below). |
| `TAVILY_API_KEY` | Optional | Company intel / resource search falls back gracefully without it. |
| `SENDGRID_API_KEY` / `RESEND_API_KEY` | Optional | Weekly report emails; skipped without it. |
| `SECRET_KEY` | Yes | Set to a real random value in production — never reuse the `.env.example` placeholder. |
| `ALLOWED_ORIGINS` | Yes | CORS — set to the deployed frontend's real URL in production. |
| `VITE_API_BASE_URL` (frontend build arg, not `.env`) | Yes | The API's public URL, baked into the frontend at build time. |

## 3. Deploying to Railway

Railway can run all three services as one project.

1. **Create the project** from this GitHub repo (`railway login`, then `railway init` or via the Railway dashboard → New Project → Deploy from GitHub repo).
2. **Add a Postgres plugin**: New → Database → PostgreSQL. Railway injects `DATABASE_URL` automatically into services attached to it — attach it to the `api` service.
3. **`api` service**: point it at the repo root (uses the root `Dockerfile`). Set env vars from the table above (`LLM_PROVIDER`, the matching API key, `SECRET_KEY`, `ALLOWED_ORIGINS` = the frontend's Railway URL once known, plus optional `TAVILY_API_KEY`/`SENDGRID_API_KEY`). Expose port `8000`. Railway's injected `DATABASE_URL` from step 2 already matches what `alembic upgrade head` in the container's `CMD` expects — no extra wiring needed.
4. **`frontend` service**: point it at the `frontend/` subdirectory (uses `frontend/Dockerfile`). Set the build arg `VITE_API_BASE_URL` to the `api` service's public Railway URL (generate its domain first, then redeploy the frontend so the build arg picks it up — Vite bakes it in at build time, so this order matters). Expose port `3000`.
5. **Generate public domains** for both `api` and `frontend` (Railway → service → Settings → Networking → Generate Domain).
6. **Verify**: `curl https://<api-domain>/docs` and open `https://<frontend-domain>` in a browser; confirm the profile form successfully calls the API (no CORS errors — this means `ALLOWED_ORIGINS` on `api` must include the frontend's exact domain).

### Redeploy checklist
- Pushing to `dev`/`main` (whichever branch the Railway service tracks) triggers a rebuild automatically.
- If you change the `api` service's public domain, update `ALLOWED_ORIGINS` on `api` **and** rebuild `frontend` with the new `VITE_API_BASE_URL` build arg — it will not pick up the change from an env var alone, since it's compiled into the JS bundle.
- Database migrations run automatically on every `api` container start (`alembic upgrade head` in `Dockerfile`'s `CMD`) — no manual migration step needed on redeploy.

## 4. Deploying to Render (alternative)

Render's Blueprint (`render.yaml`) or manual dashboard setup mirrors Railway:
- One **Web Service** for `api`: root Dockerfile, port 8000, env vars as above, plus a **PostgreSQL** instance (Render → New → PostgreSQL) — copy its Internal Connection String into `api`'s `DATABASE_URL`.
- One **Web Service** for `frontend`: Dockerfile at `frontend/Dockerfile`, port 3000, build-time env var `VITE_API_BASE_URL` set to the `api` service's `.onrender.com` URL.
- Free-tier Render web services sleep after inactivity — the first request after a sleep will be slow (cold start + LaTeX/Playwright image).

## 5. What's not yet done

This document gets the project to "container builds and runs correctly, ready to deploy" — verified locally with `docker compose up --build`. Actually creating the Railway/Render project, attaching a real Postgres instance, setting production secrets, and publishing a live URL requires a maintainer with Railway/Render account access; it hasn't been done from this environment. Once deployed, replace this section with the live URL and the exact date/commit it was deployed from.
