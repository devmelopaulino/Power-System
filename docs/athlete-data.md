# Dados do atleta e prescrição

O perfil do aluno tem três abas: Panorama, Dados do Atleta e Prescrição. A prescrição salva somente a sessão e sua configuração (treino/descanso, aquecimento, máxima prevista, RPE previsto, exercícios e séries). Não recebe pesagens e não altera histórico corporal. O endpoint antigo de metadados também ignora campos de peso, evitando sobrescritas por formulários antigos.

O aluno informa peso opcionalmente no cadastro inicial ou na própria área: atualização manual, check-in de treino ou de descanso. A identidade da sessão determina o aluno; identificadores enviados no corpo não podem selecionar outra pessoa. Treinadores não podem escrever no endpoint de pesagens.

Cada envio gera um evento em `historico_pesagens`. `pesos_alunos` mantém a leitura mais recente de cada dia para gráficos e DOTS. Atualizações repetidas no mesmo dia preservam os eventos anteriores. Uma pesagem retroativa não substitui o peso de uma data posterior. Não são aceitos pesos fora de 1–500 kg nem datas futuras.

A aba Dados do Atleta mostra KPIs de peso atual, peso inicial e variação acumulada. O peso inicial vem do onboarding; na ausência dele, usa a primeira pesagem conhecida. O gráfico substitui a tabela, com períodos de 30/90/180/365 dias, datas responsivas, variação em relação ao registro anterior e origem no tooltip. O cálculo da variação anterior considera também a pesagem imediatamente anterior ao período filtrado. Atualiza a cada 15 segundos e ao voltar para a janela; os indicadores do perfil atualizam a cada 30 segundos e ao recuperar o foco. A atualização não reinicializa a sessão em edição.

Gênero (coeficientes masculino/feminino do DOTS) e categoria de peso alvo são editáveis apenas pelo treinador proprietário, nesta aba. O gênero usa a mesma coluna consultada pelo DOTS; a meta é um limite opcional em kg. O gráfico inclui uma referência pontilhada para a meta e uma tendência opcional (média móvel dos últimos sete registros visíveis). KPIs são calculados sobre todo o histórico, independentemente do filtro do gráfico.

O treinador pode corrigir data/peso ou excluir uma pesagem. Correções passam a ter origem “Ajuste do treinador”, preservando internamente a identificação de um registro inicial de onboarding. Exclusão é lógica: remove a leitura da interface e dos cálculos, preservando-a no armazenamento. As alterações ficam auditadas em `correcoes_pesagens`. A leitura diária é reconstruída na mesma transação, incluindo eventual leitura anterior do mesmo dia; peso atual, histórico e DOTS passam a usar o valor corrigido. Um registro excluído não pode ser alterado novamente pelos endpoints normais.

## Acesso compacto aos registros

A prescrição abre diretamente em Nova sessão. Editar sessão existente expande uma lista pesquisável, com oito itens por página, em ordem decrescente de data. A busca aceita data ISO ou brasileira, título, movimento e fases presentes no título (Volume, Força, Deload). O calendário oferece o resumo da sessão e um atalho de edição; em telas estreitas, a edição continua disponível no resumo.

A montagem não exibe seletor de Tipo de dia nem controles de execução. Observações gerais substituem o campo Aquecimento; orientações antigas são mantidas nas observações ao editar. A tabela contém Número da série (linha 1, 2, 3…), Número de séries, Repetições e Carga prevista em kg. Cada linha é independente: 1 × 3 × 200 ou 1 × 6 × 75, por exemplo. O backend mantém as séries individuais e os agrupamentos para reabrir a prescrição com as mesmas linhas. O limite é de 30 séries individuais por exercício. Séries e exercícios que já possuem execução não podem ser removidos nesta tela; cargas executadas, repetições executadas e RPE são preservados no salvamento. Sessões antigas de descanso permanecem reconhecidas internamente.

Nas pesagens, Editar pesagem existente usa a mesma lista compacta, com busca por data, peso e origem. Clicar ou selecionar pelo teclado uma bolinha no gráfico da aba Dados do Atleta abre diretamente a correção daquela pesagem, sem abrir o histórico completo. Apenas o treinador tem acesso aos controles de correção; a área do aluno mantém o registro de novas pesagens separado.

