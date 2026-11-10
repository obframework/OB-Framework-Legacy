# OB Chat

Substituto do chat padrao do FiveM focado em comandos.

- `T` abre somente quando nenhuma outra NUI possui foco.
- Texto comum nao e enviado; a entrada sempre exige `/comando`.
- O autocomplete usa apenas a lista publica de `config.lua`.
- Comandos administrativos e tecnicos nao aparecem nas sugestoes.
- Eventos `chat:addMessage`, `chat:clear` e `chatMessage` continuam aparecendo.
- `/pd` e privado para Policia, EMS, Bombeiros e Mecanicos em servico.
- As permissoes originais de cada comando continuam pertencendo ao recurso que
  registrou o comando.

Mantenha no `server.cfg`:

```cfg
setr chat_showJoins false
setr chat_showQuits false
stop chat
```

O recurso fica em `[system]` e inicia automaticamente no proximo boot. Para
ativar durante o desenvolvimento:

```text
refresh
ensure ob_chat
```
