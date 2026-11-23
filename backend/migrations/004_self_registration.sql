ALTER TABLE convites_alunos ADD COLUMN treinador_id BIGINT REFERENCES treinadores(id) ON DELETE CASCADE;
UPDATE convites_alunos i SET treinador_id = a.treinador_id FROM alunos a WHERE a.id = i.aluno_id;
ALTER TABLE convites_alunos ALTER COLUMN treinador_id SET NOT NULL;
ALTER TABLE convites_alunos ALTER COLUMN aluno_id DROP NOT NULL;
CREATE INDEX convites_por_treinador ON convites_alunos(treinador_id);

ALTER TABLE oauth_requests ADD COLUMN nome_aluno TEXT;
ALTER TABLE oauth_requests ADD COLUMN email_aluno TEXT;
ALTER TABLE oauth_requests ADD CONSTRAINT oauth_dados_aluno_completos
    CHECK ((nome_aluno IS NULL AND email_aluno IS NULL) OR
           (nome_aluno IS NOT NULL AND email_aluno IS NOT NULL AND convite_hash IS NOT NULL));
