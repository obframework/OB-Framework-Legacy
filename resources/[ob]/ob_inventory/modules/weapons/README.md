# weapons

Modulo interno de armas da OB Framework.

- `data/weapons.lua`: cadastra armas, pesos e compatibilidade dos acessorios.
- Armas sao itens permanentes: usar equipa a arma, sem consumir o item.
- Acessorios tambem sao itens: selecione-o no inventario com a arma compativel
  na mao. O acessorio e consumido somente depois de ser instalado.
- Municao e separada por grupo: pistola, submetralhadora, escopeta, fuzil,
  metralhadora e sniper. Ela so e consumida se a arma compativel recebeu carga.
- Lancadores, explosivos, railgun e minigun nao entram no catalogo padrao.

As imagens seguem o mesmo padrao do inventario:
`html/assets/items/<nome-do-item>.png`. Exemplo:
`weapon_pistol.png` e `weapon_component_suppressor.png`.
