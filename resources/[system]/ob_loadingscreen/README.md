# OB Loading Screen

Tela de carregamento do OB Framework baseada no video oficial de 60 segundos.
Inclui a musica `Bonde da OB`, com volume inicial de 32%. A tecla `M` silencia
ou reativa a musica durante o carregamento.

## Ativacao

O recurso fica em `[system]`, grupo que ja e iniciado pelo `server.cfg`.
Para aplicar sem reiniciar a cidade inteira, use no console do servidor:

```text
refresh
restart ob_loadingscreen
restart ob_multichar
```

O encerramento e manual: a tela permanece visivel durante `Awaiting scripts` e
o `ob_multichar` a fecha depois de preparar o personagem, a colisao e a camera
da selecao. Se a consulta de personagens falhar, a tela tambem e fechada para
que o jogador consiga ver a notificacao do erro.
