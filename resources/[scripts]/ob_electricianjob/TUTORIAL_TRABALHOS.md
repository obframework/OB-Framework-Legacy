# Tutorial prático: criar e modificar trabalhos na OB Framework

> Atualização 18/10/2026: os exemplos abaixo preservam o histórico didático.
> O eletricista atual usa três etapas e a NUI própria `ui/repair.js`; não usa
> mais o minigame aleatório de `ob_minigame`. O marcador do chão consulta a
> altura real do piso, os objetos são redetectados e a descarga é não contínua.
> Para o comportamento instalado, consulte `README.md`, `config.lua` e o fonte.

Este guia usa o `ob_electricianjob` instalado neste servidor como exemplo real.
Ele foi escrito para quem quer alterar um trabalho existente e depois criar um
trabalho básico sem depender de tentativa e erro às cegas.

> Importante: uma validação de sintaxe não substitui o teste dentro do FiveM.
> Depois de editar, reinicie apenas o recurso alterado e teste o caminho inteiro.

## 1. Como um trabalho é dividido

Neste recurso, cada arquivo tem uma responsabilidade:

- `fxmanifest.lua`: informa ao FiveM quais arquivos carregar e as dependências.
- `config.lua`: modelos, coordenadas, pagamento, ferramentas, níveis e minigames.
- `client/main.lua`: markers, interações por E, animações, props, faíscas e interface.
- `server/main.lua`: valida distância, grupo, progresso, pagamento e veículos.
- `ui/`: painel HTML/CSS/JavaScript do trabalho.

Regra prática:

- Aparência e interação visual ficam no cliente.
- Dinheiro, XP, inventário e permissões sempre são confirmados no servidor.
- Valores que você pretende ajustar com frequência ficam no `config.lua`.

## 2. Coordenadas: `vec3` e `vec4`

Uma posição comum usa:

```lua
vec3(x, y, z)
```

Uma posição que também precisa de direção usa:

```lua
vec4(x, y, z, heading)
```

Exemplo do NPC:

```lua
coords = vec4(741.7849, 137.6208, 80.6044, 237.5639)
```

O `heading` gira o ped ou veículo. Valores aproximados:

- `0`: norte.
- `90`: leste.
- `180`: sul.
- `270`: oeste.

No cliente, você pode imprimir a posição atual:

```lua
local ped = PlayerPedId()
local coords = GetEntityCoords(ped)
local heading = GetEntityHeading(ped)
print(('vec4(%.4f, %.4f, %.4f, %.4f)'):format(
    coords.x, coords.y, coords.z, heading
))
```

O eletricista já possui dois comandos:

- `/eletricistaponto nome`: mostra no F8 sua posição e o objeto mais próximo.
- `/eletricistaoffset`: mire numa parte de um carro ou objeto. O comando mostra
  no F8 a coordenada mundial e o offset local, além de desenhar por 10 segundos
  um cone amarelo no ponto atingido.

## 3. Marker `MarkerTypeUpsideDownCone`

O eletricista usa o tipo `0`, conhecido como `MarkerTypeUpsideDownCone`.

Exemplo direto:

```lua
DrawMarker(
    0,                          -- MarkerTypeUpsideDownCone
    coords.x, coords.y, coords.z + 0.32,
    0.0, 0.0, 0.0,             -- direção
    0.0, 0.0, 0.0,             -- rotação
    0.38, 0.38, 0.28,          -- tamanho X, Y e Z
    255, 210, 0, 230,           -- vermelho, verde, azul, transparência
    false, false, 2, false,
    nil, nil, false
)
```

As cores são RGBA e variam de `0` a `255`:

- amarelo: `255, 210, 0, 230`
- vermelho: `255, 64, 64, 220`
- verde: `64, 210, 125, 190`
- azul: `50, 150, 255, 220`

O tamanho é controlado pelos três números depois da rotação:

```lua
0.35, 0.35, 0.35 -- pequeno
0.50, 0.50, 0.50 -- médio
0.80, 0.80, 0.80 -- grande
```

`DrawMarker` precisa ser executado a cada frame. Por isso ele deve ficar dentro
de uma thread com `Wait(0)` enquanto estiver perto do jogador:

