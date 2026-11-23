CREATE TABLE perfis_alunos (
 aluno_id BIGINT PRIMARY KEY REFERENCES alunos(id) ON DELETE CASCADE,
 foto TEXT, categoria TEXT CHECK (categoria IN ('masculino','feminino')),
 bloco TEXT NOT NULL DEFAULT '', inicio_bloco DATE, semanas INTEGER NOT NULL DEFAULT 4 CHECK (semanas BETWEEN 1 AND 52)
);
CREATE TABLE pesos_alunos (
 aluno_id BIGINT NOT NULL REFERENCES alunos(id) ON DELETE CASCADE,
 data DATE NOT NULL, peso DOUBLE PRECISION NOT NULL CHECK (peso > 0 AND peso <= 500),
 PRIMARY KEY(aluno_id,data)
);
CREATE TABLE treinos_alunos (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 aluno_id BIGINT NOT NULL REFERENCES alunos(id) ON DELETE CASCADE,
 data DATE NOT NULL, titulo TEXT NOT NULL,
 concluido BOOLEAN NOT NULL DEFAULT FALSE,
 exercicios JSONB NOT NULL CHECK (jsonb_typeof(exercicios) = 'array'),
 observacoes TEXT NOT NULL DEFAULT '', video TEXT NOT NULL DEFAULT '',
 atualizado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX treinos_aluno_data ON treinos_alunos(aluno_id,data,id);
