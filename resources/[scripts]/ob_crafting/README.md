# ob_crafting

Fabricacao original integrada a CoreRP. As bancadas e receitas ficam em `config.lua`.

- Target nas bancadas, NUI no padrao visual dos empregos e progresso persistente.
- Materiais sao reservados no servidor antes da animacao.
- Cancelamento devolve tudo; falha devolve a porcentagem configurada.
- Armas recebem numero de serie, qualidade, autor e data em metadata.
- Receitas com `blueprint = true` exigem projeto. Staff usa `/darprojeto [id] [receita]`.

Reinicie `ob_inventory` apos instalar, para carregar os novos itens, e depois inicie `ob_crafting`.

## Modos de bancada

- `mode = 'public'`: usa nivel, XP, estatisticas e projetos.
- `mode = 'private'`: ignora nivel, XP e projetos; exige um dos grupos de `groups`.
- `requireDuty = true`: o integrante precisa estar em servico no grupo.

Exemplo privado:

```lua
private_gunsmith = {
    label = 'Armeiro da organizacao', category = 'weapons', mode = 'private',
    groups = { 'police' }, requireDuty = true,
    coords = vector3(0.0, 0.0, 0.0), radius = 1.3, icon = '🔩',
    visual = { type = 'prop', model = 'gr_prop_gr_lathe_01b', heading = 0.0, placeOnGround = true },
}
```

Cada receita continua apontando para uma bancada exata com `station = 'private_gunsmith'`.

## Visual da bancada

`visual.type` aceita `prop` ou `ped`. `visual.coords` e opcional; quando omitido,
usa as coordenadas da zona. Para remover o visual sem remover o craft, apague `visual`.
Para deixar uma bancada cadastrada sem cria-la no mapa, use `enabled = false`.
