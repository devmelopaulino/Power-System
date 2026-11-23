-- Dados fictícios. Executado somente pelo script local, nunca nas migrações.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'power_system_dev' THEN
  RAISE EXCEPTION 'Os exemplos só podem ser inseridos no banco local power_system_dev.';
 END IF;
END $$;
CREATE TEMP TABLE demo_owner ON COMMIT DROP AS
 SELECT id FROM treinadores WHERE id = :treinador_id;
DO $$ BEGIN
 IF (SELECT count(*) FROM demo_owner) <> 1 THEN RAISE EXCEPTION 'Treinador local não encontrado.'; END IF;
END $$;

CREATE TEMP TABLE demo_people (
 nome TEXT, email TEXT, categoria TEXT, peso_inicial DOUBLE PRECISION, peso_atual DOUBLE PRECISION,
 agachamento DOUBLE PRECISION, supino DOUBLE PRECISION, terra DOUBLE PRECISION, fator_inicial DOUBLE PRECISION, bloco TEXT
) ON COMMIT DROP;
-- Não cria aluno nem altera identidade ou conta Google.
INSERT INTO demo_people
 SELECT a.nome,lower(a.email),'masculino',92,90,210,160,270,0.72,'Bloco de Força'
 FROM alunos a JOIN demo_owner owner ON owner.id=a.treinador_id
 WHERE a.id=:aluno_id AND lower(a.nome)='lucas melo';
DO $$ BEGIN
 IF (SELECT count(*) FROM demo_people)<>1 THEN RAISE EXCEPTION 'Lucas Melo não encontrado para este treinador.'; END IF;
END $$;
CREATE TEMP TABLE demo_students ON COMMIT DROP AS
 SELECT a.id,p.* FROM demo_people p JOIN alunos a ON lower(a.email)=p.email
 JOIN demo_owner owner ON owner.id=a.treinador_id WHERE a.id=:aluno_id;

INSERT INTO perfis_alunos (aluno_id,categoria,bloco,inicio_bloco,semanas)
 SELECT id,categoria,bloco,date_trunc('week',CURRENT_DATE)::date-14,4 FROM demo_students
 ON CONFLICT(aluno_id) DO UPDATE SET categoria=COALESCE(perfis_alunos.categoria,EXCLUDED.categoria), bloco=CASE WHEN perfis_alunos.bloco='' THEN EXCLUDED.bloco ELSE perfis_alunos.bloco END, inicio_bloco=COALESCE(perfis_alunos.inicio_bloco,EXCLUDED.inicio_bloco);

-- 53 pesagens ao longo de um ano, com tendência e pequenas oscilações.
-- Preserva pesagens existentes e correções feitas no histórico.
INSERT INTO pesos_alunos (aluno_id,data,peso)
 SELECT p.id,CURRENT_DATE-364+(w*7),
  round((p.peso_inicial+(p.peso_atual-p.peso_inicial)*w/52.0+sin(w*0.8)*0.25*sin(pi()*w/52.0))::numeric,2)::double precision
 FROM demo_students p CROSS JOIN generate_series(0,52) w
 ON CONFLICT(aluno_id,data) DO NOTHING;

-- Sincroniza apenas pesagens ainda sem evento; não recria registros corrigidos/excluídos.
INSERT INTO historico_pesagens(aluno_id,data,peso,origem,registrado_em)
 SELECT p.aluno_id,p.data,p.peso,'legado',p.data::timestamp AT TIME ZONE 'UTC'
 FROM pesos_alunos p JOIN demo_students a ON a.id=p.aluno_id
 WHERE NOT EXISTS (SELECT 1 FROM historico_pesagens h WHERE h.aluno_id=p.aluno_id AND h.data=p.data);

