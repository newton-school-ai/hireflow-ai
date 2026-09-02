# ---- Build stage --------------------------------------------------------
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# Vite inlines VITE_* vars into the built JS at compile time — unlike the
# backend, a runtime `env_file` on the container has no effect here, so the
# API base URL has to arrive as a build ARG instead (see docker-compose.yml).
ARG VITE_API_BASE_URL=http://localhost:8000
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

RUN npm run build

# ---- Serve stage ---------------------------------------------------------
# `serve` keeps the runtime image on the same Node toolchain as the build
# stage (no new tech like nginx just to host static files).
FROM node:20-alpine
WORKDIR /app

RUN npm install -g serve@14

COPY --from=build /app/dist ./dist

EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
