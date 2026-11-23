CREATE TABLE contas (
    google_sub TEXT PRIMARY KEY,
    perfil TEXT NOT NULL CHECK (perfil IN ('treinador', 'aluno')),
    treinador_id BIGINT UNIQUE REFERENCES treinadores(id) ON DELETE CASCADE,
    aluno_id BIGINT UNIQUE REFERENCES alunos(id) ON DELETE CASCADE,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK ((perfil = 'treinador' AND treinador_id IS NOT NULL AND aluno_id IS NULL)
        OR (perfil = 'aluno' AND aluno_id IS NOT NULL AND treinador_id IS NULL))
);

INSERT INTO contas (google_sub, perfil, treinador_id)
SELECT google_sub, 'treinador', id FROM treinadores WHERE google_sub IS NOT NULL;

ALTER TABLE sessoes ADD COLUMN conta_sub TEXT REFERENCES contas(google_sub) ON DELETE CASCADE;
UPDATE sessoes s SET conta_sub = t.google_sub FROM treinadores t WHERE t.id = s.treinador_id;
-- Sessoes antigas sem identidade Google nao podem autenticar uma conta.
DELETE FROM sessoes WHERE conta_sub IS NULL;
ALTER TABLE sessoes ALTER COLUMN conta_sub SET NOT NULL;
ALTER TABLE sessoes DROP COLUMN treinador_id;
ALTER TABLE treinadores DROP COLUMN google_sub;
CREATE INDEX sessoes_por_conta ON sessoes(conta_sub);

CREATE UNIQUE INDEX alunos_email_por_treinador ON alunos(treinador_id, lower(btrim(email))) WHERE email IS NOT NULL;

CREATE TABLE convites_alunos (
    token_hash TEXT PRIMARY KEY,
    aluno_id BIGINT NOT NULL UNIQUE REFERENCES alunos(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),
    accepted_at TIMESTAMPTZ,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX convites_expiracao ON convites_alunos(expires_at);

ALTER TABLE oauth_requests ADD COLUMN convite_hash TEXT;
ALTER TABLE oauth_requests ADD COLUMN cadastro_treinador BOOLEAN NOT NULL DEFAULT FALSE;
