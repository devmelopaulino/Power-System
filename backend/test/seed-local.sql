-- Dados ficticios exclusivos do ambiente local. Nao executar em producao.
BEGIN;
INSERT INTO treinadores (nome, email)
VALUES ('Treinador de teste', 'treinador.local@example.invalid')
ON CONFLICT DO NOTHING;

INSERT INTO alunos (treinador_id, nome, email)
SELECT t.id, exemplo.nome, exemplo.email
FROM treinadores t
CROSS JOIN (VALUES
  ('Aluno de teste 01', 'aluno01.local@example.invalid'),
  ('Aluno de teste 02', 'aluno02.local@example.invalid'),
  ('Aluno de teste 03', 'aluno03.local@example.invalid')
) AS exemplo(nome, email)
WHERE t.email = 'treinador.local@example.invalid'
  AND NOT EXISTS (
    SELECT 1 FROM alunos a WHERE a.treinador_id = t.id AND a.email = exemplo.email
  );
COMMIT;