-- Cada linha [percentual, quantidade de séries, repetições] é expandida para
-- séries individuais. O agrupamento permite editar 3x4 sem triplicar o volume.
CREATE FUNCTION pg_temp.demo_exercise(label text, movement text, rm numeric, rows jsonb, done boolean)
RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_build_object('nome',label,'movimento',movement,
  'agrupamentos',(SELECT jsonb_agg((r->>1)::int ORDER BY n) FROM jsonb_array_elements(rows) WITH ORDINALITY x(r,n)),
  'series',(SELECT jsonb_agg(jsonb_build_object(
   'repeticoesPrevistas',(r->>2)::int,
   'cargaPrevista',round(rm*(r->>0)::numeric/100/2.5)*2.5,
   'repeticoes',CASE WHEN done THEN (r->>2)::int END,
   'carga',CASE WHEN done THEN round(rm*(r->>0)::numeric/100/2.5)*2.5 END,
   'rpe',CASE WHEN done THEN CASE WHEN movement='acessorio' THEN least(8.5,7+(k-1)*0.5) ELSE least(9.5,greatest(3,round(((r->>0)::numeric/10-1+(k-1)*0.25)*2)/2)) END END
  ) ORDER BY n,k)
  FROM jsonb_array_elements(rows) WITH ORDINALITY x(r,n)
  CROSS JOIN LATERAL generate_series(1,(r->>1)::int) k))
$fn$;

-- Somente sessões identificadas como exemplos dos três alunos fictícios.
-- Once a sample has history, initialization must not erase its audit trail.
CREATE TEMP TABLE demo_training_students ON COMMIT DROP AS SELECT * FROM demo_students a WHERE NOT EXISTS(SELECT 1 FROM treinos_alunos t WHERE t.aluno_id=a.id AND t.titulo LIKE '%(exemplo)');
SELECT NOT EXISTS(SELECT 1 FROM demo_training_students) AS demo_has_sessions \gset
\if :demo_has_sessions
\echo 'Historico existente preservado; nenhuma sessao foi recriada.'
\else

