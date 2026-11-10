# OB HUD

HUD da OB Framework com status do jogador, voz, municao, minimapa e painel do
veiculo.

## Personalizacao

- `O` ou `/hudconfig`: abre o menu local.
- Temas: Classica, Clean e Racing. A chave interna da Classica continua sendo
  `current` para preservar as preferencias que ja estavam salvas.
- Clean posiciona o minimapa no canto superior direito; Racing usa o superior esquerdo.
- Filtros visuais: Original, Realista, Natural, Cinema, Vibrante e Contraste.
  As variacoes usam intensidade moderada para preservar noite e interiores.
- Avioes e helicopteros ativam automaticamente instrumentos de voo em nos e pes,
  com velocidade sobre o solo, altitudes MSL/AGL, razao vertical, rumo e atitude.
- Desempenho: Original, Equilibrado, Desempenho e FPS maximo.
- As escolhas sao salvas localmente por jogador usando KVP do FiveM.

Os filtros sao apenas visuais e nao modificam o clima sincronizado. Somente os
perfis Desempenho e FPS maximo reaplicam LOD por frame, pois essa native exige
aplicacao continua. No perfil Original esse processamento fica adormecido.

## Configuracao

`config.lua` controla o tema inicial (`DefaultTheme`), unidade de velocidade,
intervalo da HUD, exibicao do minimapa fora do veiculo, logo e tecla padrao do
menu. Os temas aceitos sao `current`, `clean` e `racing`; a escolha individual
salva pelo jogador continua tendo prioridade.

## Validacao em jogo

`RectangularMinimap = true` carrega apenas a mascara retangular do HUD de
referencia orbis-hudorbis. `stream/ob_hud_radarmask.ytd` e Legacy;
`stream_enhanced/ob_hud_radarmask.ytd` foi convertido pelo Alchemist para Enhanced.
O FiveM seleciona a pasta da edicao automaticamente. Copie ambas ao distribuir
o recurso. Nao ha substituicao de minimap.gfx ou minimap.ytd.
Se a textura nao carregar em 10 segundos, o radar nativo permanece e o F8
registra a falha. Para voltar ao nativo, defina RectangularMinimap = false e
reinicie o recurso. A conversao nao substitui o teste visual nas duas edicoes.

A NUI e a sintaxe podem ser verificadas fora do jogo, mas posicao real do
minimapa, filtros e ganho de FPS precisam ser comparados em um cliente FiveM.
