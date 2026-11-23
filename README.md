# Power System

Estrutura inicial para um gerenciador de treinos, com uma página **Hello World** em React e uma rota HTTP em Haskell.

## Estrutura

```text
.devcontainer/devcontainer.json  # Ambiente do Codespaces
backend/
  app/Main.hs                   # Servidor Warp, porta 8080
  src/API/Routes.hs             # Rotas da API e verificacao do banco
  src/Database/Connection.hs    # Conexao PostgreSQL e migracoes
  migrations/001_initial.sql   # Tabelas de treinadores e alunos
  power-system.cabal            # Dependências e executável
frontend/
  src/App.jsx                   # Página Hello World
  src/main.jsx                  # Entrada React
  src/index.css                 # Tailwind CSS
  vite.config.js                # Servidor e proxy /api
```

A base usa React, Vite e Tailwind CSS no frontend; Servant e Warp no backend. A persistência usa PostgreSQL, com tabelas de treinadores e alunos. Login e operações de cadastro ainda não foram implementados.

## Executar localmente

Requisitos: Node.js com npm, GHC, Cabal e as bibliotecas de desenvolvimento do PostgreSQL (`libpq-dev` e `pkg-config` no Debian/Ubuntu). No Windows, disponibilize as bibliotecas de desenvolvimento do PostgreSQL e `pg_config` no PATH, ou use o Codespaces.

Em um terminal, inicie o backend:

```sh
cd backend
cabal update
cabal run power-system-server
```

Em outro terminal, instale as dependências e inicie o frontend:

```sh
cd frontend
npm ci
npm run dev
```

Abra http://localhost:5173 para ver a página Hello World.

O backend responde `Hello World` em http://localhost:8080/hello. Durante o desenvolvimento, o Vite encaminha http://localhost:5173/api/hello para essa rota. Use o prefixo `/api` nas futuras chamadas do frontend para funcionar também no Codespaces. A página inicial é estática e não depende da API.

A variável de ambiente `PORT` permite alterar a porta do backend (padrão: `8080`). Se mudar essa porta, ajuste também o destino do proxy em `frontend/vite.config.js`.

## Codespaces

Ao criar ou reconstruir o container, a configuração instala as dependências do frontend e compila o backend. Depois, execute os dois comandos de inicialização em terminais separados:

```sh
cd backend && cabal run power-system-server
```

```sh
cd frontend && npm run dev
```

Abra a porta **5173** na aba **Ports** do Codespaces. A API é acessada pelo proxy `/api` no mesmo endereço do frontend.

As alterações locais chegam ao Codespaces após commit e push para o GitHub e `git pull` no Codespaces. Para aplicar mudanças em `.devcontainer`, reconstrua o container.

## Verificar a base

```sh
cd frontend
npm run build
```

```sh
cd backend
cabal build
```

O build do frontend gera `frontend/dist`. `npm run preview` permite conferir esse build estático; o proxy do Vite é usado apenas no servidor de desenvolvimento.

## Publicar no Railway

O `Dockerfile` na raiz compila o React e o Haskell. Um único serviço entrega a página em `/` e a API em `/api/hello` (com `/hello` mantido para o teste direto).

Crie um projeto no Railway com este repositório, mantendo a pasta raiz do serviço em `/`. O Railway detecta o `Dockerfile`; não configure comandos de build ou inicialização adicionais. Em **Settings → Networking**, use **Generate Domain** para obter o endereço público. Configure a verificação de saúde do serviço em `/api/health`, com timeout de 120 segundos.

A porta vem da variável `PORT` do Railway. O diretório da página compilada é definido por `STATIC_DIR` no container. Configure `DATABASE_URL` com a referência privada do serviço PostgreSQL, conforme a seção abaixo.

Para publicar os arquivos locais com a CLI do Railway, depois de vincular o projeto e o serviço:

```sh
railway up --service power-system
```

Para testar o modo de produção local sem Docker, execute `npm ci` e `npm run build` em `frontend`, depois `cabal run power-system-server` em `backend`. Abra http://localhost:8080: o Haskell entrega a página compilada e a API pelo mesmo endereço.

## Banco de dados PostgreSQL

No Railway, adicione um serviço **PostgreSQL** no mesmo projeto e ambiente da aplicação. No serviço **power-system**, configure:

```text
DATABASE_URL=${{Postgres.DATABASE_URL}}
```

Essa referência mantém as credenciais no Railway e usa a rede privada. Não publique a senha nem a URL real no repositório. O banco não precisa de domínio ou porta pública.

Na inicialização, o Haskell aguarda o banco e aplica `backend/migrations/001_initial.sql` em uma transação. A tabela `schema_migrations` registra a versão aplicada; inicializações posteriores preservam os dados. Um bloqueio do PostgreSQL serializa migrações em deployments simultâneos. Para evoluir o esquema, acrescente uma nova migração e sua versão ao executor; não altere uma migração já aplicada.

