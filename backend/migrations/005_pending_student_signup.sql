CREATE TABLE cadastros_alunos_pendentes (
    token_hash TEXT PRIMARY KEY,
    convite_hash TEXT NOT NULL,
    google_sub TEXT NOT NULL,
    email_google TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '10 minutes'),
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX cadastros_alunos_expiracao ON cadastros_alunos_pendentes(expires_at);