```lua
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        if #(playerCoords - coords) < 40.0 then
            sleep = 0
            DrawMarker(0, coords.x, coords.y, coords.z + 0.32,
                0, 0, 0, 0, 0, 0,
                0.38, 0.38, 0.28,
                255, 210, 0, 230,
                false, false, 2, false, nil, nil, false)
        end
        Wait(sleep)
    end
end)
```

No eletricista, o marker do reparo está em `client/main.lua`, na chamada:

```lua
drawInteractionMarker(resolvedTask.repair, { 255, 210, 0, 230 }, 0.34)
```

## 4. Como funciona o `ob_target`

Existem quatro formas principais de criar um target.

### 4.1 Target numa zona fixa

```lua
exports.ob_target:RegisterSphereZone('meu_trabalho_caixa', {
    coords = vec3(100.0, 200.0, 30.0),
    radius = 0.8,
    option = {
        icon = 'fa-solid fa-wrench',
        label = 'Consertar caixa',
        action = function()
            print('O jogador escolheu consertar.')
        end,
        canInteract = function()
            return not trabalhando
        end,
    },
})
```

Neste `ob_target`, `radius` define o tamanho real da `SphereZone`. O campo
`distance` não aumenta uma zona. Se estiver difícil ativar o target, aumente:

```lua
radius = 0.65 -- bem preciso
radius = 1.0  -- confortável
radius = 1.5  -- amplo
```

Para retirar a zona:

```lua
exports.ob_target:UnregisterZone('meu_trabalho_caixa')
```

### 4.2 Zona em formato de caixa

```lua
exports.ob_target:RegisterBoxZone('meu_balcao', {
    coords = vec3(100.0, 200.0, 30.0),
    size = vec3(1.8, 0.8, 1.2),
    rotation = 90.0,
    option = {
        icon = 'fa-solid fa-box',
        label = 'Abrir depósito',
        action = function() print('abriu') end,
    },
})
```

Use `size.x`, `size.y` e `size.z` para largura, profundidade e altura.
`rotation` gira a caixa no chão.

### 4.3 Target em uma entidade local

Bom para NPC ou prop criado apenas naquele cliente:

```lua
exports.ob_target:RegisterEntity('meu_npc', npc, {
    icon = 'fa-solid fa-user',
    label = 'Conversar',
    distance = 2.5,
    action = function(entity)
        print('NPC selecionado:', entity)
    end,
})
```

### 4.4 Target em uma entidade de rede

Bom para um prop ou veículo que todos precisam enxergar:

```lua
local netId = NetworkGetNetworkIdFromEntity(object)

exports.ob_target:RegisterNetworkEntity('minha_maleta', netId, {
    icon = 'fa-solid fa-toolbox',
    label = 'Abrir maleta',
    distance = 2.5,
    action = function(entity)
        print('Maleta:', entity)
    end,
})
```

Para remover uma opção de entidade:

```lua
exports.ob_target:RemoveEntityOption('minha_maleta')
```

Ao reiniciar o `ob_target`, registre novamente as opções:

```lua
AddEventHandler('ob_target:client:ready', function()
    registrarMeusTargets()
end)
```

Para enxergar todas as zonas registradas, use:

```text
/obtargetdebug
```

Depois segure a tecla do target.

## 5. Target num ponto específico de um veículo

Um veículo se move e gira, então uma coordenada mundial fixa não serve. Use um
offset local relativo ao veículo:

```lua
local point = GetOffsetFromEntityInWorldCoords(vehicle, x, y, z)
```

Os eixos locais normalmente são:

- `x` positivo: lado direito.
- `x` negativo: lado esquerdo.
- `y` positivo: frente.
- `y` negativo: traseira.
- `z` positivo: cima.
- `z` negativo: baixo.

O eletricista atual não usa um offset lateral fixo. Ele consulta as dimensões
do modelo e posiciona o cone no centro, logo depois da traseira:

```lua
local minimum = GetModelDimensions(GetEntityModel(vehicle))
local y = minimum.y - 0.65
local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, minimum.z + 0.08)
```

Como o veículo se move, a coordenada é recalculada a cada frame enquanto o
jogador está perto. `rearMarkerGap` ajusta a distância depois da carroceria.

