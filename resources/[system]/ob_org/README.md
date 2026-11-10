# ob_org

Sistema independente de organizacoes da OB Framework. Toda organizacao,
cargo, permissao, salario, ponto, meta e rota e criada em runtime pelo painel;
o `shared/config.lua` contem apenas regras globais.

Criacao, edicao e exclusao de cargos, permissoes dos cargos e o editor completo
de rotas sao exclusivos do `/adminorg`. Liderancas podem administrar somente
os dados operacionais liberados ao cargo, como membros, identidade e metas.

## Comandos

- `/adminorg`: administracao e criacao de organizacoes.
- `/painel`: organizacao legal do personagem.
- `/tablet`: organizacao ilegal do personagem.

Cada personagem pode pertencer a somente uma organizacao. Quando removido,
entra na blacklist global pelo numero de dias definido em `BlacklistDays`.
O `/adminorg` mostra os bloqueios ativos e permite liberar um ID manualmente.

## Central provisoria de empregos

O `ob_jobcenter` usa exports de servidor deste recurso para listar somente
organizacoes legais ativas, contratar no menor cargo e registrar uma saida
voluntaria com prazo minimo e blacklist proprios. A gravacao continua sendo
responsabilidade do `ob_org`, incluindo a atualizacao do emprego, state bag e
acesso ao `/painel`.

## Blips de equipes em servico

O proprio `ob_org` mostra no mapa os membros online das organizacoes legais
enquanto estiverem em servico. No `/adminorg`, selecione uma organizacao legal
e abra `Blips de servico` para definir se ela aparece, nome, icone, cor,
tamanho, icone de helicoptero e quais organizacoes podem enxerga-la.

As escolhas ficam em `ob_org_duty_blips`. O `shared/config.lua` mantem apenas
intervalo e valores tecnicos padrao. Organizacoes antigas recebem uma
configuracao inicial automaticamente e organizacoes novas sao cadastradas ao
serem criadas. As coordenadas sao consolidadas pelo servidor e enviadas apenas
aos servicos autorizados; nao ha consulta ao banco a cada atualizacao.

## Ordem de inicio

O recurso depende de `ob_core`, `ob_inventory`, `ob_admin`, `ob_lib` e
`ob_database`. O `server.cfg` atual inicia `[system]` depois desses recursos,
portanto `ob_org` sera encontrado automaticamente no proximo boot.

Como o core recebeu o registro dinamico de empregos, para ativar manualmente
pela primeira vez reinicie o conjunto a partir de `ob_core` e depois confirme
que `ob_org` iniciou. Nao e necessario importar SQL: as tabelas sao criadas no
primeiro start.

## Metas e rotas

Metas ilegais sao diarias e individuais. Cada circuito completo de uma rota
adiciona `1` ao progresso daquele personagem em todas as metas ativas. O
ranking mostra circuitos concluidos em 7 e 30 dias.

O editor usa a posicao atual do administrador para o NPC e para cada ponto.
Durante a rota, `E` coleta e `F7` cancela. Recompensas, chances, quantidades e
limite de tipos por ponto sao validados e sorteados no servidor. O NPC aparece
somente no local de inicio; os pontos de coleta usam blip e marcador, sem NPC.
Excluir uma rota remove seus pontos e recompensas, mantendo apenas o historico
ja contabilizado no ranking.

## Baus de organizacao

Os baus sao criados somente no `/adminorg`, dentro da organizacao legal ou
ilegal selecionada. O local atual do administrador vira o marcador de acesso:
os membros aproximam-se e pressionam `E`.

- `Armazenamento`: quantidade de slots e peso maximo configuraveis. Usa a
  persistencia do `ob_inventory` e permite arrastar itens nos dois sentidos.
- `Descarte infinito`: aceita itens da mochila, apaga-os definitivamente e nao
  oferece retirada.

Cada bau pode ter um webhook do Discord. Entradas, saidas e descartes ficam
registrados em `ob_org_chest_logs` mesmo sem webhook. O segredo do webhook nao
e enviado para a NUI. Excluir um bau apaga seu inventario, mas preserva o
historico de auditoria.

Slots e peso podem ser aumentados ou reduzidos a qualquer momento. Se a nova
capacidade deixar itens acima do ultimo slot ou acima do peso, nada e apagado:
os slots excedentes ficam cinza e servem apenas para recuperar seus itens. O
bau volta a aceitar entradas conforme os itens forem retirados ou movidos para
a capacidade ativa.
