local isOpen = false
local characters = {}
local maxSlots = 1
local selectedSlot = 1
local previewCamera
local unlockedSlots = 1
local loadingScreenClosed = false
local previewPreparing = false
local selectionPending = false

local function clearFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

local function closeInitialLoadingScreen()
    if loadingScreenClosed then return end
    loadingScreenClosed = true
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end

local function scenePosition()
    local scene = ORMulticharConfig.Scene
    local heading = math.rad(scene.coords.w)
    local forward = vector3(-math.sin(heading), math.cos(heading), 0.0)
    local camera = vector3(
        scene.coords.x + forward.x * scene.cameraDistance,
        scene.coords.y + forward.y * scene.cameraDistance,
        scene.coords.z + scene.cameraHeight
    )
    local lookAt = vector3(scene.coords.x, scene.coords.y, scene.coords.z + scene.lookAtHeight)
    return scene.coords, camera, lookAt
end

local function loadWorldAt(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end
end

local function setPreviewModel(character)
    local appearance = character and character.appearance
    local gender = character and tonumber(character.gender) or 0
    local model = gender == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'

    if appearance and GetResourceState('ob_creator') == 'started' then
        exports.ob_creator:setPlayerAppearance(appearance)
    elseif GetResourceState('ob_creator') == 'started' then
        exports.ob_creator:setPlayerModel(model)
    end
end

local function fadeOutForPreview()
    if IsScreenFadedOut() then return end

    DoScreenFadeOut(150)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(0)
    end
end

local function preparePreview(character)
    if previewPreparing then return end
    previewPreparing = true

    local coords, cameraCoords, lookAt = scenePosition()
    local ped = PlayerPedId()

    fadeOutForPreview()
    SetEntityVisible(ped, false, false)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, true)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w, true, true, false)
    ClearPedTasksImmediately(ped)
    SetEntityHeading(ped, coords.w)
    loadWorldAt(coords)
    setPreviewModel(character)

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(ped, coords.w)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    DisplayRadar(false)

    if not previewCamera then
        previewCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    SetCamCoord(previewCamera, cameraCoords.x, cameraCoords.y, cameraCoords.z)
    PointCamAtCoord(previewCamera, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(previewCamera, 42.0)
    SetCamActive(previewCamera, true)
    RenderScriptCams(true, false, 0, true, true)

    -- O Enhanced b169 deixa o estado visual preso depois de qualquer
    -- SetTimecycleModifier, mesmo quando ClearTimecycleModifier e chamado.
    -- O desfoque era apenas cosmetico; mantenha-o desativado ate a correcao
    -- do cliente para nao contaminar a imagem durante toda a sessao.

    closeInitialLoadingScreen()
    previewPreparing = false
    DoScreenFadeIn(250)
end

local function closePreview(hidePlayer)
    clearFocus()
    SendNUIMessage({ action = 'close' })
    isOpen = false
    ClearTimecycleModifier()

    if previewCamera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(previewCamera, false)
        previewCamera = nil
    end

    if hidePlayer then
        SetEntityVisible(PlayerPedId(), false, false)
    end
end

local function characterAtSlot(slot)
    for _, character in ipairs(characters) do
        if tonumber(character.slot) == tonumber(slot) then return character end
    end
end

local function details(character)
    if not character then
        return {
            name = 'Novo personagem',
            slot = selectedSlot,
            nationality = 'Disponivel',
            birthdate = nil,
            gender = nil,
            empty = true,
        }
    end

    return {
        userId = character.userId,
        name = ('%s %s'):format(character.firstname or '', character.lastname or ''),
        slot = character.slot,
        nationality = character.nationality or 'Brasileiro',
        birthdate = character.birthdate,
        gender = tonumber(character.gender) == 1 and 'Feminino' or 'Masculino',
        empty = false,
    }
end

local function showSlot(slot)
    local requestedSlot = math.max(1, math.min(tonumber(slot) or 1, maxSlots))
    if requestedSlot > unlockedSlots and not characterAtSlot(requestedSlot) then return end
    if requestedSlot == selectedSlot and previewCamera and not previewPreparing then
        local activeCharacter = characterAtSlot(selectedSlot)
        SendNUIMessage({ action = 'select', selectedSlot = selectedSlot, details = details(activeCharacter) })
        return
    end

    selectedSlot = requestedSlot
    local character = characterAtSlot(selectedSlot)
    preparePreview(character)
    SendNUIMessage({ action = 'select', selectedSlot = selectedSlot, details = details(character) })
end

local function openMultichar()
    if isOpen then return end
    print('[ob_multichar] Carregando personagens.')
    local data, err = OR.Callback.awaitResource('ob_core', 'listCharacters')
    if not data then
        closeInitialLoadingScreen()
        OR.Notify(err or 'Nao foi possivel carregar os personagens.', 'error')
        return
    end

    characters = data.characters or {}
    maxSlots = math.max(1, tonumber(data.maxSlots) or 1)
    unlockedSlots = math.max(1, math.min(maxSlots, tonumber(data.unlockedSlots) or 1))
    selectedSlot = (characters[1] and characters[1].slot) or 1
    selectionPending = false
    isOpen = true
    preparePreview(characterAtSlot(selectedSlot))
    SendNUIMessage({
        action = 'open',
        characters = characters,
        maxSlots = maxSlots,
        unlockedSlots = unlockedSlots,
        selectedSlot = selectedSlot,
        details = details(characterAtSlot(selectedSlot)),
    })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

RegisterNetEvent('ob_multichar:client:open', function()
    CreateThread(openMultichar)
end)

RegisterNUICallback('preview', function(data, callback)
    if isOpen then showSlot(data and data.slot) end
    callback({ ok = true })
end)

RegisterNUICallback('play', function(data, callback)
    if not isOpen or selectionPending then
        callback({ ok = false })
        return
    end

    local character = characterAtSlot(data and data.slot or selectedSlot)
    if not character then
        if selectedSlot > unlockedSlots then
            OR.Notify('Este slot ainda esta bloqueado.', 'error')
            callback({ ok = false })
            return
        end
        selectionPending = true
        fadeOutForPreview()
        closePreview(true)
        TriggerEvent('ob_creator:client:openCharacterCreator', selectedSlot)
        callback({ ok = true, creating = true })
        return
    end

    selectionPending = true
    local selected, err = OR.Callback.awaitResource('ob_core', 'selectCharacter', character.userId)
    if not selected then
        selectionPending = false
        OR.Notify(err or 'Nao foi possivel selecionar o personagem.', 'error')
        callback({ ok = false })
        return
    end

    -- A tela continua preta ate o ob_spawn montar a propria NUI. Assim o ped
    -- de preview nunca aparece entre a selecao e a escolha de local.
    fadeOutForPreview()
    closePreview(true)
    callback({ ok = true })
    TriggerEvent('ob_core:client:characterChosen', selected)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        closePreview()
    end
end)
