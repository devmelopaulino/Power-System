ALTER TABLE perfis_alunos ADD COLUMN categoria_peso_alvo DOUBLE PRECISION CHECK(categoria_peso_alvo>0 AND categoria_peso_alvo<=500);
ALTER TABLE historico_pesagens DROP CONSTRAINT historico_pesagens_origem_check;
ALTER TABLE historico_pesagens ADD CONSTRAINT historico_pesagens_origem_check CHECK(origem IN ('onboarding','treino','descanso','manual','legado','treinador'));
ALTER TABLE historico_pesagens ADD COLUMN excluido_em TIMESTAMPTZ;
ALTER TABLE historico_pesagens ADD COLUMN origem_original TEXT;
CREATE TABLE correcoes_pesagens (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pesagem_id BIGINT NOT NULL REFERENCES historico_pesagens(id),
 treinador_id BIGINT NOT NULL REFERENCES treinadores(id),
 antes JSONB NOT NULL, depois JSONB,
 registrado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
