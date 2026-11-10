# ob_target

Sistema leve de interacao por olhar da OB Framework. Ele nao contem regras de
emprego, inventario ou permissoes; cada modulo registra e valida sua propria
acao no servidor.

## Uso padrão

Segure **Alt esquerdo** e mire no alvo. O indicador central acende quando uma
opção está disponível, mas a câmera continua presa. Clique uma vez com o
botão esquerdo para liberar o cursor e clique na opção para confirmá-la.
Soltar Alt cancela a interação. O atalho pode ser remapeado pelo jogador nas
configurações de teclas do FiveM.

## Jogadores

```lua
exports.ob_target:AddPlayerOption('meu_recurso:reviver', {
    label = 'Reanimar jogador',
    icon = '+',
    event = 'meu_recurso:client:reviver',
    stateKey = 'or:downed',
    stateValue = true,
    distance = 2.2,
})

RegisterNetEvent('meu_recurso:client:reviver', function(targetServerId)
    -- Envie targetServerId ao servidor e valide distancia/permissao/item la.
end)
```

## Entidades

```lua
exports.ob_target:AddEntityOption('meu_recurso:porta', {
    label = 'Abrir porta',
    event = 'meu_recurso:client:abrirPorta',
    entityType = 3, -- objeto; 1 ped, 2 veiculo, 3 objeto
    distance = 2.0,
})

RegisterNetEvent('meu_recurso:client:abrirPorta', function(entity)
    -- entity e local ao cliente; valide toda acao relevante no servidor.
end)
```

Use `RemovePlayerOption(id)` ou `RemoveEntityOption(id)` para retirar uma
opcao. `canInteract` pode ser uma funcao local que retorna `true`/`false`.

## Restart independente

As opcoes do target sao locais ao `ob_target`. Se o recurso for reiniciado,
entidades que ja existiam nao sao recriadas; o recurso dono delas deve apenas
registrar suas opcoes novamente ao receber o evento abaixo:

```lua
AddEventHandler('ob_target:client:ready', function()
    -- registre novamente as opcoes dos peds, veiculos ou zonas ainda ativos
end)
```

Os modulos proprios de saude e lojas ja fazem isso. Assim `restart ob_target`
nao exige reiniciar `ob_core` nem reconectar jogadores.
