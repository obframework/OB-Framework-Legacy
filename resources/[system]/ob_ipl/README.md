# OB IPL

`config.lua` controla interiores, mansoes e Cayo Perico. Nao iniciar outro
loader dos mesmos IPLs simultaneamente, pois eles podem alternar os conjuntos.

## Mansoes

Build minimo 3717, conforme bob74_ipl 2.6.0. Alem dos IPLs, `mansions.lua`
ativa estilo, elevador, arte, papel de parede e tablets. Configuracao padrao:
estilo `cali`, cor creme, papel `deco`. IDs de referencia sao conferidos pela
localizacao antes de usar; o andar principal possui fallback por coordenadas.
Os interiores sao tentados novamente quando o streaming fica pronto.

- Vinewood: 543.852, 712.754, 201.0
- Richman: -1630.434, 470.852, 128.0
- Tongva: -2601.712, 1874.826, 166.0

Referencias de conjuntos em `LICENSE.bob74`; nao depende do bob74_ipl.

## Cayo Perico

Build minimo 2189. Carrega a ilha ao chegar a 2250 m do centro e descarrega
ao passar de 2500 m; a diferenca evita alternar o streaming na borda.
`showOnMap` habilita desenho no mapa de pausa e minimapa local; `showBlip`
adiciona o destino Cayo Perico. Nenhum teleporte automatico e criado.

Natives: SetIslandEnabled / SetIslandHopperEnabled, SetUseIslandMap /
SetToggleMinimapHeistIsland. Referencias:
https://github.com/citizenfx/natives/blob/master/STREAMING/SetIslandEnabled.md
https://github.com/citizenfx/natives/blob/master/HUD/SetUseIslandMap.md

## Verificacao

`node tests/ob-tuning-ipl-check.cjs` na raiz da base testa sintaxe e natives
simuladas. Ainda e necessario conferir a renderizacao no GTA:

1. `restart ob_ipl` e entrar nas tres mansoes, incluindo os andares inferiores.
2. Abrir o mapa em Los Santos e localizar a ilha/blip.
3. Ir ate Cayo, verificar terreno, colisao, interiores e minimapa.
4. Voltar a Los Santos e verificar se o minimapa voltou ao normal.
5. Repetir apos reiniciar o recurso; observar F8 para erros.
