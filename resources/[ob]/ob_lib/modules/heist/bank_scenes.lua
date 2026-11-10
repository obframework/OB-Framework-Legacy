-- Cenas dos roubos a banco.
-- A furadeira Fleeca usa a mesma origem, rotacao e sequencia do mri_Qfleecaheist.
OBBankScenes = OBBankScenes or {}
OBBankScenes.Version = '3.0.1-mri-props'
print(('[OBBankScenes] %s carregado em %s'):format(OBBankScenes.Version, GetCurrentResourceName()))

local activePed
local activeDrill
local activeBag
local activeSound
local activeCam
local activeScenes = {}
local activeCash
local activeStage

local function controlTick()
    for _, control in ipairs({30,31,32,33,34,35,24,25,37,44,140,141,142}) do
        DisableControlAction(0, control, true)
    end
    return not activePed or IsEntityDead(activePed) or IsControlJustPressed(0, 177)
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 10000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    model = type(model) == 'number' and model or joaat(model)
    RequestModel(model)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function removeEntity(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DetachEntity(entity, true, true)
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

local function animationDuration(dict, clip, fallback)
    local duration = math.floor((GetAnimDuration(dict, clip) or 0.0) * 1000)
    return duration >= 200 and duration or fallback
end

function OBBankScenes.Cleanup()
    for _, scene in ipairs(activeScenes) do NetworkStopSynchronisedScene(scene) end
    activeScenes = {}
    activeStage = nil
    if activeSound then
        StopSound(activeSound)
        ReleaseSoundId(activeSound)
        activeSound = nil
    end
    if activeCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(activeCam, false)
        activeCam = nil
    end
    if activePed and DoesEntityExist(activePed) then ClearPedTasks(activePed) end
    removeEntity(activeDrill)
    removeEntity(activeBag)
    removeEntity(activeCash)
    activeCash = nil
    activePed = nil
    activeDrill = nil
    activeBag = nil
    ClearAllHelpMessages()
end

-- One live scene at a time. Do not bind the same actors to six pending scenes.
-- Parameters below use the typed native contract, not decompiler float bit patterns.
local function stageFailure(label)
    local stage = activeStage
    local actors = {}
    for _, actor in ipairs(stage and stage.actors or {}) do
        actors[#actors+1] = ('%s: exists=%s playing=%s control=%s'):format(actor.clip,
            tostring(DoesEntityExist(actor.entity)),
            tostring(IsEntityPlayingAnim(actor.entity, stage.dict, actor.clip, 2)),
            tostring(NetworkHasControlOfEntity(actor.entity)))
    end
    print(('[OBBankScenes v3][%s] %s | %s'):format(GetCurrentResourceName(), label, table.concat(actors, '; ')))
    return false, 'A cena foi interrompida. Detalhes registrados no F8 [OBBankScenes v3].'
end

local function actorsPlaying(stage)
    for _, actor in ipairs(stage.actors) do
        if not DoesEntityExist(actor.entity) or not IsEntityPlayingAnim(actor.entity, stage.dict, actor.clip, 2) then return false end
    end
    return true
end

local function startStage(dict, pos, rot, clips, cameraClip, looped)
    for _, scene in ipairs(activeScenes) do NetworkStopSynchronisedScene(scene) end
    activeScenes = {}
    local scene = NetworkCreateSynchronisedScene(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
        2, not looped, looped == true, 1.0, 0.0, 1.0)
    activeScenes[1] = scene
    local actors = {{entity=activePed, clip=clips[1]}, {entity=activeBag, clip=clips[2]}}
    NetworkAddPedToSynchronisedScene(activePed, scene, dict, clips[1], 4.0, -4.0, 1033, 0, 1000.0, 0)
    NetworkAddEntityToSynchronisedScene(activeBag, scene, dict, clips[2], 1.0, -1.0, 1148846080)
    if clips[3] then
        actors[#actors+1] = {entity=activeDrill, clip=clips[3]}
        NetworkAddEntityToSynchronisedScene(activeDrill, scene, dict, clips[3], 1.0, -1.0, 1148846080)
    end
    activeStage = {net=scene, dict=dict, actors=actors}
    NetworkStartSynchronisedScene(scene)
    -- Start camera on the same tick, but only show it once the actors are playing.
    if cameraClip then
        PlayCamAnim(activeCam, cameraClip, dict, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, false, 2)
    end
    local deadline = GetGameTimer() + 2500
    repeat
        if controlTick() then return false, 'Acao cancelada.' end
        local localScene = NetworkGetLocalSceneFromNetworkId(scene)
        if localScene and localScene >= 0 and IsSynchronizedSceneRunning(localScene) and actorsPlaying(activeStage) then
            activeStage.localScene = localScene
            if cameraClip then RenderScriptCams(true, false, 0, true, false) end
            return true
        end
        Wait(0)
    until GetGameTimer() >= deadline
    return stageFailure('start '..clips[1])
end

local function waitStage()
    local stage = activeStage
    local deadline = GetGameTimer() + animationDuration(stage.dict, stage.actors[1].clip, 10000) + 3000
    repeat
        if controlTick() then return false, 'Acao cancelada.' end
        if GetSynchronizedScenePhase(stage.localScene) >= 0.98 then return true end
        if not IsSynchronizedSceneRunning(stage.localScene) or not actorsPlaying(stage) then
            return stageFailure('interrupted '..stage.actors[1].clip)
        end
        Wait(0)
    until GetGameTimer() >= deadline
    return stageFailure('timeout '..stage.actors[1].clip)
end

local function drillGame()
    local scaleform = RequestScaleformMovie('VAULT_DRILL')
    local loadDeadline = GetGameTimer() + 10000
    while not HasScaleformMovieLoaded(scaleform) and GetGameTimer() < loadDeadline do Wait(0) end
    if not HasScaleformMovieLoaded(scaleform) then return false end
    local function call(name, value)
        BeginScaleformMovieMethod(scaleform, name)
        if value ~= nil then ScaleformMovieMethodAddParamFloat(value) end
        EndScaleformMovieMethod()
    end
    local speed, pos, temp, depth = 0.0, 0.0, 0.0, 0.0
    local gameDeadline = GetGameTimer() + 120000
    call('REVEAL'); call('SET_SPEED', 0.0); call('SET_DRILL_POSITION', 0.0)
    call('SET_TEMPERATURE', 0.0); call('SET_HOLE_DEPTH', 0.0)
    while pos < 1.0 and temp < 1.0 and GetGameTimer() < gameDeadline do
        DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
        OR.Help.Show('[ESC] Cancelar perfuracao')
        if controlTick() then
            call('RESET'); SetScaleformMovieAsNoLongerNeeded(scaleform); return false
        end
        if not activeStage or not actorsPlaying(activeStage) then
            call('RESET'); SetScaleformMovieAsNoLongerNeeded(scaleform)
            return stageFailure('drill actors lost')
        end
        local dt = GetFrameTime()
        if IsControlPressed(0, 175) then speed = math.min(1.0, speed + 0.5 * dt) end
        if IsControlPressed(0, 174) then speed = math.max(0.0, speed - 0.5 * dt) end
        if IsControlPressed(0, 172) then
            local advance = 0.20 * dt / (math.max(0.1, temp) * 10.0)
            if speed > 0.4 then
                pos = math.min(1.0, pos + advance)
                temp = math.min(1.0, temp + 0.08 * dt * speed)
            elseif pos < 0.1 or pos < depth then
                pos = math.min(1.0, pos + advance * 0.25)
            else
                temp = math.min(1.0, temp + 0.005 * dt)
            end
        elseif IsControlPressed(0, 173) then
            pos = math.max(0.0, pos - 0.15 * dt)
            temp = math.max(0.0, temp - 0.30 * dt)
        else
            temp = math.max(0.0, temp - 0.35 * dt)
        end
        depth = math.max(depth, pos)
        call('SET_SPEED', speed); call('SET_DRILL_POSITION', pos)
        call('SET_TEMPERATURE', temp); call('SET_HOLE_DEPTH', depth)
        Wait(0)
    end
    call('RESET')
    SetScaleformMovieAsNoLongerNeeded(scaleform)
    ClearAllHelpMessages()
    return pos >= 1.0 and temp < 1.0
end

local function createProp(name)
    local model = loadModel(name)
    if not model then error('Modelo indisponivel: '..name) end
    local pos = GetEntityCoords(activePed)
    -- Igual ao mri_Qfleecaheist: entidade de rede normal, sem forcar
    -- netMissionEntity nem impedir migracao. O log mostrou a bolsa desaparecendo
    -- antes do fim do intro; essas restricoes nao existem na referencia funcional.
    local object = CreateObject(model, pos.x, pos.y, pos.z, true, false, false)
    if object == 0 then error('Falha criando prop: '..name) end
    local deadline = GetGameTimer() + 2500
    while not NetworkGetEntityIsNetworked(object) and GetGameTimer() < deadline do Wait(0) end
    if not NetworkGetEntityIsNetworked(object) then
        removeEntity(object)
        error('Prop sem registro de rede: '..name)
    end
    SetModelAsNoLongerNeeded(model)
    return object
end

local function runDrill(sceneData)
    local dict = 'anim_heist@hs3f@ig9_vault_drill@laser_drill@'
    if not loadAnim(dict) then return false, 'Nao foi possivel carregar a animacao da furadeira.' end
    activePed = PlayerPedId()
    local vaultPos = type(sceneData) == 'table' and sceneData.coords or nil
    local vaultRot = type(sceneData) == 'table' and sceneData.rotation or nil
    if not vaultPos or not vaultRot then return false, 'Origem da cena nao configurada.' end
    SetCurrentPedWeapon(activePed, joaat('WEAPON_UNARMED'), true)
    activeBag = createProp('hei_p_m_bag_var22_arm_s')
    activeDrill = createProp('hei_prop_heist_drill')
    activeCam = CreateCam('DEFAULT_ANIMATED_CAMERA', true)
    local animations = {
        {'intro', 'bag_intro', 'intro_drill_bit', 'intro_cam'},
        {'drill_straight_start', 'bag_drill_straight_start', 'drill_straight_start_drill_bit', 'drill_straight_start_cam'},
        {'drill_straight_end_idle', 'bag_drill_straight_idle', 'drill_straight_idle_drill_bit', 'drill_straight_idle_cam'},
        {'drill_straight_fail', 'bag_drill_straight_fail', 'drill_straight_fail_drill_bit', 'drill_straight_fail_cam'},
        {'drill_straight_end', 'bag_drill_straight_end', 'drill_straight_end_drill_bit', 'drill_straight_end_cam'},
        {'exit', 'bag_exit', 'exit_drill_bit', 'exit_cam'}
    }
    local function play(index, looped)
        local clips = animations[index]
        local ok, reason = startStage(dict, vaultPos, vaultRot, clips, clips[4], looped)
        if not ok then return false, reason end
        if looped then return true end
        return waitStage()
    end
    RequestAmbientAudioBank('DLC_HEIST_FLEECA_SOUNDSET', false)
    RequestAmbientAudioBank('DLC_MPHEIST\\HEIST_FLEECA_DRILL', false)
    RequestAmbientAudioBank('DLC_MPHEIST\\HEIST_FLEECA_DRILL_2', false)
    for i = 1, 2 do
        local ok, reason = play(i, false)
        if not ok then return false, reason end
    end
    local ready, reason = play(3, true)
    if not ready then return false, reason end
    activeSound = GetSoundId()
    PlaySoundFromEntity(activeSound, 'Drill', activeDrill, 'DLC_HEIST_FLEECA_SOUNDSET', true, 0)
    local success, gameReason = drillGame()
    StopSound(activeSound); ReleaseSoundId(activeSound); activeSound = nil
    if gameReason then return false, gameReason end
    if success then
        for _, index in ipairs({5,6}) do
            local ok, exitReason = play(index, false)
            if not ok then return false, exitReason end
        end
    else
        -- Cancellation returns immediately; no extra uninterruptible failure movie.
        return false, 'Perfuracao cancelada ou broca superaquecida.'
    end
    return true
end

local function protectedAction(action, ...)
    OBBankScenes.Cleanup()
    local result = table.pack(pcall(action, ...))
    OBBankScenes.Cleanup()
    if not result[1] then
        print(('[OBBankScenes v3][%s] %s'):format(GetCurrentResourceName(), tostring(result[2])))
        return false, 'Falha na cena. Consulte o F8 [OBBankScenes v3].'
    end
    return table.unpack(result, 2, result.n)
end

function OBBankScenes.Drill(sceneData)
    return protectedAction(runDrill, sceneData)
end

local function runCollection(collectChunk)
    if type(collectChunk) ~= 'function' then return false, 0, 'Coleta invalida.' end
    local dict = 'anim@heists@ornate_bank@grab_cash'
    if not loadAnim(dict) then return false, 0, 'Nao foi possivel carregar a animacao do dinheiro.' end
    activePed = PlayerPedId()
    activeBag = createProp('hei_p_m_bag_var22_arm_s')
    activeCash = createProp('hei_prop_heist_cash_pile')
    SetEntityVisible(activeCash, false, false)
    AttachEntityToEntity(activeCash, activePed, GetPedBoneIndex(activePed, 60309),
        0.0,0.0,0.0,0.0,0.0,0.0,false,false,false,false,0,true)
    local rot = vector3(0.0, 0.0, GetEntityHeading(activePed))
    -- Convert the authored intro root into an origin at the player's current spot.
    -- Bag and ped share this origin for intro/grab/exit; no hand-tuned attachments.
    local offset = GetAnimInitialOffsetPosition(dict, 'intro', 0.0,0.0,0.0, rot.x,rot.y,rot.z, 0.0,2)
    local pos = GetEntityCoords(activePed) - offset
    local ok, reason = startStage(dict, pos, rot, {'intro','bag_intro'}, nil, false)
    if ok then ok, reason = waitStage() end
    if not ok then return false, 0, reason end
    ok, reason = startStage(dict, pos, rot, {'grab','bag_grab'}, nil, true)
    if not ok then return false, 0, reason end
    local total, finished, lastMessage = 0, false, nil
    local nextChunk, deadline = GetGameTimer() + 1500, GetGameTimer() + 20000
    local chunks = 0
    while chunks < 5 and GetGameTimer() < deadline do
        if controlTick() then lastMessage = 'Coleta cancelada.'; break end
        if not actorsPlaying(activeStage) then
            local failed, failureMessage = stageFailure('cash actors lost')
            lastMessage = failureMessage; break
        end
        if HasAnimEventFired(activePed, joaat('CASH_APPEAR')) then SetEntityVisible(activeCash, true, false) end
        if HasAnimEventFired(activePed, joaat('RELEASE_CASH_DESTROY')) then SetEntityVisible(activeCash, false, false) end
        if GetGameTimer() >= nextChunk then
            local paid, amount, remaining, message = collectChunk()
            if paid ~= true then lastMessage = message or 'Nao foi possivel recolher o dinheiro.'; break end
            total = total + (tonumber(amount) or 0)
            chunks = chunks + 1
            finished = (tonumber(remaining) or 0) <= 0
            if finished then break end
            nextChunk = GetGameTimer() + 1500
        end
        Wait(0)
    end
    SetEntityVisible(activeCash, false, false)
    if not IsEntityDead(activePed) then
        local exiting = startStage(dict, pos, rot, {'exit','bag_exit'}, nil, false)
        if exiting then waitStage() end
    end
    return finished, total, lastMessage
end

function OBBankScenes.CollectMoney(collectChunk)
    local result = table.pack(protectedAction(runCollection, collectChunk))
    if type(result[2]) == 'string' then return false, 0, result[2] end
    return table.unpack(result, 1, result.n)
end
