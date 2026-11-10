local function nativeTrue(value) return value == true or value == 1 end
local enhanced = type(IsGameEnhancedVersion) == 'function' and nativeTrue(IsGameEnhancedVersion()) or false
local ready, serverGeneration = false, nil
local mode, distance = OBVoiceConfig.DefaultMode, OBVoiceConfig.Modes[OBVoiceConfig.DefaultMode].distance
local label = OBVoiceConfig.Modes[mode].label
local radioChannel, callChannel, radio, call = 0, 0, {}, {}
local phoneSend, phoneReceive = {}, {}
local enabled, radioEnabled, radioPressed, cycleDisabled = true, true, false, false
local radioAnimDisabled, micClicks = false, true
local volume = { radio = enhanced and 100 or OBVoiceConfig.RadioVolume, call = enhanced and 100 or OBVoiceConfig.CallVolume }
local overridden, muted, warned = {}, {}, {}
local proximityOverride, customCheck, listenerOverride = nil, nil, false
local ringUntil, lastProperties = 0, ''
local target, radioSubmix = 1, nil
local customSubmixes = {}

local function notice(message)
    if GetResourceState('ob_notification') == 'started' then
        TriggerEvent('ob_notification:client:notify', message, 'info')
    else TriggerEvent('chat:addMessage', { args = { 'OB Voice', message } }) end
end
RegisterNetEvent('ob_voice:notice', notice)
local function unsupported(feature)
    if not warned[feature] then
        warned[feature] = true
        print('[ob_voice] Enhanced: API publica indisponivel para ' .. feature .. '; nao foi aplicado um ajuste ficticio.')
    end
    return false
end
local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge and value or nil
end
local function tableIds(values)
    local result = {}
    for key, value in pairs(type(values) == 'table' and values or {}) do
        local id = tonumber(key)
        if id then result[id] = value end
    end
    return result
end
local function canRadio()
    return enabled and radioEnabled and ready and radioChannel > 0
        and (tonumber(LocalPlayer.state.disableRadio) or 0) == 0
        and LocalPlayer.state['or:downed'] ~= true and LocalPlayer.state.isDead ~= true
        and not IsEntityDead(PlayerPedId())
end
local function setRadioPressed(value)
    value = value == true and canRadio()
    if radioPressed == value then return end
    radioPressed = value
    TriggerServerEvent('pma-voice:setTalkingOnRadio', value)
    LocalPlayer.state:set('radioActive', value, true)
    TriggerEvent('pma-voice:radioActive', value)
    if micClicks then PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
    if not value then StopAnimTask(PlayerPedId(), 'random@arrests', 'generic_radio_enter', 1.0) end
end

