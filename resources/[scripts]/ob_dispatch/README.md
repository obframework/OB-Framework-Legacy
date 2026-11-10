# ob_dispatch

Central de chamados da CoreRP para policia, EMS e outros grupos em servico.

## Criar chamado em outro recurso (servidor)

```lua
exports.ob_dispatch:CreateAlert('medical_emergency', {
    actorSource = source, -- opcional; valida a posicao real do jogador
    coords = GetEntityCoords(GetPlayerPed(source)),
    message = 'Pessoa inconsciente apos uma queda.',
    metadata = { origin = 'ob_health' },
})
```

Tambem pode ser usado por evento exclusivamente server-side:

```lua
TriggerEvent('ob_dispatch:server:createAlert', 'traffic_accident', { coords = vector3(0.0, 0.0, 0.0) })
```

O evento rejeita chamadas vindas de clientes. Para novos tipos, copie um bloco de `Dispatch.types` em `config.lua`.
Cada tipo controla grupos em servico, codigo, prioridade, mensagem, raio, deslocamento, blip, som e duracao.

Exports adicionais:

- `RegisterType(id, definition)`: registra um tipo em tempo de execucao por outro recurso servidor.
- `CountOnDuty(group)`: quantidade de membros em servico.
- `GetActiveCalls()`: snapshot dos chamados ainda ativos.

O jogador em servico recebe um cartao no canto da tela. `Y` aceita e marca a rota do ultimo chamado, `N` dispensa o cartao e `F2` abre a central com todas as ocorrencias ativas e seus botoes de GPS. As teclas podem ser alteradas em `config.lua`.

## Aplicativo Emergencia

O recurso registra automaticamente no `ob_phone` o aplicativo padrao `Emergencia`. O cidadao pode solicitar Policia (grupo `police`) ou Medico (grupo `ambulance`) e enviar uma descricao curta junto da localizacao atual.

Chamados feitos pelo aplicativo sao exclusivos: o servidor entrega a ocorrencia ao primeiro profissional em servico que aceitar. Depois do aceite, ela e removida do cartao e do `F2` de todos os demais destinatarios, enquanto o vencedor recebe a rota no GPS. Ao abrir o `F2`, a lista e sincronizada novamente com o servidor e filtrada pelas permissoes em servico do jogador.
