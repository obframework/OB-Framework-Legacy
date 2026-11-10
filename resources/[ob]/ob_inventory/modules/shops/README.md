# Módulo de lojas

As lojas pertencerão ao inventário e seguirão esta estrutura:

```text
data/shops.lua
modules/shops/client/main.lua
modules/shops/server/main.lua
```

O módulo deve entregar/remover itens somente pelos exports de `ob_inventory`.
Assim preço, estoque, NUI e validação ficam no módulo, sem alterar o núcleo.
# Grupos, lojas e comercio de jogadores

O editor agora separa **Grupos** de **Locais**. O grupo guarda atendente, blip,
permissao, moeda e catalogo; cada local guarda apenas nome, grupo, coordenadas e
os pontos da entrega. Alterar um grupo atualiza todas as lojas ligadas a ele.

Somente grupos com `category = convenience` e `purchasable = true` podem ser
comprados. Ammu-Nation e os demais grupos continuam exclusivamente publicos.
Lojas sem dono usam o catalogo padrao com estoque infinito. Quando compradas,
passam a descontar estoque persistente e a creditar o lucro liquido no caixa da
loja. O imposto de venda sempre e retido. Quando o `ob_economy` esta ativo ele
e creditado no Tesouro; em modo monitor, desativado ou indisponivel, permanece
registrado na loja e e retirado da economia localmente.

O proprietario usa `/comercio` ou o NPC de gerenciamento para renomear a loja,
depositar/sacar caixa, alterar precos e solicitar reposicao para uma ou varias
lojas. A entrega por motorista precisa destes pontos no local:

- `manager`: NPC de compra e gerenciamento;
- `truckStop`: parada do caminhao na loja;
- `dropoff`: ponto em que o entregador entrega a caixa.

O caminhao nao possui ponto de nascimento manual. A cada pedido o cliente procura
uma via livre e valida entre 500 metros e 2 km da parada configurada. Se nenhuma
entrada segura for encontrada, o pedido e cancelado e o valor retorna ao caixa.

As tabelas e a migracao dos cadastros antigos sao criadas automaticamente no
primeiro start. A parte empresarial e tolerante a falhas: se ela ou o banco
estiverem indisponiveis, as lojas publicas continuam carregando e vendendo pelo
catalogo normal.
