# OB Vehicle Keys

Chaves, trancas e lockpick separados da garagem. Nao depende de `ob_garage`.
Os trabalhos usam `ob_core` para criar/remover veiculos; a garagem continua
responsavel por guardar/retirar e pelo cadastro dos carros pessoais.

## Configuracao

Em `config.lua`, `virtual = true` faz L usar a autorizacao do personagem,
sem item, inclusive ao retirar da garagem ou passar lockpick. `virtual = false`
usa `vehiclekey` no inventario. As chaves fisicas
podem ser transferidas pelo inventario e mostram a placa. O item sozinho nao
basta: o identificador da chave tambem e validado no banco.

O dono recebe a original ao retirar o carro. `/chave`, perto do veiculo,
reemite uma chave para o dono ou para um personagem que ja tenha uma reserva
registrada. Se faltar espaco no inventario, libere um slot e use `/chave`.

Z liga/desliga o motor (`EngineKey`). No modo fisico, ligar transfere a chave
para a ignicao; desligar devolve a mesma chave a mochila. O dono continua usando
L mesmo sem o item. Quem tem reserva so usa L com a chave na mochila.
Nao existe chave fisica no modo virtual. A ignicao guarda o item num inventario
persistente; se faltar espaco na devolucao, ela fica protegida e tenta novamente.
Ao guardar, a chave na ignicao permanece no veiculo; a chave carregada e movida
da mochila para esse mesmo inventario interno, removendo duplicatas carregadas.
Ao retirar o carro, a chave guardada volta a ficar na ignicao, sem emitir outra.
Z continua devolvendo a chave quando o motorista desliga manualmente.
O /dv e a remocao de temporarios descartam a chave, sem devolucao automatica.
O campo disposition na tabela de ignicao e migrado automaticamente.
O item na ignicao permite que outro motorista
conduza o veiculo e retire a chave ao desligar, como uma chave deixada no contato.

Lockpick fica neste recurso e usa o minigame existente, `ob_minigame`.
Sucesso concede uma reserva, sem mudar o dono ou revogar a original.
Falha e sucesso descontam um uso: normal 3, avancada 5 (definidos no inventario).
Cancelamento antes de iniciar nao desconta. O alvo e vinculado antes do minigame.

Reservas de carros cadastrados persistem em `ob_vehicle_keys` (criacao automatica).
Um novo proprietario gera outra identidade de chave: reservas do dono anterior
nao abrem o carro do comprador. Carros de NPC/trabalho usam uma identidade da
entidade atual; suas chaves nao valem para outro carro que reutilize a placa.
Reiniciar a garagem nao apaga as autorizacoes. Reiniciar o recurso de chaves
invalida as autorizacoes de NPCs/temporarios; as dos carros cadastrados persistem.

## Integracao servidor

- `exports.ob_core:CreateServerVehicle(source, model, coords, options)` retorna `{ok, netId, error}`
- `exports.ob_core:SpawnTemporaryVehicle(source, model, coords, options)`
- `exports.ob_core:DeleteTemporaryVehicle(source, netId)`
- `exports.ob_vehiclekeys:GrantTemporaryKey(source, netId)`
- `exports.ob_vehiclekeys:GrantTemporaryVehicleKey(source, netId)` (administrativo)
- `exports.ob_vehiclekeys:RevokeTemporaryKey(netId)`
- `exports.ob_vehiclekeys:GrantOwnerKey(source, netId)`
- `exports.ob_vehiclekeys:GiveSpareKey(source, netId)`
- `exports.ob_vehiclekeys:HasKey(source, netId)`
- `exports.ob_vehiclekeys:BeginLockpick(source, itemName, inventorySlot)`

Exports de concessao sao somente servidor: o recurso chamador deve validar a
regra de trabalho/compartilhamento. Nao ha evento de cliente que entregue chaves
arbitrarias. Resultado de minigame do cliente nao e prova anti-cheat; o servidor
valida tentativa, personagem, alvo, distancia, tempo e ferramenta.

Concessionaria nao tem mais dependencia de carregamento da garagem. Test-drive
usa o core; a compra/entrega pessoal ainda consulta a garagem e fica indisponivel
enquanto ela reinicia. Nao e necessario reiniciar a concessionaria junto.

## Aplicacao e testes

A primeira instalacao altera o core, inventario e manifests: reinicie a cidade
uma vez. O `server.cfg` ja inicia `ob_vehiclekeys` apos o inventario.
Depois disso, `restart ob_garage` nao deve reiniciar os trabalhos/concessionaria.

Teste com dois jogadores: dono tranca; outro usa lockpick; ambos usam L; guarde
e retire novamente; confirme que a reserva continua valida. Teste tambem uma
rota de trabalho durante `restart ob_garage` e os dois modos de chave.
O teste local `tests/ob-vehiclekeys-check.cjs` simula autorizacao/persistencia;
nao substitui FiveM, MySQL nem o minigame real.
