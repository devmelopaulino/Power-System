CREATE TABLE treinadores (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome TEXT NOT NULL CHECK (length(btrim(nome)) > 0),
    email TEXT NOT NULL CHECK (length(btrim(email)) > 0),
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX treinadores_email_unico ON treinadores (lower(btrim(email)));

CREATE TABLE alunos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    treinador_id BIGINT NOT NULL REFERENCES treinadores (id) ON DELETE RESTRICT,
    nome TEXT NOT NULL CHECK (length(btrim(nome)) > 0),
    email TEXT CHECK (email IS NULL OR length(btrim(email)) > 0),
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX alunos_por_treinador ON alunos (treinador_id, nome, id);
