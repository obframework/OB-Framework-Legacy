# OB Pause Menu

Menu de pausa experimental da **OB Framework**.

## Uso

- `ESC`: abre o menu quando o personagem estiver carregado e nenhuma outra NUI estiver em uso.
- `/obmenu`: comando alternativo para abrir ou fechar.
- **Mapa** abre o atlas interno com posicao real, blips visiveis no cliente, zoom, arraste e clique para marcar GPS.
- O atlas oferece um botao separado para abrir o mapa nativo completo.
- **Configuracoes do GTA** abre diretamente a aba nativa de configuracoes.
- O botao **HUD e graficos** abre o menu existente do `ob_hud`.

O recurso fica dentro de `[system]`, que ja e iniciado como grupo no `server.cfg`.

## Observacao de teste

A estrutura Lua, HTML e JavaScript pode ser validada fora do jogo, mas a captura do ESC e o frontend nativo devem ser testados em um cliente Legacy e em um Enhanced.
