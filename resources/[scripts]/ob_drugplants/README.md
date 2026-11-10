# ob_drugplants

Cultivo persistente integrado ao `ob_inventory`, `ob_target` e `ob_crafting`.

## Fluxo

1. Use `Vaso de plantio` e confirme a posição com **E**. Setas giram e Backspace cancela.
2. Perto do vaso vazio, use `Semente de maconha` ou `Semente de coca`.
3. Use o `Regador` e o `Fertilizante` quando os níveis estiverem baixos.
4. Pelo alvo da planta é possível consultar crescimento, água, nutrientes e saúde.
5. Em 100%, use o alvo para colher. Cada vaso suporta 5 plantios; enquanto ainda tiver usos, volta ao inventário com a contagem preservada. Há chance de recuperar uma semente.
6. Processe as folhas na bancada `Laboratório clandestino` do `ob_crafting`.

O crescimento usa tempo real e fica persistido em `ob_drug_plants`. Por padrão, uma planta saudável leva cerca de 5 minutos; fertilizada, cerca de 3 minutos. O target mostra a porcentagem e o tempo estimado restante. Falta de água ou nutrientes reduz a saúde; excesso de água também prejudica. Plantas mortas não produzem e precisam ser limpas.

O regador suporta 10 regas. Vasos, sementes, folhas, pasta de coca e os produtos finais de maconha/coca não vencem por tempo; apenas vaso e regador gastam usos.

## Configuração

Todas as regras ficam em `config.lua`: limites, distância entre vasos, tempo de crescimento, consumo de água/nutrientes, dano, rendimento, chance de semente e modelos por estágio.

O GTA V não possui um modelo nativo específico de coca. Por isso a coca usa variantes visuais dos props nativos de cultivo. Eles podem ser substituídos no `config.lua` por props customizados sem alterar o código.

O recurso está na pasta `[scripts]`, que já é iniciada pelo `ensure [scripts]` da base.