## 6. Criar e carregar um prop com uma mão

### 6.1 Carregar o modelo

```lua
local model = joaat('prop_tool_box_04')
RequestModel(model)
while not HasModelLoaded(model) do Wait(20) end
```

Nunca crie o objeto antes de o modelo terminar de carregar.

### 6.2 Criar o objeto

Neste framework:

```lua
local ped = PlayerPedId()
local object = exports.ob_core:CreateNetworkedObject(
    model,
    GetEntityCoords(ped),
    false
)
```

Objeto de rede é necessário quando outros jogadores precisam vê-lo.

### 6.3 Prender na mão direita

O osso `57005` é usado aqui para a mão direita:

```lua
AttachEntityToEntity(
    object,
    ped,
    GetPedBoneIndex(ped, 57005),
    0.14, 0.00, -0.02, -- posição X, Y, Z
    0.0, -90.0, 0.0,  -- rotação X, Y, Z
    true, true, false, true, 1, true
)
```

Para fazer a maleta ficar ao lado direito como uma mala:

- Ajuste primeiro a posição em passos de `0.02`.
- Depois ajuste a rotação em passos de `5` ou `10` graus.
- Mude apenas um eixo por vez.
- Tire uma captura quando ficar perto do resultado desejado.

Configuração atual:

```lua
Electrician.toolbox = {
    model = 'prop_tool_box_04',
    bone = 57005,
    carryOffset = vec3(0.14, 0.0, -0.02),
    carryRotation = vec3(0.0, -90.0, 0.0),
    animDict = 'move_weapon@jerrycan@generic',
    animClip = 'idle',
}
```

## 7. Fazer o braço e a maleta se moverem juntos

O prop não possui uma animação separada. Ele acompanha a mão porque está preso
ao osso. A animação movimenta o braço e o osso movimenta o prop.

```lua
RequestAnimDict('move_weapon@jerrycan@generic')
while not HasAnimDictLoaded('move_weapon@jerrycan@generic') do Wait(20) end

TaskPlayAnim(
    ped,
    'move_weapon@jerrycan@generic',
    'idle',
    4.0, -4.0, -1,
    49,
    0.0, false, false, false
)
```

Neste caso, a flag `49` combina repetição, parte superior do corpo e animação
secundária. Ela permite andar enquanto mantém o braço na pose.

Para encerrar corretamente:

```lua
StopAnimTask(ped, dict, clip, 2.0)
ClearPedSecondaryTask(ped)
DetachEntity(object, true, true)
exports.ob_core:DeleteNetworkedObject(object)
```

Se esquecer a limpeza, o personagem pode ficar travado na animação ou deixar
um prop invisível preso à mão.

## 8. Faíscas nas caixas e em cantos específicos

O eletricista usa:

```lua
asset = 'core'
effect = 'ent_sht_electrical_box'
```

Exemplo mínimo:

```lua
RequestNamedPtfxAsset('core')
while not HasNamedPtfxAssetLoaded('core') do Wait(20) end

UseParticleFxAssetNextCall('core')
local handle = StartParticleFxLoopedAtCoord(
    'ent_sht_electrical_box',
    coords.x, coords.y, coords.z,
    0.0, 0.0, 0.0,
    0.8,
    false, false, false, false
)
```

Para apagar:

```lua
StopParticleFxLooped(handle, false)
```

No `config.lua` do eletricista, cada rota pode receber:

```lua
sparkName = 'ent_sht_electrical_box',
sparkScale = 0.8,
sparkOffsets = {
    vec3(-0.20, 0.00, 0.15),
    vec3( 0.20, 0.00, 0.15),
},
```

Como interpretar `sparkOffsets`:

- Com o prop detectado, o offset acompanha a posição e a rotação do prop.
- Sem entidade detectável no Enhanced, o offset é somado à coordenada mundial
  do reparo.
- `x` move para os lados, `y` move para frente/trás e `z` move para cima/baixo.
- Um offset cria uma faísca; dois offsets criam duas faíscas.

Comece com `vec3(0.0, 0.0, 0.0)`. Depois mova em passos de `0.05` até chegar
ao canto desejado. Não use dezenas de efeitos loopados: cada um possui custo.

