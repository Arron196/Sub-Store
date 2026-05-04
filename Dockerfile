# syntax=docker/dockerfile:1

ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS backend-builder

WORKDIR /src/backend
RUN corepack enable

COPY backend/package.json backend/pnpm-lock.yaml ./
COPY backend/patches ./patches
RUN pnpm install --frozen-lockfile

COPY backend/ ./
RUN pnpm bundle:esbuild

FROM ${NODE_IMAGE} AS frontend-builder

ARG SUB_STORE_FRONTEND_REPO=https://github.com/sub-store-org/Sub-Store-Front-End.git
ARG SUB_STORE_FRONTEND_REF=master
ARG VITE_API_URL=/api
ARG VITE_PUBLIC_PATH=/

WORKDIR /src
RUN apk add --no-cache git && corepack enable
RUN git clone --depth 1 --branch "${SUB_STORE_FRONTEND_REF}" "${SUB_STORE_FRONTEND_REPO}" frontend

WORKDIR /src/frontend
RUN pnpm install --frozen-lockfile

ENV VITE_API_URL=${VITE_API_URL}
ENV VITE_PUBLIC_PATH=${VITE_PUBLIC_PATH}
RUN pnpm build

FROM ${NODE_IMAGE} AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    SUB_STORE_DOCKER=true \
    SUB_STORE_BACKEND_API_HOST=0.0.0.0 \
    SUB_STORE_BACKEND_API_PORT=3000 \
    SUB_STORE_BACKEND_MERGE=true \
    SUB_STORE_FRONTEND_BACKEND_PATH=/api \
    SUB_STORE_FRONTEND_PATH=/app/frontend \
    SUB_STORE_DATA_BASE_PATH=/opt/sub-store/data

COPY --from=backend-builder /src/backend/dist/sub-store.bundle.js ./sub-store.bundle.js
COPY --from=frontend-builder /src/frontend/dist ./frontend

RUN mkdir -p /opt/sub-store/data \
    && chown -R node:node /app /opt/sub-store

USER node

EXPOSE 3000
VOLUME ["/opt/sub-store/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -qO- "http://127.0.0.1:${SUB_STORE_BACKEND_API_PORT}/" >/dev/null || exit 1

CMD ["node", "/app/sub-store.bundle.js"]