Tabela e página individual consultam as mesmas sessões e usam as mesmas funções Haskell para máximas e Total: maior carga executada em cada movimento, independentemente do número de repetições. O Total só aparece quando existem registros dos três movimentos. Prescrição sem execução não produz PR. As cargas ficam centralizadas na tabela.

Rotas:

- `GET /api/alunos/:id/dados-atleta`: leitura pelo treinador proprietário.
- `GET /api/auth/dados-atleta`: leitura pelo próprio aluno.
- `POST /api/auth/pesagens`: peso, data e origem; exige sessão de aluno e proteção CSRF.
- `POST /api/alunos/:id/dados-atleta`: gênero e limite de peso alvo; não modifica pesagens.
- `POST /api/alunos/:id/pesagens/:registro/editar`: corrige data e peso; exige treinador proprietário e CSRF.
- `POST /api/alunos/:id/pesagens/:registro/excluir`: exclui a leitura dos cálculos e reconstrói o peso diário.
- `POST /api/alunos/:id/treinos`: sessão e objeto `prescricao`, com `tipoDia`, `aquecimento`, `cargaMaximaDia` e `rpePrevisto`. Descanso não aceita exercícios executados.

A migração 007 mantém as pesagens existentes e inicia o histórico de eventos. Os testes locais verificam propriedade, onboarding, pesagens repetidas e retroativas, proteção contra campos de peso de clientes antigos, preservação durante prescrição, descanso e igualdade entre máximas do perfil e da tabela.

A montagem não possui campos de Link do vídeo nem de carga máxima manual. A máxima prevista do dia é calculada a partir da maior carga prevista entre as séries dos exercícios, tanto ao salvar quanto ao consultar sessões antigas. Sem exercícios (descanso), a máxima é nula. Esse cálculo não cria execução nem altera PRs. Links de vídeos já existentes permanecem preservados nos registros antigos.

## Salvamentos confiáveis (auditoria 16 e 39)

Prescrição, execução, perfil e pesagens usam `Idempotency-Key`, vinculado à conta autenticada. A migração `011_reliable_writes.sql` registra a resposta confirmada na mesma transação da alteração. Repetir a mesma chave e conteúdo devolve a resposta anterior; reutilizar a chave com conteúdo diferente retorna 409. Envios concorrentes da mesma operação são serializados. As verificações de sessão, CSRF e papel continuam obrigatórias. Convites e autenticação não armazenam respostas com tokens nessa tabela.

Antes de enviar, o navegador preserva o conteúdo e a chave por conta. Falhas de rede, resposta ilegível ou erro do servidor deixam a tentativa como não confirmada. O painel de salvamentos permite confirmar novamente com a mesma chave, inclusive após recarregar ou autenticar de novo com a mesma conta. Dados diferentes na mesma rota aguardam a resolução da tentativa anterior. Erros explícitos de validação liberam a tentativa para correção; sucesso é exibido apenas após confirmação do servidor. Não há reenvio automático ao reconectar.

A recuperação depende de manter os dados deste navegador. Não são guardados tokens de autenticação nesses registros. O cabeçalho `X-Power-System-Account` impede enviar uma tentativa pendente sob outra conta autenticada. Testes cobrem repetição, concorrência, chaves incompatíveis, erro sem recibo, pesagens, resposta perdida, sessão expirada e isolamento de contas.

## Auditoria 12, 34, 38 e 40

Total e DOTS ausentes exibem os movimentos/dados faltantes, sem substituir ausência por zero. O gráfico mantém o estado sem registros do período e explica separadamente os requisitos atuais do indicador. Aluno tem atalhos para Perfil e Peso; treinador para Dados do Atleta.

Campos de execução preservam texto vazio durante a edição, aceitam vírgula decimal nas cargas, oferecem teclado adequado e exibem validação junto ao campo. Antes do envio, cargas são convertidas para números de 0 a 1.500 kg e repetições para inteiros de 1 a 100. Vazio impede o envio; zero explícito representa ausência de carga externa. Séries não realizadas continuam sem execução, e RPE é aplicado após normalizar os números.

Convite e onboarding anunciam peso opcional, cadastro e edição limitam o nome a 120 caracteres, e o cadastro informa os requisitos posteriores para DOTS. Erros de sessão, permissão, registro ausente, validação, rede e indisponibilidade recebem orientações distintas. Mensagens de infraestrutura não exibem conteúdo técnico retornado pelo servidor nem comandos para reiniciá-lo. Falhas durante gravação mantêm a proteção e o estado não confirmado da auditoria 16/39.
