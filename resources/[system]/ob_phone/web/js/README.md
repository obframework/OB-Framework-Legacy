# Interface do OB Phone

O antigo `web/app.js` foi dividido por responsabilidade. O arquivo `app.js`
agora apenas inicia o relógio e a atualização automática.

## Organização

- `core.js`: estado compartilhado, utilitários, preferências e tela inicial.
- `apps/communication.js`: contatos, mensagens, grupos e DarkChat.
- `apps/obgram.js`: feed, perfis e stories.
- `apps/gallery.js`: galeria, seleção, corte, zoom e filtros.
- `apps/camera.js`: captura de foto e vídeo.
- `apps/services.js`: banco e garagem.
- `apps/settings-store.js`: configurações e loja.
- `router.js`: abre e atualiza aplicativos.
- `actions.js`: ações disparadas por botões e formulários.
- `runtime.js`: eventos do navegador, notificações e chamadas.

## Regras para alterações

1. Coloque a tela e as funções do aplicativo no arquivo de seu domínio.
2. Use `post(nome, dados)` para uma chamada NUI simples.
3. Use `action(nome, dados, depois)` quando precisar bloquear cliques repetidos,
   mostrar erros e executar uma atualização após o sucesso.
4. Botões internos usam `data-do="nomeDaAcao"`; registre a ação em
   `actions.js`.
5. Registre a abertura do aplicativo em `router.js`.
6. Não grave dados importantes somente no navegador. Use callbacks Lua e o
   banco do servidor.

Para aplicativos novos e independentes, prefira a API externa. Ela evita
alterar esses arquivos. Consulte `docs/creating-apps.md`.
