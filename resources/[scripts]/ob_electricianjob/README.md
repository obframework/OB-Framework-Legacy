# Electrician Job

Trabalho de eletricista individual ou cooperativo. A NUI segue o padrão visual dos empregos de ônibus e táxi, mantendo o amarelo como identidade do eletricista. A aba Ranking mostra os 50 melhores por XP ou reparos e calcula a colocação do personagem atual.

## Fluxo atual

1. Use o target no encarregado, monte uma dupla opcional e inicie o turno.
2. Retire o `utillitruck4` e siga o GPS até a caixa ou o poste.
3. Quando o caminhão estiver na área do chamado, aparecem dois cones pequenos: um em cada lateral do veículo.
4. Em qualquer uma das laterais, pressione E para pegar a ferramenta indicada no HUD.
5. Vá ao defeito e pressione E para iniciar a etapa: abrir/isolar, reconectar cabos e testar a tensão.
6. Entre as etapas, volte a qualquer lateral para guardar a ferramenta usada e pegar a próxima.
7. Depois das três etapas, guarde a última ferramenta e finalize o chamado em qualquer lateral do caminhão.
8. A cada cinco chamados completos, todos os integrantes recebem o dinheiro acumulado e 150 XP (30 por chamado, configurável).

Não existe mais caixa de ferramentas física. O NPC continua usando `ob_target`; as interações do serviço usam cones pequenos `MarkerTypeUpsideDownCone`, texto 3D e a tecla E. Os cones laterais só aparecem com o caminhão parado e a até `truckTaskDistance` do chamado.

Finalizar o turno antes de completar os cinco chamados descarta a rota parcial. Se faltar espaço no inventário no pagamento, libere espaço e tente finalizar o chamado novamente; quem já recebeu não recebe em duplicidade.

Os minigames são próprios deste recurso (`ui/repair.js`). Cada tentativa tem 60 segundos; cabos e tensão permitem duas falhas e encerram na terceira. ESC cancela sem avançar. O cliente também cancela por morte ou afastamento, e o servidor libera etapas que excedem o limite.

Uma pessoa recebe somente chamados no solo. Os chamados aéreos entram no sorteio apenas com dois integrantes e exigem que um parceiro esteja no banco do motorista controlando a cesta. As duas pessoas recebem uma chave temporária do mesmo caminhão.

## Pontos do mapa

Os sete pontos ficam em `config.lua`. `search` é a posição exata do objeto elétrico e o destino do GPS. O cliente procura o modelo configurado num raio de 2 metros por native e pelo pool de objetos. A busca se repete perto do destino para acompanhar o carregamento do mapa.

Sem entidade confirmada, não existe reparo invisível: após 10 segundos perto do destino, E solicita outro chamado. O cone amarelo marca o reparo no objeto e as faíscas usam `core/ent_sht_electrical_box`. Depois de isolar o circuito na primeira etapa, as faíscas cessam.

Use `/eletricistaponto nome` para imprimir no F8 a coordenada e o objeto mais próximo. Use `/eletricistaoffset` mirando na parte visual do defeito para obter o offset local. Esses comandos apenas leem e imprimem dados.

## Aplicação e teste

Para aplicar sem reiniciar toda a cidade:

```text
restart ob_electricianjob
```

Teste no FiveM com uma e duas pessoas. Confirme os dois lados do caminhão, troca das três ferramentas, todos os sete pontos, faíscas, minigames, pagamento, cesta e desconexão de um integrante durante o turno.

`tests/validate.cjs` valida a sintaxe Lua disponível e exercita a NUI em navegador headless. `tests/validate_server.py` executa o fluxo do servidor quando a dependência Lupa/Lua 5.4 está instalada. Validação estática não substitui o teste dentro do jogo.
