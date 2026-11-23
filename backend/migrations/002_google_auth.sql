ALTER TABLE treinadores ADD COLUMN google_sub TEXT UNIQUE;

CREATE TABLE oauth_requests (
    state_hash TEXT PRIMARY KEY,
    code_verifier TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '10 minutes')
);

CREATE INDEX oauth_requests_expiration ON oauth_requests (expires_at);

CREATE TABLE sessoes (
    token_hash TEXT PRIMARY KEY,
    treinador_id BIGINT NOT NULL REFERENCES treinadores(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX sessoes_expiration ON sessoes (expires_at);
CREATE INDEX sessoes_por_treinador ON sessoes (treinador_id);
