# ob_moneywash

Lavagem de dinheiro da OB Framework. O recurso usa `black_money`, entrega `money`, persiste locais e transacoes no banco e valida no servidor distancia, saldo, tempo e propriedade da retirada.

## Uso

- Administracao: `/lavagemeditor` ou modulo opcional no `ob_adminmenu`.
- O atendente apenas confirma o valor e reserva uma maquina. O dinheiro sujo so e retirado quando o jogador usa o target da maquina amarela; a retirada do valor limpo tambem ocorre pelo target da mesma maquina.
- Cada local aceita de 1 a 20 maquinas. O editor permite capturar coordenadas, digitar os valores, posicionar a maquina visualmente e gerar automaticamente a posicao inicial da animacao.
- O marcador amarelo identifica a maquina reservada para o jogador. Maquinas ocupadas por outras pessoas aparecem em vermelho.
- A maquina concluida permanece aberta com o dinheiro visivel ate o proprietario retirar. As animacoes de deposito e retirada usam `prop_money_bag_01`.
- Os tres modelos da maquina ficam centralizados em `shared/config.lua`; o editor cuida apenas das maquinas, coordenadas e pontos de animacao.
- O campo `Grupo autorizado` aceita uma chave do `ob_org` (por exemplo, `police`). Vazio significa acesso publico.
- A taxa representa a parte retida. O padrao de 40% entrega 60% ao jogador.
- O tempo padrao e 60 segundos e pode ser diferente em cada local.

## Seguranca e auditoria

- A retirada de `black_money`, o cronometro e o pagamento de `money` sao validados no servidor.
- A reserva, a maquina atribuida, a distancia, o dono da operacao e a permissao de grupo sao validados novamente no servidor antes da retirada do dinheiro sujo.
- Cada operacao recebe um comprovante unico no formato `LW-00000001`.
- Antes de pagar, o servidor reserva a transacao no banco com o estado `paying`. Apenas uma solicitacao consegue alterar o estado e receber o valor.
- Os saldos anterior e posterior sao comparados tanto na retirada quanto no pagamento.
- Se o servidor reiniciar durante um pagamento ou o saldo final nao conferir, a operacao passa para `review` e nao e paga novamente automaticamente.
- O editor possui uma area de auditoria com busca por comprovante, ID da transacao, ID/nome do personagem, local e estado.
- Ao selecionar uma operacao, o painel mostra a linha do tempo dos eventos registrados em `ob_moneywash_audit`.
- Os indicadores destacam operacoes em revisao e qualquer transacao que possua mais de uma confirmacao de pagamento.

Para conferir uma reclamacao, abra `/lavagemeditor`, pesquise o comprovante informado pelo jogador e compare os eventos `wash_started`, `payout_claimed` e `payout_confirmed`. Casos `review` precisam ser verificados manualmente antes de qualquer compensacao.

O recurso e iniciado automaticamente quando `ensure [scripts]` ja existe no `server.cfg`. O `ob_adminmenu` nao e dependencia; se ele parar, o comando proprio continua disponivel.

## Validacao pendente

Os arquivos e contratos podem ser validados estaticamente, mas o fluxo financeiro precisa ser exercitado com o banco real e a posicao, orientacao dos props e animacoes precisam ser conferidas dentro do FiveM em Legacy e Enhanced. Use o editor para ajustar a posicao de interacao de cada maquina.

