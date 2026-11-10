local selectedUserId
local selectedCharacter
local spawnOpening = false
local sessionAcknowledged = false
local progressActive = false
local meMessages = {}

local function nativeTrue(value)
    return value == true or value == 1
end

ORCore = ORCore or {}
ORCore.Progress = ORCore.Progress or {}

local function requestAnimation(animation)
    if type(animation) ~= 'table' or type(animation.dict) ~= 'string' or type(animation.clip) ~= 'string' then return nil end
    RequestAnimDict(animation.dict)
    local timeout = GetGameTimer() + 5000
    while not nativeTrue(HasAnimDictLoaded(animation.dict)) and GetGameTimer() < timeout do Wait(0) end
    return nativeTrue(HasAnimDictLoaded(animation.dict)) and animation or nil
end

function ORCore.Progress.Run(data)
    if progressActive then return false, 'Ja existe uma acao em andamento.' end
    data = type(data) == 'table' and data or {}

    local duration = math.max(250, math.floor(tonumber(data.duration) or (ORCoreConfig.Progress and ORCoreConfig.Progress.DefaultDuration) or 2500))
    local ped = PlayerPedId()
    local animation = requestAnimation(data.animation)
    progressActive = true
    SendNUIMessage({ action = 'progress', open = true, label = data.label or 'Processando...', duration = duration })

    if animation then
        TaskPlayAnim(ped, animation.dict, animation.clip, 4.0, -4.0, duration, animation.flag or 49, 0.0, false, false, false)
    end

    local endsAt = GetGameTimer() + duration
    local completed = true
    while GetGameTimer() < endsAt do
        if nativeTrue(IsEntityDead(ped)) or LocalPlayer.state['or:downed'] == true then
            completed = false
            break
        end
        Wait(0)
    end

    if animation and nativeTrue(DoesEntityExist(ped)) then ClearPedTasks(ped) end
    SendNUIMessage({ action = 'progress', open = false })
    progressActive = false
    return completed, completed and nil or 'Acao cancelada.'
end

exports('Progress', ORCore.Progress.Run)