WITH planos AS (
 SELECT p.*,w,dia,
  p.email=(SELECT email FROM demo_people) AND w%4=2 AND dia=2 AS remanejado,
  p.email=(SELECT email FROM demo_people) AND w%4=1 AND dia=3 AS falta
 FROM demo_training_students p CROSS JOIN generate_series(0,53) w CROSS JOIN generate_series(0,4) dia
 WHERE p.email<>'rafael.exemplo@example.invalid' OR dia IN (0,2,4)
), agenda AS (
 SELECT p.*,r.reposicao,
  date_trunc('week',CURRENT_DATE)::date-364+w*7+CASE WHEN r.reposicao THEN 5 ELSE dia END AS data,
  CASE WHEN p.email='rafael.exemplo@example.invalid' THEN
   CASE dia WHEN 0 THEN 'agachamento' WHEN 2 THEN 'supino' ELSE 'terra' END
   ELSE CASE dia WHEN 0 THEN 'agachamento' WHEN 1 THEN 'supino' WHEN 2 THEN 'terra' WHEN 3 THEN 'agachamento' ELSE 'supino' END END AS movimento,
  CASE WHEN w%12=11 THEN 'Deload' WHEN w%12=10 THEN 'Avaliação de força'
   WHEN w%12>=7 THEN 'Intensificação' WHEN w%12>=4 THEN 'Força' ELSE 'Volume' END AS fase,
  (fator_inicial+(1-fator_inicial)*least(w,52)/52.0)::numeric AS progresso
 FROM planos p CROSS JOIN LATERAL (SELECT false AS reposicao UNION ALL SELECT true WHERE p.remanejado) r
), detalhes AS (
 SELECT *,data<=CURRENT_DATE AND NOT falta AND (NOT remanejado OR reposicao) AS realizado,
  (CASE movimento WHEN 'agachamento' THEN agachamento WHEN 'supino' THEN supino ELSE terra END)::numeric*progresso AS rm,
  CASE movimento WHEN 'agachamento' THEN 'Agachamento' WHEN 'supino' THEN 'Supino' ELSE 'Terra' END AS nome_movimento,
  CASE WHEN fase='Deload' THEN '[[20,1,8],[30,1,5],[50,1,4],[60,2,3]]'::jsonb
   WHEN dia>=3 AND email<>'rafael.exemplo@example.invalid' THEN '[[30,1,8],[40,1,5],[50,1,4],[65,1,3],[70,1,3],[75,2,3]]'::jsonb
   WHEN fase='Avaliação de força' THEN '[[20,1,8],[30,1,5],[50,1,5],[60,1,4],[70,1,3],[80,1,2],[90,1,1],[95,1,1],[100,1,1]]'::jsonb
   WHEN fase='Intensificação' THEN '[[20,1,8],[30,1,5],[50,1,5],[60,1,4],[70,1,3],[75,1,3],[80,1,3],[85,3,3]]'::jsonb
   WHEN fase='Força' THEN '[[20,1,8],[30,1,6],[50,1,5],[60,1,4],[70,1,3],[80,3,4]]'::jsonb
   ELSE '[[20,1,8],[30,1,6],[50,1,5],[60,1,4],[70,4,5]]'::jsonb END AS rampa
 FROM agenda WHERE data>=(CURRENT_DATE-INTERVAL '1 year')::date
), payload AS (
 SELECT *,
 jsonb_build_array(pg_temp.demo_exercise(nome_movimento,movimento,rm,rampa,realizado))
 ||CASE WHEN dia=4 AND email<>'rafael.exemplo@example.invalid' THEN
  jsonb_build_array(pg_temp.demo_exercise('Terra técnico','terra',terra::numeric*progresso,
   '[[30,1,8],[40,1,5],[50,1,5],[60,1,5],[70,1,4],[75,2,3]]',realizado)) ELSE '[]'::jsonb END
 ||CASE WHEN fase='Deload' THEN '[]'::jsonb ELSE
  CASE movimento
   WHEN 'agachamento' THEN CASE WHEN dia=3 THEN
    jsonb_build_array(pg_temp.demo_exercise('Extensora','acessorio',50*progresso,'[[100,4,10]]',realizado),
     pg_temp.demo_exercise('Leg press','acessorio',180*progresso,'[[100,4,6]]',realizado),
     pg_temp.demo_exercise('Stiff','acessorio',80*progresso,'[[100,3,8]]',realizado))
    ELSE jsonb_build_array(pg_temp.demo_exercise('Desenvolvimento com halteres','acessorio',20*progresso,'[[100,4,6]]',realizado),
     pg_temp.demo_exercise('Elevação lateral','acessorio',10*progresso,'[[100,4,8]]',realizado)) END
   WHEN 'supino' THEN jsonb_build_array(
    pg_temp.demo_exercise('Remada baixa','acessorio',60*progresso,'[[100,4,10]]',realizado),
    pg_temp.demo_exercise('Tríceps na polia','acessorio',25*progresso,'[[100,3,12]]',realizado))
   ELSE jsonb_build_array(pg_temp.demo_exercise('Remada curvada','acessorio',65*progresso,'[[100,4,6]]',realizado),
    pg_temp.demo_exercise('Puxada alta','acessorio',55*progresso,'[[100,4,8]]',realizado),
    pg_temp.demo_exercise('Rosca direta','acessorio',25*progresso,'[[100,3,8]]',realizado)) END
  ||jsonb_build_array(pg_temp.demo_exercise('Abdômen','acessorio',0,'[[100,3,20]]',realizado)) END AS exercicios
 FROM detalhes
)
INSERT INTO treinos_alunos(aluno_id,data,data_prevista,data_realizada,titulo,concluido,exercicios,observacoes,video,prescricao)
 SELECT id,data,data,CASE WHEN realizado THEN data END,CASE WHEN reposicao THEN 'Reposição · ' ELSE '' END||nome_movimento||
  CASE WHEN dia=4 AND email<>'rafael.exemplo@example.invalid' THEN ' + Terra técnico' ELSE '' END||
  ' · '||fase||' · Semana '||(w%12+1)||' (exemplo)',realizado,exercicios,
  'Dados fictícios inspirados em uma planilha de força. RM de referência do movimento: '||
  (round(rm/2.5)*2.5)||' kg. Progressão: '||
  (SELECT string_agg((r->>0)||'%: '||(r->>1)||'x'||(r->>2),' → ' ORDER BY n)
   FROM jsonb_array_elements(rampa) WITH ORDINALITY x(r,n))||
  '. Cargas arredondadas em 2,5 kg. '||
  CASE WHEN reposicao THEN 'Reposição da quarta-feira no sábado da mesma semana.'
   WHEN remanejado THEN 'Não realizado nesta data; remanejado para sábado, '||to_char(data+3,'DD/MM/YYYY')||'.'
   WHEN falta THEN 'Falta sem reposição: semana com quatro treinos.'
   WHEN data>CURRENT_DATE THEN 'Sessão prescrita; execução ainda não registrada.'
   WHEN fase='Deload' THEN 'Recuperação: volume e intensidade reduzidos.'
   WHEN fase='Avaliação de força' THEN 'Single final para avaliação; acessórios com esforço moderado.'
   ELSE 'Últimas séries principais de trabalho; registrar esforço real de cada série.' END,
  '',jsonb_build_object('tipoDia','treino','aquecimento','',
   'cargaMaximaDia',(SELECT max((s->>'cargaPrevista')::numeric) FROM jsonb_array_elements(exercicios) e,
    LATERAL jsonb_array_elements(e->'series') s),
   'rpePrevisto',CASE fase WHEN 'Deload' THEN 6 WHEN 'Avaliação de força' THEN 9 ELSE 8 END)
 FROM payload;