Tabelas iniciais:

- `treinadores`: identificador, nome, e-mail único sem distinção entre maiúsculas e minúsculas e data de criação.
- `alunos`: identificador, treinador responsável, nome, e-mail opcional e data de criação.
- `schema_migrations`: versões das migrações aplicadas.

Nenhum dado pessoal de exemplo é inserido. A estrutura ainda não inclui autenticação, senhas ou permissões por usuário; as rotas de cadastro e consulta de alunos serão implementadas junto dessas regras.

`GET /api/health` consulta o banco e retorna HTTP 200 com `{"status":"ok","database":"connected"}` quando a conexão e a migração estão disponíveis. Retorna HTTP 503 quando o banco está indisponível ou não foi configurado. Essa deve ser a rota de saúde no Railway.

### Desenvolvimento e testes locais no Windows

O banco de desenvolvimento funciona exclusivamente em `127.0.0.1:5433`, com o nome `power_system_dev`. Ele é separado do PostgreSQL do Railway. Os scripts usam a instalação do PostgreSQL em `C:/ghcup/msys64/mingw64/bin`; para outra instalação, informe `-PostgresBin 'C:/caminho/para/bin'`.

Na pasta principal do projeto, abra um PowerShell e execute:

```powershell
.\scripts\local-db.ps1 -Action backend
```

O comando inicia o banco local, cria as tabelas pelo Haskell, adiciona um treinador e três alunos fictícios e inicia a API na porta 8080. Pare o backend antigo com `Ctrl+C` antes de iniciar este comando se a porta já estiver ocupada.

Em outro terminal:

```powershell
cd frontend
npm run dev
```

Abra http://localhost:5173. Para conferir a conexão do backend com o banco local, acesse http://localhost:8080/api/health ou http://localhost:5173/api/health. O resultado esperado é `{"status":"ok","database":"connected"}`.

Para apenas preparar o banco, sem iniciar a API:

```powershell
.\scripts\local-db.ps1 -Action start
```

Para executar os testes de integridade das tabelas:

```powershell
.\scripts\local-db.ps1 -Action test
```

Os testes verificam o vínculo entre aluno e treinador, e-mail duplicado, nome vazio e exclusão de treinador com alunos. As inserções feitas pelos testes são revertidas. Os três alunos fictícios são mantidos no banco local para desenvolver as telas; iniciar novamente não duplica esses registros. As telas de cadastro e consulta ainda precisam ser implementadas.

Para ver e parar o serviço local:

```powershell
.\scripts\local-db.ps1 -Action status
.\scripts\local-db.ps1 -Action stop
```

Parar o serviço preserva os dados. Ele não é instalado como um serviço automático do Windows: use o script para iniciá-lo após reiniciar o PC.

### Visualizar o banco local

No DBeaver ou pgAdmin, crie uma conexão PostgreSQL com:

- Host: `127.0.0.1`
- Porta: `5433`
- Banco: `power_system_dev`
- Usuário: `power_system_dev`
- Senha: consulte `.local/postgres/connection.json` no seu computador.

Esse arquivo contém uma senha aleatória exclusiva do desenvolvimento. A pasta `.local` guarda o banco e suas credenciais e está excluída do Git, do envio ao Railway e da imagem Docker. Não compartilhe seu conteúdo.

### Outros ambientes

No Linux/Codespaces, use um PostgreSQL de desenvolvimento separado e exporte a URL antes de executar o backend. `backend/.env.example` documenta a variável; o Cabal não carrega arquivos `.env` automaticamente.

```sh
export DATABASE_URL='postgresql://postgres:SUA_SENHA@localhost:5432/power_system'
cd backend
cabal run power-system-db
cabal run power-system-server
```

Sem `DATABASE_URL`, a página e as rotas Hello World continuam funcionando localmente, mas a verificação do banco retorna 503. No Railway, a variável é obrigatória. `MIGRATIONS_DIR` pode alterar a pasta das migrações (padrão: `migrations`, a partir da pasta `backend` ou `/app` no container).

## Login e cadastro

Acesse `/#/entrar` ou `/#/cadastro`. O cadastro oferece os perfis **treinador** e **aluno** com Google. Treinadores criam sua conta e usam `/#/alunos` para gerar um link de convite. O aluno abre o link e entra com Google. Depois, preenche o nome e, opcionalmente, o peso corporal numa tela intermediária e confirma o cadastro para acessar seus treinos. Depois, entra em `/#/meus-treinos`. O Haskell controla os perfis e as permissões; a prescrição fica separada da aba Dados do Atleta, com pesagens registradas pelo aluno.

Veja o passo a passo em [Login com Google](docs/google-login.md), incluindo configuração local, variáveis no Railway e testes. O JSON das credenciais e as configurações da pasta `.local` não devem ser publicados.
