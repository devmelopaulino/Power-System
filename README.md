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

### Desenvolvimento local

Use um banco PostgreSQL separado do ambiente de produção. `backend/.env.example` documenta a variável; o Cabal não carrega arquivos `.env` automaticamente. Antes de iniciar o backend, exporte a URL no terminal:

```powershell
$env:DATABASE_URL = 'postgresql://postgres:SUA_SENHA@localhost:5432/power_system'
cd backend
cabal run power-system-server
```

No Bash/Codespaces:

```sh
export DATABASE_URL='postgresql://postgres:SUA_SENHA@localhost:5432/power_system'
cd backend
cabal run power-system-server
```

Sem `DATABASE_URL`, o desenvolvimento local mantém a página e as rotas Hello World funcionando, mas a verificação do banco retorna 503. No Railway, a variável é obrigatória: a aplicação encerra se a configuração ou a migração falhar. A pasta de migrações pode ser alterada por `MIGRATIONS_DIR` (padrão: `migrations`, a partir da pasta `backend` ou `/app` no container).
