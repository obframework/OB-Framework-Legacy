# ob_police

Primeira etapa do sistema policial da OB Framework:

- algemar e desalgemar;
- escoltar pessoa algemada;
- revistar e apreender por slot, preservando metadata;
- revista por `ob_target` e escolta pela tecla `H`;
- permissao `police` e servico validados pelo `ob_org`;
- distancia, estado e rate limit validados no servidor.

## Algemas como itens

- `handcuffs`: ao algemar, sai da mochila e vira `handcuff_key`;
- `handcuff_key`: ao desalgemar, sai da mochila e devolve `handcuffs`;
- `lockpick` e `advanced_lockpick`: podem arrombar a algema de outra pessoa;
- uma lockpick bem-sucedida e consumida e a algema arrombada nao e recuperada;
- na falha, a chance de quebra e configurada em `shared/config.lua`.

Ao usar a algema ou a chave, o personagem que executa a acao toca uma animacao
curta. A pessoa algemada usa a pose `mp_arresting/idle` e recebe o prop nativo
`p_cs_cuffs_02_s`, configuravel em `shared/config.lua`.

Qualquer pessoa que possuir os itens pode usa-los diretamente pelo inventario.
Nao existe atalho de algema no F1: algemar e desalgemar depende exclusivamente
do uso de `handcuffs`, `handcuff_key` ou uma lockpick pela mochila.

O minigame de algema usa sete etapas na lockpick comum, com velocidade maior
e tolerancia menor que o arrombamento de veiculos. Sem uma pessoa algemada
proxima, a lockpick continua sendo encaminhada normalmente ao `ob_garage`.

O estado publico usado pelas integracoes e `ob:restrained`. O `ob_radiumenu`
ja reconhece esse estado para colocar e retirar a pessoa de um veiculo.

Policiais em servico usam `H` para iniciar ou encerrar a escolta da pessoa
algemada mais proxima. A busca do alvo e a permissao do `H` sao feitas no
servidor. A revista aparece no `ob_target` somente sobre uma
pessoa algemada; os itens apreendidos sao transferidos para o policial.

Esta etapa ainda nao inclui multas, ficha, licencas, evidencias, dispatch ou
apreensao persistente de veiculos; esses contratos pertencerao ao ob_justice.
