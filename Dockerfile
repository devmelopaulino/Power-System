FROM node:22-bookworm-slim AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM haskell:9.10.3-slim-bookworm AS backend
WORKDIR /build/backend
COPY backend/power-system.cabal ./
RUN cabal update && cabal build --only-dependencies -j2
COPY backend/app/ ./app/
COPY backend/src/ ./src/
RUN cabal build power-system-server -j2 \
    && mkdir -p /output \
    && cp "$(cabal list-bin power-system-server)" /output/power-system-server

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgmp10 libnuma1 libffi8 libtinfo6 zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=backend /output/power-system-server /app/power-system-server
COPY --from=frontend /build/frontend/dist /app/public
ENV PORT=8080 STATIC_DIR=/app/public
USER app
EXPOSE 8080
CMD ["/app/power-system-server"]
