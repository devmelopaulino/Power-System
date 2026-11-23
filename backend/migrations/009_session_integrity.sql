ALTER TABLE treinos_alunos ADD COLUMN versao BIGINT NOT NULL DEFAULT 1;
LOCK TABLE historico_pesagens IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE pesos_alunos IN SHARE ROW EXCLUSIVE MODE;
-- Repair existing onboarding/daily-snapshot mismatches without changing history.
INSERT INTO pesos_alunos(aluno_id,data,peso,origem,atualizado_em)
 SELECT DISTINCT ON (aluno_id,data) aluno_id,data,peso,origem,registrado_em
 FROM historico_pesagens WHERE excluido_em IS NULL
 ORDER BY aluno_id,data,registrado_em DESC,id DESC
 ON CONFLICT(aluno_id,data) DO UPDATE SET peso=EXCLUDED.peso,origem=EXCLUDED.origem,atualizado_em=EXCLUDED.atualizado_em;
