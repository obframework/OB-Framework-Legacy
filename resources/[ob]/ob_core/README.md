# `ob_core`

API pública e guia para recursos da OB Framework:

[`docs/API_CORE.md`](../../../docs/API_CORE.md)

Use somente os exports e eventos documentados. Não acesse `ORCore.Players`
diretamente em outro recurso.

## Props temporarios sincronizados

Carregue o modelo antes de criar o objeto. O terceiro parametro escolhe entre
`CreateObject` (`true`) e `CreateObjectNoOffset` (`false`).

```lua
local object, netId = exports.ob_core:CreateNetworkedObject(model, coords, false)
exports.ob_core:DeleteNetworkedObject(object)
```

Use estes exports para objetos de gameplay presos ao jogador ou que precisam
ser vistos pelos demais clientes. Objetos puramente locais de interface ou
pre-visualizacao nao precisam ser entidades de rede.