local function applyLegacy()
    if enhanced or not ready or not MumbleIsConnected() then return end
    local own = GetPlayerServerId(PlayerId())
    if own <= 0 then return end
    if MumbleGetVoiceChannelFromServerId(own) ~= own then MumbleSetVoiceChannel(own) end
    -- O filtro de destinos abaixo ja limita o alcance real. Usar esse mesmo
    -- raio curto na curva nativa apagava a voz antes de chegar ao limite.
    local audioScale = math.max(1.0, math.min(5.0, tonumber(OBVoiceConfig.LegacyAudioDistanceMultiplier) or 3.0))
    MumbleSetTalkerProximity(distance * audioScale + 0.0)
    MumbleSetVoiceTarget(target)
    MumbleClearVoiceTargetPlayers(target)
    local desired, targets = {}, {}
    local coords, ownBucket = GetEntityCoords(PlayerPedId()), LocalPlayer.state['ob:voiceBucket']
    if enabled and LocalPlayer.state.disableProximity ~= true then
        for _, player in ipairs(GetActivePlayers()) do
            local id = GetPlayerServerId(player)
            local bucket = Player(id).state['ob:voiceBucket']
            if id ~= own and bucket ~= nil and bucket == ownBucket then
                local near = #(coords - GetEntityCoords(GetPlayerPed(player))) <= distance
                if customCheck then local ok, result = pcall(customCheck, player); near = ok and result == true end
                if near or listenerOverride then targets[id] = true end
            end
        end
    end
    local function remoteAllowed(id)
        return not OBVoiceConfig.IsolateCommunicationBuckets or Player(id).state['ob:voiceBucket'] == ownBucket
    end
    for id in pairs(call) do
        if id ~= own and enabled and remoteAllowed(id) then targets[id] = true; desired[id] = volume.call / 100 end
    end
    for id in pairs(phoneSend) do
        if id ~= own and enabled and remoteAllowed(id) then targets[id] = true end
    end
    for id in pairs(phoneReceive) do
        if id ~= own and enabled and remoteAllowed(id) then desired[id] = volume.call / 100 end
    end
    for id, talking in pairs(radio) do
        if id ~= own and enabled and radioEnabled and remoteAllowed(id) then
            if radioPressed then targets[id] = true end
            if talking then desired[id] = math.max(desired[id] or 0, volume.radio / 100) end
        end
    end
    for id in pairs(muted) do desired[id] = 0; targets[id] = nil end
    for id in pairs(targets) do MumbleAddVoiceTargetPlayerByServerId(target, id) end
    for id in pairs(overridden) do
        if desired[id] == nil then
            MumbleSetVolumeOverrideByServerId(id, -1.0)
            if radioSubmix then MumbleSetSubmixForServerId(id, -1) end
        end
    end
    for id, vol in pairs(desired) do
        MumbleSetVolumeOverrideByServerId(id, vol + 0.0)
        if radioSubmix then
            local effect = call[id] and customSubmixes.call or radio[id] == true and (customSubmixes.radio or radioSubmix)
            MumbleSetSubmixForServerId(id, effect or -1)
        end
    end
    overridden = desired
end
local function sendProperties()
    local properties = { enabled = enabled, radioEnabled = radioEnabled and (tonumber(LocalPlayer.state.disableRadio) or 0) == 0,
        proximityEnabled = LocalPlayer.state.disableProximity ~= true,
        radioListen = volume.radio > 0, callListen = volume.call > 0 }
    local signature = ('%s:%s:%s:%s:%s'):format(properties.enabled, properties.radioEnabled,
        properties.proximityEnabled, properties.radioListen, properties.callListen)
    if signature ~= lastProperties and ready then lastProperties = signature; TriggerServerEvent('ob_voice:properties', properties) end
end
RegisterNetEvent('ob_voice:sync', function(data)
    if type(data) ~= 'table' or type(data.proximity) ~= 'table' then return end
    if (data.backend == 'enhanced') ~= enhanced then
        ready = false
        return unsupported('backend do cliente e do servidor divergentes; confira o artifact')
    end
    local changedGeneration = serverGeneration ~= data.generation
    serverGeneration, ready = data.generation, true
    mode, distance, label = data.proximity.index, data.proximity.distance, data.proximity.mode
    local oldRadio = radioChannel
    radioChannel, callChannel = tonumber(data.radioChannel) or 0, tonumber(data.callChannel) or 0
    radio, call = tableIds(data.radio), tableIds(data.call)
    phoneSend, phoneReceive = tableIds(data.phoneSend), tableIds(data.phoneReceive)
    if oldRadio ~= radioChannel or not canRadio() or (radioPressed and radio[GetPlayerServerId(PlayerId())] ~= true) then setRadioPressed(false) end
    LocalPlayer.state:set('proximity', data.proximity, false)
    LocalPlayer.state:set('radioChannel', radioChannel, false)
    LocalPlayer.state:set('callChannel', callChannel, false)
    LocalPlayer.state:set('ob:voiceBucket', data.bucket, false)
    if changedGeneration then lastProperties = ''; sendProperties() end
    TriggerEvent('pma-voice:setTalkingMode', mode)
    applyLegacy()
end)

