ALTER TABLE treinos_alunos ADD COLUMN prescricao JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE pesos_alunos ADD COLUMN atualizado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE pesos_alunos ADD COLUMN origem TEXT NOT NULL DEFAULT 'legado';
UPDATE pesos_alunos SET atualizado_em=data::timestamp AT TIME ZONE 'UTC';
CREATE TABLE historico_pesagens (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 aluno_id BIGINT NOT NULL REFERENCES alunos(id) ON DELETE CASCADE,
 data DATE NOT NULL, peso DOUBLE PRECISION NOT NULL CHECK(peso>=1 AND peso<=500),
 origem TEXT NOT NULL CHECK(origem IN ('onboarding','treino','descanso','manual','legado')),
 registrado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO historico_pesagens(aluno_id,data,peso,origem,registrado_em)
 SELECT aluno_id,data,peso,'legado',data::timestamp AT TIME ZONE 'UTC' FROM pesos_alunos;
CREATE INDEX historico_pesagens_aluno ON historico_pesagens(aluno_id,data DESC,registrado_em DESC,id DESC);
