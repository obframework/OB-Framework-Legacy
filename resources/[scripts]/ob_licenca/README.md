# ob_licenca

Recurso OB independente de QBCore/Qbox/ox_lib/idcard. Instalado na Enhanced em
`resources/[scripts]/ob_licenca`. Rotas e banco de perguntas aproveitados do
orbis-licenca; servidor, cliente e interface proprios para a OB Framework.

## Instalar e usar

Na primeira instalacao, use `refresh` e `ensure ob_licenca`. O grupo `[scripts]`
do server.cfg inicia o recurso automaticamente nos proximos boots. A tabela
`ob_licenses` e criada por este recurso. `ob_documents` nao e dependencia:
quando presente, acrescenta a CNH fisica, validade e renovacao; quando ausente,
provas, categorias e o export `HasLicense` continuam funcionando normalmente.

Instrutor/blip Centro de Licencas: 218.3152, -1391.3157, 30.5875.
Use ob_target no instrutor ou `/licenca` estando proximo.
Categorias: moto (A), carro (B), caminhao (C), barco e helicoptero (RP).
Teorica: $5.000, 10 perguntas da categoria escolhida, 2 minutos e 30 segundos,
ate 3 erros. Perguntas curtas e respostas embaralhadas; gabarito permanece no
servidor. Nao existe bypass para admin.
Primeira pratica apos teorica: gratuita. Reteste: $2.000 terrestres / $3.000 barco
e helicoptero. Consulte config.lua para alterar taxas, NPC, rotas e limites.

Pagamento usa ob_economy quando ativo; fallback cartao ob_bank ou dinheiro
ob_inventory. Nao divide uma taxa entre cartao e dinheiro. Falha antes de iniciar
estorna quando a mesma sessao ainda esta disponivel; se a pessoa desconectar
nessa janela, o console registra ESTORNO PENDENTE para atendimento administrativo.

Pratica em instancia individual, com veiculo e chave via ob_core/ob_vehiclekeys.
Siga os pontos azuis e limites de velocidade. Servidor verifica veiculo, motorista,
sequencia, posicao, tempo, velocidade e danos. O cliente nao envia aprovacao.
Excesso de velocidade por mais de 2s e danos relevantes geram penalidades.
Morte, sair do banco do motorista, timeout ou `/cancelarprova` encerram a tentativa.
O recurso nao revive o jogador nem altera o ob_health. Taxas de provas ja iniciadas
nao sao reembolsadas. A prova limpa o veiculo e retorna ao centro ao terminar.

## CNH e consulta policial

O `ob_licenca` cuida das provas e oferece no instrutor apenas os servicos da CNH.
A CNH mostra as categorias obtidas e quantos dias restam. A validade oficial e de
14 dias, sem usar/desgastar a durabilidade do item. Renovacao custa $1.500 e a
segunda via perdida custa $2.500. Se estiver vencida e perdida, as duas taxas sao
cobradas juntas. A primeira emissao ocorre gratuitamente ao concluir a primeira
categoria.

O `identity_card` nao e emitido nem substituido no instrutor. Sua emissao inicial
e segunda via ficam no recurso separado `ob_documents`, para serem acionadas pelo
futuro kit inicial e pelo futuro local de identificacao. Somente policia em servico
pode consultar terceiros: ob_target na pessoa -> Consultar documentos, ou
`/verlicenca ID_DO_PERSONAGEM`, ate 4m e na mesma instancia.
Mostra nome, ID fixo, nascimento, nacionalidade, trabalho legal, validade e categorias;
nao expoe Discord, license/Rockstar, IP, saldo ou outros metadados privados.
Consulta e emissao ficam registradas no console. Owner/admin nao burla policia.

Export de compatibilidade apenas servidor:
`exports.ob_licenca:HasLicense(userId, 'car')` -> boolean. A implementacao oficial
fica em `exports.ob_documents:HasLicense(...)`.
Nao bloqueia garagem/concessionaria automaticamente e nao altera outros recursos.

## Dependencias e ciclo de vida

ob_lib, ob_database, ob_core e ob_inventory obrigatorios no servidor. `ob_database` e
`server_only`, por isso nao pode constar em `dependencies` do fxmanifest:
ele e importado apenas pelos scripts de servidor. ob_vehiclekeys necessario na pratica;
ob_org necessario para consultas policiais; ob_notification para avisos. ob_target
opcional (comando /licenca disponivel). Chaves, combustivel e notificacoes usam a base.
ob_documents e uma integracao opcional e nao consta nas dependencias do manifesto.
BucketBase 510000 + source: reserve essa faixa para a autoescola; o script recusa
iniciar se outro jogador ja estiver nessa instancia. Reinicio cancela provas em
andamento, mas conserva teoricas aprovadas, tentativas e habilitacoes no banco.

## Teste no jogo pendente

1. Civil: exame teorico completo, erro/timeout/cancelamento e tentativa duplicada.
2. Praticas nas 5 categorias, chave/ignicao Z, velocidade, danos e devolucao.
3. Receber a CNH, obter nova categoria e conferir a atualizacao no mesmo item.
4. Testar vencimento, renovacao e segunda via da CNH com as taxas corretas.
5. Consulta policial em servico, fora de servico, por civil e longe do alvo.
6. Restart/desconexao durante a prova: limpar veiculo/cursor e restaurar instancia.

Testes em tests/ob-licenca-check.cjs simulam natives/SQL; nao validam o FiveM real.
