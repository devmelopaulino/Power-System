CREATE TABLE operacoes_gravacao (
 autor_sub TEXT NOT NULL REFERENCES contas(google_sub) ON DELETE CASCADE,
 chave TEXT NOT NULL CHECK(length(chave) BETWEEN 16 AND 128),
 caminho TEXT NOT NULL, fingerprint TEXT NOT NULL,
 status INTEGER NOT NULL CHECK(status BETWEEN 200 AND 299),
 resposta BYTEA NOT NULL,
 criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(autor_sub,chave)
);
