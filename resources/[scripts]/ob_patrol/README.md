# ob_patrol

Patrulhamento policial continuo para a CoreRP.

## Fluxo

- O NPC de Mission Row abre o painel pelo `ob_target` e nao possui blip.
- O lider monta um grupo de ate quatro policiais e escolhe Sul ou Norte.
- A patrulha nao termina ao completar uma rota: outra rota da mesma regiao e escolhida automaticamente.
- Cada checkpoint validado paga ao motorista entre $100 e $250.
- O pagamento, a ordem do checkpoint, a distancia e a viatura sao validados no servidor.
- O limitador da ronda e 60 km/h.

## Comandos

- `/patrulha`: ativa ou desativa o limitador e a participacao local nos checkpoints.
- `/patrulhasair`: encerra a patrulha; somente o lider pode encerrar o grupo.
- A patrulha tambem pode ser encerrada no painel do NPC.

## Rotas no banco

As tabelas `ob_patrol_routes` e `ob_patrol_route_points` sao criadas automaticamente. Na primeira inicializacao, as rotas de `Patrol.routes` e eventuais rotas do antigo `data/generated_routes.json` sao migradas como sementes.

A staff com `panel.open` abre o gerenciador separado com `/patrulharotas`. O painel do NPC permanece apenas para a patrulha e para o grupo. No gerenciador, a staff pode:

- criar uma rota;
- alterar nome e regiao;
- regravar todos os pontos;
- excluir uma rota.

Ao criar ou regravar, dirija e use `/patrulhaponto` em cada checkpoint. Salve com `/patrulhasalvar` ou cancele com `/patrulhacancelar`.

## Validacao no jogo

Depois de `ensure ob_patrol`, confira a criacao das duas tabelas, migracao das seis rotas, pagamentos, alternancia do limitador, troca automatica de rota, grupo e todas as operacoes do gerenciador de rotas. O grupo deve ser testado com pelo menos dois jogadores.