O script liga as faíscas quando o jogador fica a até `35 m` e as desliga ao se
afastar, terminar o reparo ou encerrar o trabalho.

## 9. Escolher o minigame

Os minigames disponíveis neste servidor são:

### Tecla no tempo certo

```lua
local success = exports.ob_minigame:Keypress({
    title = 'APERTAR PARAFUSO',
    key = 'E',
    steps = 3,
    speed = 1.0,
    tolerance = 0.14,
    timeoutMs = 120000,
})
```

### Barra de precisão

```lua
local success = exports.ob_minigame:PrecisionBar({ steps = 3 })
```

### Invasão de dados

```lua
local success = exports.ob_minigame:DataCrack({
    title = 'REPROGRAMAR CONTROLADOR',
    bars = 6,
    timeSeconds = 40,
    maxMistakes = 3,
    speed = 1.0,
    tolerance = 0.075,
})
```

### Circuito elétrico

```lua
local success = exports.ob_minigame:Circuit({
    title = 'ESTABILIZAR TENSAO',
    adjustCurrent = true,
    rows = 3,
    maxMultiplier = 5,
    timeSeconds = 45,
    maxAttempts = 4,
})
```

### Sequência de fios

```lua
local success = exports.ob_minigame:WireSequence({
    title = 'LIGAR CABOS',
    wires = 5,
    timeSeconds = 35,
    maxMistakes = 2,
})
```

Para cancelar qualquer um durante a limpeza do recurso:

```lua
exports.ob_minigame:Cancel()
```

No eletricista, `Electrician.minigames` relaciona o ID da ferramenta com o
minigame. Para trocar o minigame do alicate, altere a entrada de mesmo índice:

```lua
Electrician.minigames[2] = {
    name = 'WireSequence',
    options = {
        title = 'LIGAR CABOS',
        wires = 5,
        timeSeconds = 35,
        maxMistakes = 2,
    }
}
```

Depois, a função `runMinigame()` decide qual export chamar pelo campo `name`.
Se criar um nome novo, também será necessário adicionar sua condição nessa
função.

## 10. Adicionar uma ferramenta

Adicione ao final de `Electrician.tools`:

```lua
[4] = {
    label = 'multímetro',
    model = 'nome_do_prop',
    fallbackModel = 'prop_tool_screwdvr03',
    bone = 57005,
    offset = vec3(0.10, 0.02, -0.01),
    rotation = vec3(-80.0, 0.0, 5.0),
},
```

Adicione também `Electrician.minigames[4]`. Os índices precisam corresponder.
Se o modelo estiver errado ou não carregar, o `fallbackModel` evita que o
serviço fique sem prop.

## 11. Adicionar uma rota de reparo

Exemplo de caixa no chão:

```lua
{
    label = 'Caixa elétrica de exemplo',
    type = 'ground',
    toolbox = vec3(100.0, 201.5, 31.0),
    search = vec3(100.0, 200.0, 30.0),
    searchRadius = 2.0,
    models = { 'prop_elecbox_05a' },
    zOffset = 0.75,
    sparkScale = 0.8,
    sparkOffsets = { vec3(0.0, 0.0, 0.0) },
},
```

- `toolbox`: onde a maleta será colocada no chão.
- `search`: origem do objeto e destino do GPS.
- `searchRadius`: distância usada para localizar o prop exato.
- `models`: modelos aceitos naquele chamado.
- `zOffset`: altura do marker e das faíscas sobre a origem do prop.
- `type = 'ground'`: pode aparecer trabalhando sozinho.
- `type = 'aerial'`: exige dupla e operador na cesta.

No Enhanced, alguns objetos estáticos não aparecem para
`GetClosestObjectOfType`. O eletricista usa `search + zOffset` como fallback;
assim o marker e as faíscas continuam aparecendo.

## 12. Estrutura mínima de um trabalho novo

`fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_script 'client.lua'
server_script 'server.lua'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_target',
    'ob_notification',
    'ob_minigame'
}
```

`config.lua`:

```lua
MeuTrabalho = {
    point = vec3(100.0, 200.0, 30.0),
    reward = 500,
}
```

`client.lua`:

