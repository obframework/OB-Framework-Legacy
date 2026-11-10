# ob_drugselling

Venda original para pedestres usando `ob_target`.

- O NPC compra de 1 a 3 unidades.
- O preco aumenta com policiais em servico e com a variedade de drogas carregada.
- Ha recusa, denuncia e chance de furto. O alerta policial mostra somente uma area deslocada por 10 segundos.
- Denuncias sao enviadas pela central compartilhada `ob_dispatch`.
- Quando ocorre furto, somente o dono pode revistar o corpo do NPC morto e recuperar a mercadoria.
- Item, quantidade, preco, distancia, entidade e propriedade da recuperacao sao validados no servidor.

Valores e chances ficam em `config.lua`.
