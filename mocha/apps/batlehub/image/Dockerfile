# The upstream image ships the server alone; this one adds the web console it serves from static_dir.
ARG VERSION
FROM node:26-alpine AS ui
WORKDIR /ui
RUN npm install -g --ignore-scripts pnpm@11.26.0
COPY ui/package.json ui/pnpm-lock.yaml ui/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY ui/ ./
RUN pnpm run generate && pnpm run build

FROM ghcr.io/batlehub/batlehub:${VERSION}
COPY --from=ui /ui/dist /app/ui/dist
