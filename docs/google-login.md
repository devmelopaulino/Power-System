# Login e cadastro com Google

O sistema tem perfis de treinador e aluno, ambos com acesso Google. O treinador cria sua conta em Criar conta → Sou treinador. O aluno só ativa o acesso por um convite gerado pelo treinador. A entrada reconhece o perfil pelo identificador permanente `sub` do Google e abre a área correspondente. A aplicação não recebe a senha do Google; cada conta Google fica vinculada a um perfil.

## Criar o cliente no Google Cloud

1. Abra https://console.cloud.google.com/ e selecione/crie o projeto **Power System**.
2. Em **Google Auth Platform**, preencha os dados do aplicativo (nome e e-mails de contato solicitados).
3. Em **Público-alvo / Audience**, escolha o público adequado. Para contas pessoais, use **Externo**. Se o aplicativo ficar em teste, inclua os e-mails dos usuários de teste.
4. Em **Clientes / Clients**, crie um cliente OAuth do tipo **Aplicativo da Web / Web application**.
5. Em **URIs de redirecionamento autorizados**, adicione exatamente:
   - `http://localhost:5173/api/auth/google/callback`
   - `https://power-system-production.up.railway.app/api/auth/google/callback`
6. Salve e baixe o JSON das credenciais. Não envie esse arquivo ao GitHub.

Este projeto usa redirecionamento pelo servidor, sem bibliotecas Google no navegador. Solicita somente os escopos `openid email profile`; não solicita acesso ao Drive, Agenda ou Gmail.

## Configurar no PC

Na raiz do projeto, importe o JSON baixado:

```powershell
.\scripts\configure-google.ps1 -CredentialsFile 'C:\caminho\para\client_secret.json'
```

O comando salva as configurações em `.local/google-auth.json`, ignorado pelo Git e pelos arquivos de publicação. Ele não exibe a chave secreta no terminal. O arquivo original também é ignorado quando seu nome começa por `client_secret`.

Pare o backend anterior com Ctrl+C e inicie:

```powershell
.\scripts\local-db.ps1 -Action backend
```

Em outro terminal:

```powershell
cd frontend
npm run dev
```

Abra http://localhost:5173/#/entrar ou http://localhost:5173/#/cadastro. Use esse endereço (mesmo host e porta cadastrados no Google). Para registrar um treinador, escolha **Criar conta → Sou treinador** e conclua o Google. A opção **Entrar** reconhece contas existentes e não transforma automaticamente uma conta desconhecida em treinador. Os dados fictícios do banco local pertencem a outro treinador e não são transferidos automaticamente para a conta Google.

## Configurar no Railway

No serviço **power-system**, configure as variáveis:

- `GOOGLE_CLIENT_ID`: o client ID do cliente Web.
- `GOOGLE_CLIENT_SECRET`: o segredo do cliente, somente no backend.
- `APP_BASE_URL`: `https://power-system-production.up.railway.app`.
- `DATABASE_URL`: a referência privada ao PostgreSQL já configurada.

Publique a versão atual do código e confirme que a segunda URL de retorno foi cadastrada no Google. As credenciais não são variáveis `VITE_` e não entram no JavaScript publicado. O domínio configurado em `APP_BASE_URL` determina o retorno após autenticação e a origem permitida para sair da conta.

## Comportamento

- Sem configuração Google, as telas continuam disponíveis e informam que o acesso ainda não foi ativado.
- O Haskell troca o código por um token diretamente no Google, usando client secret e PKCE S256. Consulta o perfil no endpoint HTTPS fixo do Google e exige e-mail verificado. Não aceita nome, e-mail ou identidade enviados pelo navegador como prova de login.
- Cada tentativa usa um estado aleatório vinculado a um cookie HttpOnly, com validade de dez minutos e uso único no banco.
- A sessão usa um token aleatório em cookie HttpOnly e SameSite=Lax. No HTTPS, também usa Secure e o prefixo `__Host-`. O banco guarda apenas o hash do token, com validade de sete dias.
- Sair da conta apaga a sessão no banco e o cookie. O endpoint exige POST, a origem configurada e um cabeçalho próprio para proteção contra CSRF.
- A lista de alunos é filtrada pelo treinador identificado na sessão, sem aceitar um ID de treinador fornecido pelo navegador.
- Um perfil antigo sem vínculo Google não é vinculado automaticamente só porque tem o mesmo e-mail.

## Rotas

| Rota | Finalidade |
|---|---|
| `GET /api/auth/config` | Informa se o acesso Google está habilitado, sem expor segredos. |
| `GET /api/auth/google` | Inicia o redirecionamento para o Google. |
| `GET /api/auth/google/callback` | Recebe e valida o retorno, cria a sessão e abre Meus alunos. |
| `GET /api/auth/me` | Retorna a conta autenticada, seu perfil e seus dados ou HTTP 401. |
| `GET /api/alunos` | Retorna somente os alunos do treinador autenticado. |
| `POST /api/auth/logout` | Encerra a sessão. |

