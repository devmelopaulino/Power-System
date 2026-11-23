# Perfil individual do aluno

No painel do treinador, clique no nome do aluno. A rota `/#/alunos/:id` abre o perfil e `/#/alunos/:id/treino` abre o editor de sessões. As informações ficam no PostgreSQL; não há dados de demonstração no perfil real.

## Regras dos indicadores

- PR: maior carga executada por movimento, independentemente do número de repetições. Empates usam a data mais recente. O RPE pertence à série do PR. O gráfico mostra somente a série mais pesada de cada dia por movimento, preservando suas repetições e RPE. Em empate de carga, mantém a primeira série registrada. Todas as séries executadas entram no volume, mas não são convertidas em máximas estimadas.
- Total: soma dos três PRs históricos, que podem ter sido feitos em datas diferentes. Sem um dos três movimentos, o Total fica indisponível.
- DOTS: Total histórico e pesagem mais recente, com os coeficientes masculino/feminino selecionados no perfil. Sem categoria, peso ou Total, aparece um traço. É um indicador de treino, não um resultado oficial de competição.
- Histórico DOTS: utiliza o Total acumulado e a última pesagem conhecida até cada data, sem aplicar pesagens futuras retroativamente.
- Volume: soma de repetições executadas × carga de cada série, incluindo acessórios; séries apenas prescritas não entram. Semana começa na segunda-feira. A variação compara o período atual até hoje com o mesmo trecho da semana/mês anterior. Sem volume anterior positivo, não mostra percentual.
- Calendário: concluído quando marcado explicitamente; agendado para hoje/futuro; não concluído quando a data passou sem confirmação. Para reagendar, altere a data da sessão.
- Os dias são definidos pelo relógio UTC do servidor.

## Cadastro dos dados

O editor é exclusivo para treinos e dias de descanso: aquecimento, carga máxima prevista, RPE previsto e exercícios auxiliares. Pesagens e histórico corporal ficam na aba Dados do Atleta e são registrados pelo aluno. Cada sessão contém exercícios, séries prescritas e executadas, RPE, observações e link HTTPS de vídeo. Nesta etapa, os registros e a confirmação de conclusão são feitos pelo treinador. A interface de envio de resultados pelo aluno ainda não faz parte desta página.

A edição de uma sessão preserva seu identificador e não duplica volume. Prescrições futuras não podem conter resultados executados nem estar concluídas. A mesma data de pesagem é atualizada; datas diferentes preservam o histórico.

## API e segurança

- `GET /api/alunos/:id/perfil?periodo=30|90|180|365&volume=semana|mes`
- `POST /api/alunos/:id/perfil`
- `POST /api/alunos/:id/treinos` (id nulo cria; id existente edita)

Todas as rotas exigem sessão de treinador e conferem a propriedade do aluno no servidor. Escritas exigem proteção CSRF. O cliente não decide o treinador proprietário. A migração `006_student_training.sql` cria perfil, pesagens e sessões sem alterar as contas existentes.

Referências DOTS: [IPF Models Evaluation, seção 3](https://www.powerlifting.sport/fileadmin/ipf/data/ipf-formula/Models_Evaluation-I-2020_01.pdf) e [implementação OpenPowerlifting](https://gitlab.com/openpowerlifting/opl-data/blob/main/crates/coefficients/src/dots.rs). Os limites de peso aplicados são 40–210 kg (masculino) e 40–150 kg (feminino).

## Verificação local

Execute `./scripts/test-auth.ps1` na raiz. Os testes usam um banco temporário e verificam migrações, isolamento entre treinadores, DOTS, PR/RPE, Total, volume com cargas diferentes, variação semanal, pesagens, bloqueio de execução futura e edição sem duplicação.

## Interação no gráfico

O eixo de datas distribui marcas intermediárias conforme a largura disponível. Uma bolinha representa a série mais pesada de cada dia. Mouse, toque ou teclado abrem uma janela junto ao ponto com data, carga, repetições, RPE e percentual do PR. No mouse, a janela fecha assim que o cursor sai da bolinha. No teclado, fecha ao sair do ponto; em telas de toque, tocar fora também fecha.

O percentual é calculado em Haskell como carga da série / maior carga executada no movimento em todo o histórico × 100, incluindo séries com mais de uma repetição. Essa referência independe do período selecionado e é a mesma do card de PR. Sem carga máxima positiva, o percentual fica indisponível.

## Perfis dos exemplos locais

O preparo dos exemplos substitui somente sessões com título terminado em (exemplo), dos três e-mails fictícios do treinador escolhido, e renova suas pesagens. João: segunda a sexta, cinco treinos. Marina: meta de cinco, semanas de quatro e reposições de quarta para sábado. Rafael: segunda, quarta e sexta. O intervalo começa um ano antes da data de execução; as semanas nas extremidades podem ser parciais. As sessões futuras são apenas prescritas. Faltas e datas originais de sessões remanejadas não contêm cargas executadas. As reposições registram a execução na nova data e identificam a origem nas observações.

Consulte também [Dados do atleta e prescrição](athlete-data.md) para as regras de integridade, sincronização e endpoints de pesagens.