local function setChannel(kind, value)
    value = finite(value)
    if not value or value < 0 or value > 2147483647 then return false end
    if kind == 'Call' and value ~= math.floor(value) then return false end
    TriggerServerEvent('pma-voice:setPlayer' .. kind, value)
    return true -- Pedido enviado; o servidor confirma via sync/clSetPlayer*.
end
local function setVolume(kind, value)
    value = finite(value)
    if not value then return false end
    value = math.max(0, math.min(100, value))
    -- Enhanced possui mute/deaf por canal; volume intermediario depende da
    -- futura API de audio do cliente. 0 e 100 funcionam sem Mumble depreciado.
    if enhanced and value ~= 0 and value ~= 100 then return unsupported('volume individual de ' .. kind .. ' (somente 0/100 disponiveis)') end
    volume[kind] = value
    LocalPlayer.state:set(kind, value, true)
    sendProperties(); applyLegacy(); return true
end
local function requestMode(index, override)
    if not OBVoiceConfig.Modes[index] then return false end
    TriggerServerEvent('ob_voice:mode', index, override)
    return true
end
RegisterCommand('cycleproximity', function()
    if not ready then TriggerServerEvent('ob_voice:ready'); return notice('A voz ainda esta sincronizando com o servidor.') end
    if cycleDisabled or IsPauseMenuActive() or IsNuiFocused() then return end
    local direction = IsControlPressed(0, 21) and -1 or 1
    local nextMode = ((mode - 1 + direction) % #OBVoiceConfig.Modes) + 1
    proximityOverride = nil
    requestMode(nextMode)
    ringUntil = GetGameTimer() + 2500
end, false)
RegisterKeyMapping('cycleproximity', 'Voz: mudar distancia (Shift inverte)', 'keyboard', OBVoiceConfig.CycleKey)
RegisterCommand('voz', function(_, args)
    local index = tonumber(args and args[1])
    if not index then return notice('HOME alterna o alcance. /voz 1, /voz 2 ou /voz 3 seleciona o nivel.') end
    if not ready then TriggerServerEvent('ob_voice:ready'); return notice('A voz ainda esta sincronizando.') end
    if cycleDisabled or not OBVoiceConfig.Modes[index] then return end
    proximityOverride = nil
    requestMode(index)
    ringUntil = GetGameTimer() + 2500
end, false)
RegisterCommand('+radiotalk', function() setRadioPressed(true) end, false)
RegisterCommand('-radiotalk', function() setRadioPressed(false) end, false)
RegisterKeyMapping('+radiotalk', 'Voz: falar no radio', 'keyboard', OBVoiceConfig.RadioKey)
RegisterCommand('vozdebug', function()
    print(('[ob_voice] backend=%s ready=%s modo=%s distancia=%s radio=%s chamada=%s'):format(
        enhanced and 'enhanced' or 'legacy', ready, mode, distance, radioChannel, callChannel))
    local localTalking = type(NetworkIsLocalPlayerTalking) == 'function' and NetworkIsLocalPlayerTalking() or 'indisponivel'
    print(('[ob_voice] fala_network=%s fala_local=%s tecla=%s'):format(tostring(NetworkIsPlayerTalking(PlayerId())), tostring(localTalking), OBVoiceConfig.CycleKey))
end, false)

exports('setCallChannel', function(value) return setChannel('Call', value) end)
exports('SetCallChannel', function(value) return setChannel('Call', value) end)
exports('addPlayerToCall', function(value) return setChannel('Call', value) end)
exports('removePlayerFromCall', function() return setChannel('Call', 0) end)
exports('setRadioChannel', function(value) return setChannel('Radio', value) end)
exports('SetRadioChannel', function(value) return setChannel('Radio', value) end)
exports('addPlayerToRadio', function(value) return setChannel('Radio', value) end)
exports('removePlayerFromRadio', function() return setChannel('Radio', 0) end)
exports('setRadioVolume', function(value) return setVolume('radio', value) end)
exports('getRadioVolume', function() return volume.radio end)
exports('setCallVolume', function(value) return setVolume('call', value) end)
exports('getCallVolume', function() return volume.call end)
exports('registerCustomSubmix', function(callback)
    if enhanced then return unsupported('submix personalizado') end
    if type(callback) ~= 'function' then return false end
    local ok, result = pcall(callback)
    if not ok or type(result) ~= 'table' or type(result[1]) ~= 'string' or not finite(result[2]) then return false end
    customSubmixes[result[1]] = result[2]; return true
end)
exports('setEffectSubmix', function(kind, id)
    if enhanced then return unsupported('efeitos de audio individuais') end
    id = finite(id)
    if (kind ~= 'radio' and kind ~= 'call') or not id or id < -1 or id ~= math.floor(id) then return false end
    customSubmixes[kind] = id; applyLegacy(); return true
end)
local function setVoiceProperty(key, value)
    if key == 'radioEnabled' then radioEnabled = value == true; if not radioEnabled then setRadioPressed(false) end
    elseif key == 'micClicks' then micClicks = value == true or value == 'true'
    elseif key == 'enabled' then enabled = value == true; NetworkSetVoiceActive(enabled)
    else return false end
    sendProperties(); applyLegacy(); return true
end
exports('setVoiceProperty', setVoiceProperty)
exports('SetMumbleProperty', setVoiceProperty)
exports('SetTokoProperty', setVoiceProperty)
exports('setAllowProximityCycleState', function(disabled) cycleDisabled = disabled == true end)
exports('overrideProximityRange', function(value, disableCycle)
    value = finite(value)
    if not value or value < 0 or value > OBVoiceConfig.MaxOverrideDistance then return false end
    proximityOverride = value; cycleDisabled = disableCycle == true
    return requestMode(mode, value)
end)
exports('clearProximityOverride', function() proximityOverride = nil; cycleDisabled = false; return requestMode(mode) end)
exports('overrideProximityCheck', function(fn)
    if enhanced then return unsupported('checagem de proximidade personalizada no cliente') end
    if type(fn) ~= 'function' then return false end
    customCheck = fn; return true
end)
exports('resetProximityCheck', function() customCheck = nil; return true end)
exports('setListenerOverride', function(value)
    if enhanced then return unsupported('listener override no cliente') end
    listenerOverride = value == true; return true
end)
exports('toggleMutePlayer', function(id)
    if enhanced then return unsupported('mute local de um jogador especifico') end
    id = finite(id); if not id or id <= 0 then return false end
    muted[id] = not muted[id] or nil; applyLegacy(); return muted[id] == true
end)
exports('isPlayerMuted', function(id) return muted[tonumber(id)] == true end)
exports('getMutedPlayers', function() local result = {}; for id in pairs(muted) do result[id] = true end; return result end)
exports('setDisableRadioAnim', function(value) radioAnimDisabled = value == true end)
exports('toggleRadioAnim', function() radioAnimDisabled = not radioAnimDisabled; return not radioAnimDisabled end)
exports('getRadioAnimState', function() return not radioAnimDisabled end)
exports('addRadioDisableBit', function(bit)
    bit = finite(bit); if not bit or bit < 0 or bit ~= math.floor(bit) then return false end
    LocalPlayer.state:set('disableRadio', (tonumber(LocalPlayer.state.disableRadio) or 0) | bit, true); return true
end)
exports('removeRadioDisableBit', function(bit)
    bit = finite(bit); if not bit or bit < 0 or bit ~= math.floor(bit) then return false end
    LocalPlayer.state:set('disableRadio', (tonumber(LocalPlayer.state.disableRadio) or 0) & (~bit), true); return true
end)
exports('GetCapabilities', function() return { backend = enhanced and 'enhanced' or 'legacy',
    proximity = true, calls = true, radio = true, individualVolume = not enhanced, submix = not enhanced } end)
local function status()
    local connected = ready and (enhanced or nativeTrue(MumbleIsConnected()))
    local talking = nativeTrue(NetworkIsPlayerTalking(PlayerId()))
    if not talking and type(NetworkIsLocalPlayerTalking) == 'function' then
        local ok, result = pcall(NetworkIsLocalPlayerTalking)
        talking = ok and nativeTrue(result)
    end
    if not enhanced and not talking and type(MumbleIsPlayerTalking) == 'function' then
        talking = nativeTrue(MumbleIsPlayerTalking(PlayerId()))
    end
    talking = connected and enabled and talking
    return { ready = connected, talking = talking, radioTalking = radioPressed and connected,
        mode = mode, distance = distance, label = label, radioChannel = radioChannel, callChannel = callChannel }
end
exports('GetStatus', status)
AddEventHandler('pma-voice:settingsCallback', function(cb)
    local modes = {}; for i, entry in ipairs(OBVoiceConfig.Modes) do modes[i] = { entry.distance, entry.label } end
    if type(cb) == 'function' then cb({ voiceModes = modes }) end
end)
AddEventHandler('mumbleConnected', function() if not enhanced then applyLegacy() end end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then TriggerServerEvent('ob_voice:ready') end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ready = false; setRadioPressed(false)
    if not enhanced then
        for id in pairs(overridden) do MumbleSetVolumeOverrideByServerId(id, -1.0); MumbleSetSubmixForServerId(id, -1) end
        MumbleClearVoiceTarget(target); MumbleSetVoiceTarget(0)
        MumbleClearVoiceChannel()
    end
    NetworkSetVoiceActive(true)
    LocalPlayer.state:set('ob:voice', { ready = false, talking = false }, false)
end)
CreateThread(function()
    NetworkSetVoiceActive(true)
    if not enhanced then
        radioSubmix = CreateAudioSubmix('ob_voice_radio')
        if radioSubmix and radioSubmix >= 0 then
            SetAudioSubmixEffectRadioFx(radioSubmix, 0)
            SetAudioSubmixEffectParamInt(radioSubmix, 0, GetHashKey('default'), 1)
            AddAudioSubmixOutput(radioSubmix, 0)
        else radioSubmix = nil end
        TriggerEvent('pma-voice:registerCustomSubmixes')
    end
    while not NetworkIsSessionActive() do Wait(250) end
    TriggerServerEvent('ob_voice:ready')
    local retryAt = GetGameTimer() + 5000
    while true do
        Wait(OBVoiceConfig.UpdateInterval)
        if not ready and GetGameTimer() > retryAt then retryAt = GetGameTimer() + 5000; TriggerServerEvent('ob_voice:ready') end
        sendProperties(); applyLegacy()
        local current = status()
        LocalPlayer.state:set('ob:voice', current, false)
        if radioPressed and not canRadio() then setRadioPressed(false) end
    end
end)
CreateThread(function()
    while true do
        if radioPressed then
            SetControlNormal(0, 249, 1.0); SetControlNormal(1, 249, 1.0); SetControlNormal(2, 249, 1.0)
            if not radioAnimDisabled then
                RequestAnimDict('random@arrests')
                if HasAnimDictLoaded('random@arrests') and not IsEntityPlayingAnim(PlayerPedId(), 'random@arrests', 'generic_radio_enter', 3) then
                    TaskPlayAnim(PlayerPedId(), 'random@arrests', 'generic_radio_enter', 4.0, 2.0, -1, 49, 0.0, false, false, false)
                end
            end
            Wait(0)
        elseif GetGameTimer() < ringUntil then
            local pos = GetEntityCoords(PlayerPedId())
            DrawMarker(1, pos.x, pos.y, pos.z - 1.0, 0.0,0.0,0.0,0.0,0.0,0.0,
                distance * 2.0, distance * 2.0, 0.08, 25, 180, 255, 55, false, false, 2, false, nil, nil, false)
            Wait(0)
        else Wait(200) end
    end
end)
