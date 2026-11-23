ALTER TABLE treinos_alunos ADD COLUMN data_prevista DATE;
ALTER TABLE treinos_alunos ADD COLUMN data_realizada DATE;
ALTER TABLE treinos_alunos ADD COLUMN situacao TEXT NOT NULL DEFAULT 'ativa' CHECK(situacao IN ('ativa','cancelada','anulada'));
-- Recover planned dates recorded by the previous advancement flow, when valid.
UPDATE treinos_alunos SET data_prevista=CASE
 WHEN pg_input_is_valid(substring(observacoes from 'Sessao originalmente prevista para ([0-9]{4}-[0-9]{2}-[0-9]{2})'),'date')
 THEN substring(observacoes from 'Sessao originalmente prevista para ([0-9]{4}-[0-9]{2}-[0-9]{2})')::date ELSE data END,
 data_realizada=CASE WHEN concluido OR EXISTS(SELECT 1 FROM jsonb_array_elements(exercicios) e,LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(e->'series')='array' THEN e->'series' ELSE '[]'::jsonb END) s WHERE s->>'carga' IS NOT NULL) THEN data END;
ALTER TABLE treinos_alunos ALTER COLUMN data_prevista SET NOT NULL;
CREATE TABLE auditoria_treinos(
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 treino_id BIGINT NOT NULL REFERENCES treinos_alunos(id),
 aluno_id BIGINT NOT NULL REFERENCES alunos(id),
 autor_sub TEXT, autor_nome TEXT NOT NULL, autor_perfil TEXT NOT NULL,
 acao TEXT NOT NULL, motivo TEXT NOT NULL,
 antes JSONB, depois JSONB NOT NULL,
 criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX auditoria_treinos_sessao ON auditoria_treinos(treino_id,id DESC);
INSERT INTO auditoria_treinos(treino_id,aluno_id,autor_nome,autor_perfil,acao,motivo,depois)
 SELECT id,aluno_id,'Sistema','sistema','registro_inicial','Estado existente ao ativar a auditoria; alteracoes anteriores nao foram registradas.',row_to_json(t)::jsonb FROM treinos_alunos t;
