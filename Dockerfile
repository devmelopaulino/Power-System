FROM node:22-bookworm-slim AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM postgres:17-bookworm AS database-test
COPY backend/migrations/001_initial.sql /checks/schema.sql
COPY backend/test/database.sql /checks/database.sql
USER postgres
RUN initdb -D /tmp/power-system-test --auth=trust > /dev/null \
    && pg_ctl -D /tmp/power-system-test -o "-c listen_addresses='' -k /tmp" -w start \
    && psql -h /tmp -d postgres -v ON_ERROR_STOP=1 -f /checks/schema.sql -f /checks/database.sql \
    && pg_ctl -D /tmp/power-system-test -m fast -w stop \
    && touch /tmp/database-verified

FROM haskell:9.10.3-slim-bookworm AS backend
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build/backend
COPY backend/power-system.cabal ./
RUN cabal update && cabal build --only-dependencies -j2
COPY backend/app/ ./app/
COPY backend/src/ ./src/
COPY backend/migrations/ ./migrations/
RUN cabal build power-system-server -j2 \
    && mkdir -p /output \
    && cp "$(cabal list-bin power-system-server)" /output/power-system-server

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgmp10 libnuma1 libffi8 libtinfo6 zlib1g libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=backend /output/power-system-server /app/power-system-server
COPY --from=frontend /build/frontend/dist /app/public
COPY backend/migrations/ /app/migrations/
COPY --from=database-test /tmp/database-verified /app/database-verified
ENV PORT=8080 STATIC_DIR=/app/public
USER app
EXPOSE 8080
CMD ["/app/power-system-server"]
