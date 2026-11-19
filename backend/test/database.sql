-- Execute em um banco inicializado, com psql -v ON_ERROR_STOP=1 -f test/database.sql.
-- As insercoes abaixo sao revertidas: nenhum registro de teste e mantido.
BEGIN;
DO $$
DECLARE
    treinador_teste BIGINT;
    aluno_teste BIGINT;
BEGIN
    INSERT INTO treinadores (nome, email)
    VALUES ('Teste transacional', 'teste-' || txid_current() || '@example.invalid')
    RETURNING id INTO treinador_teste;

    INSERT INTO alunos (treinador_id, nome) VALUES (treinador_teste, 'Aluno de teste')
    RETURNING id INTO aluno_teste;
    IF NOT EXISTS (SELECT 1 FROM alunos WHERE id = aluno_teste AND treinador_id = treinador_teste) THEN
        RAISE EXCEPTION 'Vinculo aluno-treinador ausente';
    END IF;

    BEGIN
        INSERT INTO treinadores (nome, email)
        VALUES ('Duplicado', ' TESTE-' || txid_current() || '@EXAMPLE.INVALID ');
        RAISE EXCEPTION 'E-mail duplicado foi aceito';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO alunos (treinador_id, nome) VALUES (treinador_teste, '   ');
        RAISE EXCEPTION 'Nome vazio foi aceito';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO alunos (treinador_id, nome) VALUES (-1, 'Sem treinador');
        RAISE EXCEPTION 'Aluno sem treinador valido foi aceito';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    BEGIN
        DELETE FROM treinadores WHERE id = treinador_teste;
        RAISE EXCEPTION 'Treinador com aluno foi excluido';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
END $$;
ROLLBACK;
SELECT 'Integridade de treinadores e alunos: OK' AS resultado;
