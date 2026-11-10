# ob_prison

Sistema de prisão da OB Framework, integrado pelo ID fixo do personagem.

## Comandos

- `/prender [user_id] [meses] [motivo]`
- `/soltar [user_id] [motivo]`

Os dois comandos aceitam console. Em jogo exigem a permissão administrativa configurada.

## Integração

```lua
local ok, sentenceIdOrError = exports.ob_prison:SentenceByUserId(
    source, targetUserId, months, reason, mdtRecordId
)
```

`GetActiveSentence(userId)` consulta a pena ativa e `ReleaseByUserId` efetua a soltura.
As tabelas são criadas automaticamente pelo recurso.