```lua
local busy = false

CreateThread(function()
    exports.ob_target:RegisterSphereZone('meu_trabalho', {
        coords = MeuTrabalho.point,
        radius = 1.0,
        option = {
            icon = 'fa-solid fa-wrench',
            label = 'Executar serviço',
            canInteract = function() return not busy end,
            action = function()
                busy = true
                local success = exports.ob_minigame:PrecisionBar({ steps = 3 })
                if success then TriggerServerEvent('meu_trabalho:server:concluir') end
                busy = false
            end,
        },
    })
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    exports.ob_target:UnregisterZone('meu_trabalho')
    exports.ob_minigame:Cancel()
end)
```

`server.lua`:

```lua
local cooldown = {}

RegisterNetEvent('meu_trabalho:server:concluir', function()
    local src = source
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    if #(GetEntityCoords(ped) - MeuTrabalho.point) > 4.0 then return end

    local now = os.time()
    if (cooldown[src] or 0) > now then return end
    cooldown[src] = now + 10

    exports.ob_inventory:AddItem(src, 'money', MeuTrabalho.reward)
end)

AddEventHandler('playerDropped', function()
    cooldown[source] = nil
end)
```

Este exemplo é propositalmente básico. Um trabalho completo ainda precisa de
estado de início/fim, progressão, proteção contra repetição, tratamento de
inventário cheio e mensagens de erro.

## 13. Segurança que não pode ficar só no cliente

Nunca confie apenas nestes dados enviados pelo jogador:

- valor do pagamento;
- quantidade de XP;
- ferramenta escolhida;
- serviço concluído;
- posição enviada pelo cliente;
- ID de outro jogador.

O servidor deve saber qual trabalho está ativo, validar a distância usando o
ped do jogador, aplicar cooldown e calcular recompensa por conta própria.

## 14. Método seguro para ajustar qualquer coisa

1. Faça uma mudança pequena.
2. Valide a sintaxe do arquivo alterado.
3. Reinicie somente o recurso.
4. Teste com uma pessoa.
5. Teste com duas pessoas se houver sincronização.
6. Afaste-se e volte para testar streaming.
7. Reinicie o recurso durante o serviço.
8. Confirme que props, animações, partículas e targets foram limpos.
9. Só depois altere o próximo ponto.

## 15. Checklist rápido de problemas

### O target não aparece

- Use `/obtargetdebug`.
- Confira se o recurso `ob_target` está iniciado.
- Aumente `radius` da zona.
- Confirme que `canInteract` retorna exatamente `true`.
- Em entidade de rede, confirme o NetID.
- Em veículo, recalcule a zona enquanto ele se move.

### O prop não aparece

- Confira o nome do modelo.
- Aguarde `HasModelLoaded`.
- Confira se a criação retornou uma entidade diferente de `0`.
- Use um `fallbackModel` conhecido.

### O prop aparece torto

- Ajuste `offset` primeiro.
- Ajuste `rotation` depois.
- Mude um eixo por vez.
- Confirme o bone usado.

### A animação fica presa

- Use `StopAnimTask`.
- Use `ClearPedSecondaryTask`.
- Faça a limpeza em `onClientResourceStop`.

### A faísca não aparece

- Carregue o asset antes.
- Chame `UseParticleFxAssetNextCall` antes de cada efeito.
- Confira altura e offsets.
- Guarde o handle para conseguir desligar.

### O minigame termina, mas não paga

- Veja a resposta do callback do servidor.
- Confirme a distância no servidor.
- Confira espaço no inventário.
- Confira se a etapa já foi marcada como concluída.
- Nunca pague diretamente no cliente.

## 16. Ordem recomendada para estudar

1. Trocar cor e tamanho de um marker.
2. Mover uma `SphereZone` fixa.
3. Usar `/eletricistaoffset` num veículo.
4. Ajustar uma maleta na mão.
5. Trocar animação mantendo o mesmo prop.
6. Mover uma faísca com `sparkOffsets`.
7. Trocar o minigame de uma ferramenta.
8. Adicionar uma nova rota.
9. Adicionar uma nova ferramenta.
10. Criar o trabalho mínimo e depois adicionar progressão.

Seguindo essa ordem, cada etapa ensina apenas uma ideia nova e fica muito mais
fácil descobrir onde um erro foi introduzido.
