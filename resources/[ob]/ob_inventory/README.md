# ob_inventory

Inventario persistente por `user_id` fixo da OB Framework. Cada dono possui
uma unica linha em `ob_inventories`, com todos os slots e metadata em JSON.
Na primeira inicializacao, os registros da tabela antiga `ob_inventory_items`
sao importados sem apagar a tabela anterior, que fica como backup.

Itens no chao existem somente em memoria: aparecem ate 100 metros, exigem
aproximacao para abrir e expiram em 10 minutos. Esses valores ficam em
`data/config.lua`.

## Estrutura modular

```text
data/config.lua        configuracao base do inventario
data/items.lua         catalogo de itens
data/needs.lua         configuracao de fome, sede e estresse
data/shops.lua         catalogo, NPCs, blips e permissoes das lojas
modules/inventory/     modulo-base: NUI, slots, peso e persistencia
modules/needs/         codigo cliente/servidor do modulo needs
modules/shops/         modulo de lojas integrado a mesma NUI do inventario
```

## Mochilas e slots bloqueados

O personagem inicia com 30 slots. Cada item `mochila` usado adiciona 10 kg e
10 slots, ate o limite configurado de tres mochilas (50 kg e 60 slots).

Ao morrer, todos os itens e as melhorias equipadas sao apagados. Fora desse
fluxo, se a capacidade for reduzida com itens em slots excedentes, esses slots
permanecem visiveis em cinza: seus itens podem ser usados, retirados ou movidos
para um slot ativo vazio, mas o slot bloqueado nao aceita item novo nem troca
com outro slot.

O antigo recurso `ob_needs` foi incorporado a `modules/needs`; nao existe mais
como recurso separado.

## Imagens dos itens

Por padrao, cada item busca `html/assets/items/<nome-do-item>.png`. A pasta ja
esta pronta e possui as instrucoes em `html/assets/items/README.md`. Caso a
imagem nao exista, a interface mantem o icone em letra como reserva.

## API de servidor

```lua
local ok, reason = exports.ob_inventory:AddItem(source, 'bandage', 2)
local inventory, reason = exports.ob_inventory:GetInventory(source)
```

Entrega de itens e uma acao administrativa. Use dentro do jogo, com um cargo
que tenha a permissao `inventory.give`:

```
/giveitem 1 bandage 3
/giveitem 1 adrenaline 1
```

O primeiro argumento e sempre o `user_id` fixo do personagem (nao o ID
temporario da sessao/FiveM). O personagem deve estar conectado e ja ter
entrado na cidade.

O item `adrenaline` e usado pelo `ob_target` em uma pessoa incapacitada; a
validacao de distancia e da area ilegal continua no `ob_health` do servidor.

## Modulo de necessidades

Fome, sede e estresse sao um modulo interno deste recurso. Os valores continuam
no state bag `or:needs`, portanto a HUD permanece compativel. Pao recupera 25
de fome e agua recupera 25 de sede; os valores ficam em `data/items.lua`.