-- Verifica semanas completas; as extremidades do histórico podem ser parciais.
DO $$ BEGIN
 IF EXISTS (
  SELECT 1 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id
  WHERE t.concluido AND t.titulo LIKE '%(exemplo)'
   AND t.data>=date_trunc('week',CURRENT_DATE-INTERVAL '1 year')::date+7
   AND t.data<date_trunc('week',CURRENT_DATE)::date
  GROUP BY a.email,date_trunc('week',t.data)
  HAVING (a.email='joao.exemplo@example.invalid' AND count(*)<>5)
      OR (a.email=(SELECT email FROM demo_people) AND count(*) NOT IN (4,5))
      OR (a.email='rafael.exemplo@example.invalid' AND count(*)<>3)
 ) THEN RAISE EXCEPTION 'Frequência semanal dos exemplos inválida.'; END IF;
 IF EXISTS (
  SELECT 1 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id
  WHERE t.titulo LIKE '%(exemplo)' AND ((a.email='joao.exemplo@example.invalid' AND extract(isodow FROM t.data)>5)
   OR (a.email='rafael.exemplo@example.invalid' AND extract(isodow FROM t.data) NOT IN (1,3,5)))
 ) THEN RAISE EXCEPTION 'Dias de descanso dos exemplos inválidos.'; END IF;
 IF EXISTS (
  SELECT 1 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id,
   LATERAL jsonb_array_elements(t.exercicios) e
  WHERE t.titulo LIKE '%(exemplo)' AND
   ((SELECT sum(g::int) FROM jsonb_array_elements_text(e->'agrupamentos') g)<>jsonb_array_length(e->'series')
    OR jsonb_array_length(e->'series')>30)
 ) THEN RAISE EXCEPTION 'Agrupamentos das séries inválidos.'; END IF;
 IF EXISTS (
  SELECT 1 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id,
   LATERAL jsonb_array_elements(t.exercicios) e,LATERAL jsonb_array_elements(e->'series') s
  WHERE t.titulo LIKE '%(exemplo)' AND
   (mod((s->>'cargaPrevista')::numeric,2.5)<>0 OR (s->>'rpe')::numeric NOT BETWEEN 1 AND 10)
 ) THEN RAISE EXCEPTION 'Arredondamento de carga ou RPE inválido.'; END IF;
 IF EXISTS (
  SELECT 1 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id,
   LATERAL jsonb_array_elements(t.exercicios) e,LATERAL jsonb_array_elements(e->'series') s
  WHERE t.titulo LIKE '%(exemplo)' AND (NOT t.concluido OR t.data>CURRENT_DATE) AND s->>'carga' IS NOT NULL
 ) THEN RAISE EXCEPTION 'Sessão não concluída não pode conter carga executada.'; END IF;
END $$;

INSERT INTO auditoria_treinos(treino_id,aluno_id,autor_nome,autor_perfil,acao,motivo,depois)
 SELECT t.id,t.aluno_id,'Sistema','sistema','registro_inicial','Dados ficticios gerados para demonstracao.',row_to_json(t)::jsonb
 FROM treinos_alunos t JOIN demo_training_students a ON a.id=t.aluno_id
 WHERE t.titulo LIKE '%(exemplo)' AND NOT EXISTS(SELECT 1 FROM auditoria_treinos h WHERE h.treino_id=t.id);
\endif

SELECT a.nome,count(DISTINCT t.id) AS sessoes,
 (SELECT count(*) FROM pesos_alunos p WHERE p.aluno_id=a.id) AS pesagens,
 min(t.data) AS inicio_historico,max(t.data) AS ultima_sessao
 FROM demo_students a LEFT JOIN treinos_alunos t ON t.aluno_id=a.id GROUP BY a.id,a.nome ORDER BY a.nome;
COMMIT;