local function drawMeMessage(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.31)
    SetTextColour(150, 220, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- O servidor e a unica origem dessas mensagens. Cada ped conserva no maximo
-- tres; quando uma quarta chega, a mais antiga ja foi removida no cliente.
RegisterNetEvent('ob_core:client:showMe', function(serverId, displayName, message)
    serverId = tonumber(serverId)
    if not serverId or type(message) ~= 'string' or message == '' then return end

    local config = ORCoreConfig.Me or {}
    local limit = math.max(1, math.floor(tonumber(config.MaxMessages) or 3))
    local queue = meMessages[serverId] or {}
    while #queue >= limit do table.remove(queue, 1) end

    queue[#queue + 1] = {
        text = ('* %s: %s'):format(displayName or 'Pessoa', message),
        expiresAt = GetGameTimer() + math.max(1000, math.floor(tonumber(config.Duration) or 10000)),
    }
    meMessages[serverId] = queue
end)

CreateThread(function()
    while true do
        local waitTime = 250
        local now = GetGameTimer()
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = math.max(1.0, tonumber((ORCoreConfig.Me or {}).Distance) or 20.0)

        for serverId, queue in pairs(meMessages) do
            for index = #queue, 1, -1 do
                if queue[index].expiresAt <= now then table.remove(queue, index) end
            end

            if #queue == 0 then
                meMessages[serverId] = nil
            else
                local player = GetPlayerFromServerId(serverId)
                local ped = player ~= -1 and GetPlayerPed(player) or 0
                if ped ~= 0 and DoesEntityExist(ped) and #(playerCoords - GetEntityCoords(ped)) <= distance then
                    waitTime = 0
                    local coords = GetEntityCoords(ped)
                    for index, entry in ipairs(queue) do
                        drawMeMessage(vector3(coords.x, coords.y, coords.z + 1.05 + ((#queue - index) * 0.22)), entry.text)
                    end
                end
            end
        end
        Wait(waitTime)
    end
end)

local function applyBasePlayerRules()
    if ORCoreConfig.DisableGtaHealthRecharge then
        SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
        SetPlayerHealthRechargeLimit(PlayerId(), 0.0)
    end

    local pvpEnabled = ORCoreConfig.EnablePvP ~= false
    NetworkSetFriendlyFireOption(pvpEnabled)
    -- O terceiro parametro precisa continuar false; com true o ped pode ficar
    -- impedido de mirar em jogadores mesmo depois de alterar a configuracao.
    SetCanAttackFriendly(PlayerPedId(), pvpEnabled, false)
end

local function openSpawn()
    if spawnOpening then return end
    spawnOpening = true
    TriggerEvent('ob_spawn:client:open', selectedCharacter and selectedCharacter.lastPosition or nil)
end

RegisterNetEvent('ob_core:client:openSelector', function()
    if GetResourceState('ob_multichar') ~= 'started' then
        OR.Notify('O seletor de personagens nao esta iniciado.', 'error')
        return
    end
    TriggerEvent('ob_multichar:client:open')
end)

RegisterNetEvent('ob_core:client:characterChosen', function(character)
    if not character or not character.userId then return end
    selectedUserId = character.userId
    selectedCharacter = character
    spawnOpening = false
    TriggerEvent('ob_core:client:characterSelected', character)
    openSpawn()
end)

RegisterNetEvent('ob_core:client:sessionReady', function()
    sessionAcknowledged = true
    applyBasePlayerRules()
    print('[ob_core] Sessao confirmada pelo servidor.')
end)

RegisterNetEvent('ob_core:client:databaseUnavailable', function(message)
    OR.Notify(message or 'Banco de dados indisponivel.', 'error')
end)

RegisterNetEvent('ob_core:client:characterSelected', function(character)
    selectedUserId = character and character.userId or nil
    selectedCharacter = character
    spawnOpening = false

    if GetResourceState('ob_creator') ~= 'started' then
        openSpawn()
        return
    end
end)

RegisterNetEvent('ob_core:client:appearanceReady', function(userId)
    if selectedUserId and selectedUserId == userId then
        openSpawn()
    end
end)

-- Esta thread e iniciada ao carregar este arquivo, em vez de depender do
-- evento de start do proprio resource. Assim a primeira solicitacao de sessao
-- nao pode ser perdida durante o bootstrap do cliente Enhanced.
CreateThread(function()
    Wait(500)
    print('[ob_core] Cliente iniciado; solicitando sessao ao servidor.')

    while not sessionAcknowledged do
        TriggerServerEvent('ob_core:server:clientReady')
        Wait(2500)
    end
end)

-- Reaplica regras do framework caso outro recurso altere uma native do GTA.
CreateThread(function()
    while true do
        applyBasePlayerRules()
        Wait(5000)
    end
end)

-- A camera de inatividade e uma regra local basica do jogador. Renovar o
-- temporizador uma vez por segundo evita a camera cinematografica sem manter
-- outra rotina executando a cada frame.
CreateThread(function()
    while true do
        if ORCoreConfig.DisableGtaIdleCamera then
            InvalidateIdleCam()
            InvalidateVehicleIdleCam()
            Wait(1000)
        else
            Wait(5000)
        end
    end
end)

-- Impede que o GTA mova automaticamente um passageiro para o banco do
-- motorista quando o condutor sai. A flag nao bloqueia a entrada manual no
-- banco do motorista; ela bloqueia somente o auto-shuffle do jogo.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if ped ~= 0 and DoesEntityExist(ped) then SetPedConfigFlag(ped, 184, true) end
        Wait(IsPedInAnyVehicle(ped, false) and 250 or 1000)
    end
end)

-- A roda nativa do GTA conflita com armas controladas pelo inventario. O
-- bloqueio fica no core para valer para todos os recursos da framework.
local weaponSwitchPed
CreateThread(function()
    while true do
        if ORCoreConfig.DisableGtaWeaponWheel then
            local ped = PlayerPedId()
            if ped ~= weaponSwitchPed or not DoesEntityExist(weaponSwitchPed) then
                weaponSwitchPed = ped
                SetPedCanSwitchWeapon(ped, false)
            end
            Wait(1000)
        else
            if weaponSwitchPed and DoesEntityExist(weaponSwitchPed) then
                SetPedCanSwitchWeapon(weaponSwitchPed, true)
            end
            weaponSwitchPed = nil
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if ORCoreConfig.DisableGtaWeaponWheel then
            HideHudComponentThisFrame(19)
            for control = 12, 17 do DisableControlAction(0, control, true) end
            DisableControlAction(0, 37, true)
            for control = 157, 165 do DisableControlAction(0, control, true) end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)
