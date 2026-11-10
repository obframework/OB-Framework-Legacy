# ob_utillitruck (Legacy)

Adaptacao do [smoke_utillitruck 1.0.3](https://github.com/BigSmoKe07/smoke_utillitruck)
para a OB Framework. Modelo e codigo originais: BigSmoKe07 e PNWParksFan.
Licenca GPL-3.0 preservada em `LICENSE`. Codigo adaptado sem `ox_lib`.

Spawn code: `utillitruck4` (nao substitui o `utillitruck` original do GTA).
Entre como motorista, pressione H para baixar os pes estabilizadores e use
as setas para subir/descer ou girar a cesta. H recolhe os pes. A colisao
invisivel da cesta e criada localmente para cada jogador proximo. O servidor
valida que quem controla e o motorista e publica as animacoes nas statebags;
o cliente nao grava nelas, compativel com `sv_stateBagStrictMode true`.

Os arquivos `.yft`, `.ytd` e `.ycd` desta copia sao os originais Legacy do
download. A copia Enhanced convertida esta em
`corerp/resources/[cars]/ob_utillitruck`; o download original nao foi alterado.

O `server.cfg` inicia `[cars]`. Para testar sem reiniciar o servidor, use
`refresh` e `ensure ob_utillitruck`, depois `/car utillitruck4` e teste com
outro jogador observando a cesta. Validacao estatica nao substitui teste em jogo.
