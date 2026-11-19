# Power System

Estrutura inicial para um gerenciador de treinos, com uma página **Hello World** em React e uma rota HTTP em Haskell.

## Estrutura

```text
.devcontainer/devcontainer.json  # Ambiente do Codespaces
backend/
  app/Main.hs                   # Servidor Warp, porta 8080
  src/API/Routes.hs             # GET /hello
  power-system.cabal            # Dependências e executável
frontend/
  src/App.jsx                   # Página Hello World
  src/main.jsx                  # Entrada React
  src/index.css                 # Tailwind CSS
  vite.config.js                # Servidor e proxy /api
```

A base usa React, Vite e Tailwind CSS no frontend; Servant e Warp no backend. Não há banco de dados ou regras de negócio nesta etapa.

## Executar localmente

Requisitos: Node.js com npm, GHC e Cabal.

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

O build do frontend gera `frontend/dist`. `npm run preview` permite conferir esse build estático; o proxy `/api` está configurado apenas no servidor de desenvolvimento.
