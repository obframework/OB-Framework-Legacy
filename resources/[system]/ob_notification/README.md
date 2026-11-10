# ob_notification

Notificacao padrao da OB Framework. Nenhum outro resource precisa ter NUI propria
para mensagens simples.

No cliente:

```lua
exports.ob_notification:Notify('Operacao concluida.', 'success')
TriggerEvent('ob_notification:client:notify', 'Algo deu errado.', 'error')
```

No servidor:

```lua
exports.ob_notification:Notify(playerSource, 'Voce recebeu um item.', 'success')
```

Tipos: `success`, `error`, `warning` e `info`. `OR.Notify(...)`, disponibilizado
por `ob_lib` nos resources clientes existentes, usa este resource automaticamente.