A migração `002_google_auth.sql` prepara a autenticação inicial. A migração `003_student_accounts.sql` centraliza a identidade Google em `contas`, acrescenta os convites e vincula as sessões à conta. Treinadores e sessões Google existentes são preservados. As migrações são aplicadas em ordem, sem alterar migrações já aplicadas.

## Testar

```powershell
.\scripts\test-auth.ps1
```

O comando cria um banco local descartável e verifica proteção das rotas, estado de uso único, PKCE, identificação do treinador, isolamento dos alunos, expiração, cookies e logout. Também verifica os dois perfis, vínculo do convite ao estado OAuth, e-mail do aluno, uso único, expiração, regeneração e preservação de sessões após migração. Remove o banco temporário ao terminar. Os testes não fazem login fictício pelo endpoint público e não substituem o teste manual com sua conta Google.

Referências: [OAuth para aplicações Web](https://developers.google.com/identity/protocols/oauth2/web-server), [OpenID Connect do Google](https://developers.google.com/identity/openid-connect/openid-connect).

## Cadastro de aluno por convite

1. O treinador acessa **Meus alunos** e clica em **Convidar aluno**.
2. O sistema gera um link sem exigir nome ou e-mail do aluno.
3. O treinador copia e compartilha o link com o aluno. O sistema não envia e-mail automaticamente.
4. O aluno abre o link e escolhe **Entrar com o Google**, sem preencher nome ou e-mail antes de autenticar.
5. Depois de validar a conta Google, o Haskell cria uma autorização temporária para `/#/completar-cadastro`. A tela intermediária pede o nome e permite informar o peso corporal inicial. Ao confirmar, o servidor usa a identidade e o e-mail já verificados pelo Google, vincula o aluno ao treinador e abre **Meus treinos**. Nenhum aluno ou acesso à plataforma é criado antes dessa confirmação.
6. Nos acessos seguintes, o aluno usa **Entrar**, sem precisar do convite.

Os links são de uso único e expiram em sete dias. Cada novo aluno recebe um link individual. Renovar o convite de um aluno previamente cadastrado substitui o link daquele aluno. A conta do aluno não pode cadastrar alunos, gerar convites nem acessar a lista de alunos do treinador. O ID do treinador vem da sessão, nunca de um campo enviado pelo navegador.

O aluno já cadastrado em outra conta ou uma conta Google de treinador não é convertido nem transferido silenciosamente. A tabela **Meus alunos** informa quando o acesso está ativo. A página **Meus treinos** é a área inicial do aluno; a montagem e a consulta dos treinos serão implementadas na próxima etapa.

Rotas adicionais:

| Rota | Finalidade |
|---|---|
| `POST /api/convites` | Treinador gera um convite sem cadastrar aluno previamente. Exige sessão e proteção CSRF. |
| `POST /api/alunos/:id/convite` | Treinador renova convite de um aluno próprio ainda sem acesso ativo. |
| `POST /api/convites/verificar` | Verifica o token enviado no JSON; informa somente o nome do treinador, sem divulgar o e-mail do aluno. |

O cadastro explícito de treinador inicia em `/api/auth/google?cadastro=treinador`. A entrada de aluno começa por `/api/auth/google?convite=...`. O único login oferecido no convite é **Entrar com o Google**. A intenção e o hash do convite são gravados na tentativa OAuth e consumidos no retorno; o callback não pode substituí-los. O callback não aceita um perfil ou treinador fornecido pelo navegador.

A migração `004_self_registration.sql` permite convites vinculados diretamente ao treinador, sem um aluno existente. Gerar ou visualizar o convite e autenticar com Google ainda não criam um cadastro de aluno. O cadastro só é criado após confirmar o nome. Se o aluno já tiver um cadastro antigo sem acesso, o vínculo só é reaproveitado dentro do mesmo treinador e após a confirmação do e-mail pelo Google. Convites anteriores continuam funcionando.

O e-mail e a identidade Google ficam guardados somente no servidor durante a etapa intermediária. O formulário final aceita o nome e peso corporal opcional: não pode escolher outro e-mail, identidade ou treinador. Convites antigos vinculados a um e-mail continuam exigindo a conta Google correspondente.

## Confirmação do nome após o Google

A migração `005_pending_student_signup.sql` prepara o cadastro temporário. O navegador recebe um cookie HttpOnly de dez minutos, separado da sessão da plataforma. Em HTTPS, usa prefixo `__Host-`, Secure e SameSite=Lax. O banco guarda somente o hash desse ticket.

- `GET /api/auth/cadastro-aluno`: valida o ticket e informa o treinador para a tela intermediária, sem expor e-mail ou identificador Google.
- `POST /api/auth/cadastro-aluno`: recebe `nome` e `peso` opcional, exige proteção CSRF e revalida ticket e convite. Cria aluno, conta e sessão na mesma transação, consome o ticket e limpa o cookie temporário.
- `/#/completar-cadastro`: tela intermediária com um campo de nome e o botão **Confirmar e entrar**.

Sem concluir o nome, o ticket temporário não permite abrir a plataforma nem consultar alunos. Nome inválido mantém a etapa disponível para corrigir. Tickets expirados, convites expirados ou revogados e tentativas repetidas não criam outra conta. O logout também cancela um cadastro temporário existente no navegador.
