Appearance = {}

local function tofloat(num)
    return num + 0.0
end

local function isPedFreemodeModel(ped)
    local model = GetEntityModel(ped)
    return model == GetHashKey('mp_m_freemode_01') or model == GetHashKey('mp_f_freemode_01')
end

-- Saves antigos podem conter indices de DLC/roupas que nao existem no cliente
-- Enhanced. Nunca passe esses valores diretamente aos natives de aparencia:
-- alem do visual quebrado, eles podem derrubar o cliente ao sincronizar o ped.
local function clampInteger(value, minimum, maximum, fallback)
    value = math.floor(tonumber(value) or fallback or minimum)
    return math.max(minimum, math.min(maximum, value))
end

-- GET_PED_HEAD_BLEND_DATA usa ponteiros de saida. No cliente Enhanced esse
-- getter ja causou access violation dentro do processo do jogo, que nao pode
-- ser capturada por pcall. O creator nao precisa reler esses ponteiros: ele ja
-- possui os dados recebidos do banco ou escolhidos na NUI. Mantemos uma copia
-- validada por ped/model e usamos um default conhecido apenas quando ainda nao
-- aplicamos uma aparencia neste ped.
local PED_HEAD_BLEND_CACHE = {}
local PED_HAIR_TINT_VERSION = {}
local PED_HEAD_OVERLAY_TINT_VERSION = {}
local HEAD_BLEND_TIMEOUT_MS = 1000
local MODEL_LOAD_TIMEOUT_MS = 10000
local ensureFreemodeHeadBlendReady

local function copyHeadBlend(headBlend)
    return {
        shapeFirst = headBlend.shapeFirst,
        shapeSecond = headBlend.shapeSecond,
        shapeThird = headBlend.shapeThird,
        skinFirst = headBlend.skinFirst,
        skinSecond = headBlend.skinSecond,
        skinThird = headBlend.skinThird,
        shapeMix = headBlend.shapeMix,
        skinMix = headBlend.skinMix,
        thirdMix = headBlend.thirdMix
    }
end

local function getDefaultHeadBlend(ped)
    if GetEntityModel(ped) == GetHashKey('mp_f_freemode_01') then
        return {
            shapeFirst = 45, shapeSecond = 21, shapeThird = 0,
            skinFirst = 20, skinSecond = 15, skinThird = 0,
            shapeMix = 0.3, skinMix = 0.1, thirdMix = 0.0
        }
    end

    return {
        shapeFirst = 0, shapeSecond = 0, shapeThird = 0,
        skinFirst = 0, skinSecond = 0, skinThird = 0,
        shapeMix = 0.0, skinMix = 0.0, thirdMix = 0.0
    }
end

local function normalizeHeadBlend(ped, headBlend)
    local fallback = getDefaultHeadBlend(ped)
    headBlend = type(headBlend) == 'table' and headBlend or fallback

    return {
        shapeFirst = clampInteger(headBlend.shapeFirst, 0, 45, fallback.shapeFirst),
        shapeSecond = clampInteger(headBlend.shapeSecond, 0, 45, fallback.shapeSecond),
        shapeThird = clampInteger(headBlend.shapeThird, 0, 45, fallback.shapeThird),
        skinFirst = clampInteger(headBlend.skinFirst, 0, 45, fallback.skinFirst),
        skinSecond = clampInteger(headBlend.skinSecond, 0, 45, fallback.skinSecond),
        skinThird = clampInteger(headBlend.skinThird, 0, 45, fallback.skinThird),
        shapeMix = math.max(0.0, math.min(1.0, tonumber(headBlend.shapeMix) or fallback.shapeMix)),
        skinMix = math.max(0.0, math.min(1.0, tonumber(headBlend.skinMix) or fallback.skinMix)),
        thirdMix = math.max(0.0, math.min(1.0, tonumber(headBlend.thirdMix) or fallback.thirdMix))
    }
end

local function rememberPedHeadBlend(ped, headBlend)
    local normalized = normalizeHeadBlend(ped, headBlend)
    PED_HEAD_BLEND_CACHE[ped] = {
        model = GetEntityModel(ped),
        data = normalized,
        settled = false,
        timedOut = false,
        finalized = false,
        nativeFinished = false
    }
    return copyHeadBlend(normalized)
end

local function asInteger(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return math.floor(value)
end

local function normalizeCollectionName(value)
    if type(value) ~= 'string' or #value > 96 or value:find('\0', 1, true) then return nil end
    return value
end

local function hasCollectionNatives()
    return type(GetPedCollectionsCount) == 'function'
        and type(GetPedCollectionName) == 'function'
        and type(GetPedDrawableVariationCollectionName) == 'function'
        and type(GetPedDrawableVariationCollectionLocalIndex) == 'function'
        and type(GetPedPropCollectionName) == 'function'
        and type(GetPedPropCollectionLocalIndex) == 'function'
        and type(GetNumberOfPedCollectionDrawableVariations) == 'function'
        and type(GetNumberOfPedCollectionTextureVariations) == 'function'
        and type(GetNumberOfPedCollectionPropDrawableVariations) == 'function'
        and type(GetNumberOfPedCollectionPropTextureVariations) == 'function'
        and type(SetPedCollectionComponentVariation) == 'function'
        and type(SetPedCollectionPropIndex) == 'function'
end

local function pedHasCollection(ped, collection)
    if collection == '' then return true end
    if not hasCollectionNatives() then return false end

    local count = asInteger(GetPedCollectionsCount(ped)) or 0
    for index = 0, math.min(count - 1, 511) do
        if GetPedCollectionName(ped, index) == collection then return true end
    end
    return false
end

local function getComponentSnapshot(ped, componentId)
    local drawable = GetPedDrawableVariation(ped, componentId)
    local snapshot = {
        component_id = componentId,
        drawable = drawable,
        texture = math.max(0, GetPedTextureVariation(ped, componentId)),
        palette = type(GetPedPaletteVariation) == 'function' and math.max(0, GetPedPaletteVariation(ped, componentId)) or 0,
        collection = '',
        local_drawable = -1
    }

    if hasCollectionNatives() then
        snapshot.collection = GetPedDrawableVariationCollectionName(ped, componentId) or ''
        snapshot.local_drawable = asInteger(GetPedDrawableVariationCollectionLocalIndex(ped, componentId)) or -1
    end
    return snapshot
end

local function getPropSnapshot(ped, propId)
    -- Enhanced added a dead-ped check argument; false asks for the item the
    -- ped is wearing regardless of its health state. Legacy ignores the extra.
    local drawable = GetPedPropIndex(ped, propId, false)
    local snapshot = {
        prop_id = propId,
        drawable = drawable,
        texture = drawable < 0 and 0 or math.max(0, GetPedPropTextureIndex(ped, propId)),
        collection = '',
        local_drawable = -1
    }

    if drawable >= 0 and hasCollectionNatives() then
        snapshot.collection = GetPedPropCollectionName(ped, propId) or ''
        snapshot.local_drawable = asInteger(GetPedPropCollectionLocalIndex(ped, propId)) or -1
    end
    return snapshot
end

-- The Enhanced vMenu writer prefers collection + local drawable because those
-- indexes remain stable after GTA title updates. Old OB saves have only the
-- global drawable, so that path remains as a validated compatibility fallback.
local function safeComponentVariation(ped, componentId, drawable, texture, collection, localDrawable, palette)
    componentId = tonumber(componentId)
    if not componentId or componentId < 0 or componentId > 11 then return nil end
    componentId = math.floor(componentId)

    texture = asInteger(texture) or 0
    palette = asInteger(palette) or 0
    collection = normalizeCollectionName(collection)
    localDrawable = asInteger(localDrawable)

    if collection ~= nil and localDrawable and localDrawable >= 0 and hasCollectionNatives() then
        if not pedHasCollection(ped, collection) then return nil end

        local drawableCount = asInteger(GetNumberOfPedCollectionDrawableVariations(ped, componentId, collection)) or 0
        if localDrawable >= drawableCount then return nil end

        local textureCount = asInteger(GetNumberOfPedCollectionTextureVariations(ped, componentId, collection, localDrawable)) or 0
        if texture < 0 or texture >= textureCount then return nil end

        if type(IsPedCollectionComponentVariationValid) == 'function'
            and not IsPedCollectionComponentVariationValid(ped, componentId, collection, localDrawable, texture, palette) then
            return nil
        end

        SetPedCollectionComponentVariation(ped, componentId, collection, localDrawable, texture, palette)
        return getComponentSnapshot(ped, componentId)
    end

    drawable = asInteger(drawable)
    local drawableCount = asInteger(GetNumberOfPedDrawableVariations(ped, componentId)) or 0
    if not drawable or drawable < 0 or drawable >= drawableCount then return nil end

    local textureCount = GetNumberOfPedTextureVariations(ped, componentId, drawable)
    if texture < 0 or texture >= (textureCount or 0) then return nil end

    -- A drawable can be inside GetNumberOfPedDrawableVariations and still be
    -- invalid after a GTA title update, because the legacy global DLC indexes
    -- shift.  Passing that combination to SetPedComponentVariation is exactly
    -- what the Enhanced client warns about as CPed::SetVariation.
    if not IsPedComponentVariationValid(ped, componentId, drawable, texture, palette) then
        return nil
    end

    SetPedComponentVariation(ped, componentId, drawable, texture, palette)
    return getComponentSnapshot(ped, componentId)
end

local function safePropVariation(ped, propId, drawable, texture, collection, localDrawable)
    propId = tonumber(propId)
    if not propId or propId < 0 or propId > 7 then return nil end
    propId = math.floor(propId)
    drawable = asInteger(drawable) or -1
    if drawable < 0 then
        ClearPedProp(ped, propId)
        return getPropSnapshot(ped, propId)
    end

    texture = asInteger(texture) or 0
    collection = normalizeCollectionName(collection)
    localDrawable = asInteger(localDrawable)

    if collection ~= nil and localDrawable and localDrawable >= 0 and hasCollectionNatives() then
        if not pedHasCollection(ped, collection) then return nil end

        local drawableCount = asInteger(GetNumberOfPedCollectionPropDrawableVariations(ped, propId, collection)) or 0
        if localDrawable >= drawableCount then return nil end

        local textureCount = asInteger(GetNumberOfPedCollectionPropTextureVariations(ped, propId, collection, localDrawable)) or 0
        if texture < 0 or texture >= textureCount then return nil end

        SetPedCollectionPropIndex(ped, propId, collection, localDrawable, texture, true)
        return getPropSnapshot(ped, propId)
    end

    local drawableCount = asInteger(GetNumberOfPedPropDrawableVariations(ped, propId)) or 0
    if drawable >= drawableCount then return nil end
    local textureCount = GetNumberOfPedPropTextureVariations(ped, propId, drawable)
    if texture < 0 or texture >= (textureCount or 0) then return nil end
    if IsPedPropValid and not IsPedPropValid(ped, propId, drawable, texture) then
        return nil
    end
    SetPedPropIndex(ped, propId, drawable, texture, true, false)
    return getPropSnapshot(ped, propId)
end

local function getPedComponents(ped)
    local components = {}
    for i = 1, #constants.PED_COMPONENTS_IDS do
        local componentId = constants.PED_COMPONENTS_IDS[i]
        components[i] = getComponentSnapshot(ped, componentId)
    end
    return components
end

local function getPedProps(ped)
    local props = {}
    for i = 1, #constants.PED_PROPS_IDS do
        local propId = constants.PED_PROPS_IDS[i]
        props[i] = getPropSnapshot(ped, propId)
    end
    return props
end

local function getPedHeadBlend(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or not isPedFreemodeModel(ped) then
        return nil
    end

    local cached = PED_HEAD_BLEND_CACHE[ped]
    local model = GetEntityModel(ped)
    if cached and cached.model == model and cached.data then
        return copyHeadBlend(cached.data)
    end

    return rememberPedHeadBlend(ped, getDefaultHeadBlend(ped))
end

local function getPedFaceFeatures(ped)
    local faceFeatures = {}
    for i = 1, #constants.FACE_FEATURES do
        local feature = constants.FACE_FEATURES[i]
        faceFeatures[feature] = tonumber(string.format("%.1f", GetPedFaceFeature(ped, i - 1)))
    end
    return faceFeatures
end

local function getPedHeadOverlays(ped)
    local headOverlays = {}
    for i = 1, #constants.HEAD_OVERLAYS do
        local overlay = constants.HEAD_OVERLAYS[i]
        local _, value, _, firstColor, secondColor, opacity = GetPedHeadOverlayData(ped, i - 1)

        if value ~= 255 then
            opacity = tonumber(string.format("%.1f", opacity))
        else
            value = 0
            opacity = 0
        end

        headOverlays[overlay] = {
            style = value,
            opacity = opacity,
            color = firstColor,
            secondColor = secondColor
        }
    end

    return headOverlays
end

local function getPedHair(ped)
    local component = getComponentSnapshot(ped, 2)
    return {
        style = component.drawable,
        color = GetPedHairColor(ped),
        highlight = GetPedHairHighlightColor(ped),
        texture = component.texture,
        palette = component.palette,
        collection = component.collection,
        local_drawable = component.local_drawable
    }
end

local function getPedDecorationType(ped)
    local model = GetEntityModel(ped)
    if model == GetHashKey('mp_m_freemode_01') then
        return "male"
    elseif model == GetHashKey('mp_f_freemode_01') then
        return "female"
    end
    return IsPedMale(ped) and "male" or "female"
end

local PED_TATTOOS = {}

local function applyAutomaticFade(ped, style)
    local gender = getPedDecorationType(ped)
    local hairDecoration = constants.HAIR_DECORATIONS[gender] and constants.HAIR_DECORATIONS[gender][style]
    if hairDecoration then
        AddPedDecorationFromHashes(ped, hairDecoration[1], hairDecoration[2])
    end
end

local function setTattoos(ped, tattoos, style)
    local isMale = getPedDecorationType(ped) == "male"
    ClearPedDecorations(ped)

    if Config.AutomaticFade then
        tattoos["ZONE_HAIR"] = {}
        PED_TATTOOS["ZONE_HAIR"] = {}
        applyAutomaticFade(ped, style or GetPedDrawableVariation(ped, 2))
    end

    for zone in pairs(tattoos) do
        for i = 1, #tattoos[zone] do
            local tattoo = tattoos[zone][i]
            local tattooGender = isMale and tattoo.hashMale or tattoo.hashFemale
            for _ = 1, (tattoo.opacity or 0.1) * 10 do
                AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattooGender))
            end
        end
    end

    if Config.RCoreTattoosCompatibility then
        TriggerEvent("rcore_tattoos:applyOwnedTattoos")
    end
end

local function setPedHair(ped, hair, tattoos)
    if hair then
        -- In a freemode ped the tint natives depend on a completed head blend.
        -- Enhanced exposes the unfinished state as the familiar bright-green
        -- fallback, most visibly on colour index 0 (the normal black swatch).
        if isPedFreemodeModel(ped)
            and ensureFreemodeHeadBlendReady
            and not ensureFreemodeHeadBlendReady(ped) then
            return nil
        end

        local applied = safeComponentVariation(
            ped,
            2,
            hair.style,
            hair.texture,
            hair.collection,
            hair.local_drawable,
            hair.palette
        )
        if not applied then return nil end
        local color = clampInteger(hair.color, 0, 63, 0)
        local highlight = clampInteger(hair.highlight, 0, 63, 0)
        if isPedFreemodeModel(ped) then
            setTattoos(ped, tattoos or PED_TATTOOS, applied.drawable)
        end
        -- ClearPedDecorations/reapplying the automatic hair decoration can
        -- rebuild the hair material. Apply the tint last so Enhanced never
        -- publishes the temporary green material to nearby clients.
        SetPedHairColor(ped, color, highlight)
        -- No Enhanced o indice zero precisa existir tempo suficiente como uma
        -- mudanca de rede. Fazemos 0 -> 1 -> 0 com intervalo real, sem deixar
        -- uma escolha antiga sobrescrever a mais recente.
        local tintVersion = (PED_HAIR_TINT_VERSION[ped] or 0) + 1
        PED_HAIR_TINT_VERSION[ped] = tintVersion
        local expectedModel = GetEntityModel(ped)
        CreateThread(function()
            Wait(100)
            if PED_HAIR_TINT_VERSION[ped] ~= tintVersion
                or not DoesEntityExist(ped)
                or GetEntityModel(ped) ~= expectedModel then
                return
            end

            if color == 0 or highlight == 0 then
                SetPedHairColor(ped, color == 0 and 1 or color, highlight == 0 and 1 or highlight)
                Wait(350)
                if PED_HAIR_TINT_VERSION[ped] ~= tintVersion
                    or not DoesEntityExist(ped)
                    or GetEntityModel(ped) ~= expectedModel then
                    return
                end
            end

            SetPedHairColor(ped, color, highlight)
            Wait(500)
            if PED_HAIR_TINT_VERSION[ped] == tintVersion
                and DoesEntityExist(ped)
                and GetEntityModel(ped) == expectedModel then
                SetPedHairColor(ped, color, highlight)
            end
        end)
        return {
            style = applied.drawable,
            texture = applied.texture,
            palette = applied.palette,
            collection = applied.collection,
            local_drawable = applied.local_drawable,
            color = color,
            highlight = highlight
        }
    end
    return nil
end

local function setPedEyeColor(ped, eyeColor)
    if eyeColor then
        SetPedEyeColor(ped, clampInteger(eyeColor, 0, #constants.EYE_COLORS - 1, 0))
    end
end

local function setPedHeadBlend(ped, headBlend)
    if not headBlend or not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or not isPedFreemodeModel(ped) then
        return false
    end

    local safe = rememberPedHeadBlend(ped, headBlend)
    SetPedHeadBlendData(
        ped,
        safe.shapeFirst,
        safe.shapeSecond,
        safe.shapeThird,
        safe.skinFirst,
        safe.skinSecond,
        safe.skinThird,
        tofloat(safe.shapeMix),
        tofloat(safe.skinMix),
        tofloat(safe.thirdMix),
        false
    )
    return true
end

local function waitForPedHeadBlend(ped, timeout)
    local cached = PED_HEAD_BLEND_CACHE[ped]
    local function markSettled(timedOut, finalized, nativeFinished)
        if cached and cached.model == GetEntityModel(ped) then
            cached.settled = true
            cached.timedOut = timedOut == true
            cached.finalized = finalized == true
            cached.nativeFinished = nativeFinished == true
        end
    end

    if type(HasPedHeadBlendFinished) ~= 'function' then
        Wait(0)
        markSettled(false, false, true)
        return DoesEntityExist(ped)
    end

    local started = GetGameTimer()
    timeout = math.max(0, asInteger(timeout) or HEAD_BLEND_TIMEOUT_MS)
    while DoesEntityExist(ped) and not HasPedHeadBlendFinished(ped) do
        if GetGameTimer() - started >= timeout then
            -- vMenu Enhanced also treats this as a bounded wait instead of a
            -- fatal error. FINALIZE_HEAD_BLEND commits the material when the
            -- completion flag remains pending even though the face is usable.
            local finalized = false
            if type(FinalizeHeadBlend) == 'function' then
                FinalizeHeadBlend(ped)
                finalized = true
                Wait(0)
            end
            local nativeFinished = DoesEntityExist(ped) and HasPedHeadBlendFinished(ped)
            markSettled(true, finalized, nativeFinished)
            return DoesEntityExist(ped)
        end
        Wait(0)
    end
    local nativeFinished = DoesEntityExist(ped) and HasPedHeadBlendFinished(ped)
    markSettled(false, false, nativeFinished)
    return DoesEntityExist(ped)
end

local function setPedHeadBlendAndWait(ped, headBlend)
    if not setPedHeadBlend(ped, headBlend) then return false end
    return waitForPedHeadBlend(ped, HEAD_BLEND_TIMEOUT_MS)
end

ensureFreemodeHeadBlendReady = function(ped)
    if not isPedFreemodeModel(ped) then return true end
    local cached = PED_HEAD_BLEND_CACHE[ped]
    if type(HasPedHeadBlendFinished) ~= 'function' then return true end
    if HasPedHeadBlendFinished(ped) then
        if cached then
            cached.settled = true
            cached.nativeFinished = true
        end
        return true
    end
    -- Some Enhanced clients keep the native flag false after the bounded wait.
    -- Do not restart the asynchronous blend for every colour click once the
    -- writer already finalized/settled this exact ped.
    if cached and cached.model == GetEntityModel(ped) and cached.settled then return true end

    -- Only reapply data that this resource has already validated for this exact
    -- ped/model. Never replace another appearance resource's face with a
    -- guessed default after an ob_creator restart.
    if not cached or cached.model ~= GetEntityModel(ped) or not cached.data then return true end
    return setPedHeadBlendAndWait(ped, cached.data)
end

local function getPedHeadBlendStatus(ped)
    local cached = PED_HEAD_BLEND_CACHE[ped]
    local nativeFinished = type(HasPedHeadBlendFinished) ~= 'function' or HasPedHeadBlendFinished(ped)
    return {
        cached = cached ~= nil and cached.model == GetEntityModel(ped),
        settled = cached and cached.settled == true or false,
        timedOut = cached and cached.timedOut == true or false,
        finalized = cached and cached.finalized == true or false,
        nativeFinished = nativeFinished == true
    }
end

local function setPedFaceFeatures(ped, faceFeatures)
    if faceFeatures then
        for k, v in pairs(constants.FACE_FEATURES) do
            local value = tonumber(faceFeatures[v]) or 0
            SetPedFaceFeature(ped, k - 1, tofloat(math.max(-1.0, math.min(1.0, value))))
        end
    end
end

local function getHeadOverlayColorType(overlayName)
    -- Native reference: type 1 = eyebrows, beard, makeup and chest hair;
    -- type 2 = blush and lipstick. Other overlays do not use a tint.
    if overlayName == 'blush' or overlayName == 'lipstick' then return 2 end
    if overlayName == 'eyebrows' or overlayName == 'beard'
        or overlayName == 'makeUp' or overlayName == 'chestHair' then
        return 1
    end
    return nil
end

local function setPedHeadOverlays(ped, headOverlays)
    if headOverlays then
        if isPedFreemodeModel(ped) and not ensureFreemodeHeadBlendReady(ped) then return false end
        local appliedTints = {}
        for k, v in pairs(constants.HEAD_OVERLAYS) do
            local headOverlay = headOverlays[v] or { style = 0, opacity = 0, color = 0, secondColor = 0 }
            local overlayId = k - 1
            local styleCount = GetPedHeadOverlayNum(overlayId)
            local rawStyle = tonumber(headOverlay.style) or 0
            local style = rawStyle == 255 and 0 or clampInteger(rawStyle, 0, math.max(0, (styleCount or 1) - 1), 0)
            local opacity = rawStyle == 255 and 0.0 or math.max(0.0, math.min(1.0, tonumber(headOverlay.opacity) or 0.0))
            SetPedHeadOverlay(ped, overlayId, style, tofloat(opacity))

            local colorType = getHeadOverlayColorType(v)
            if colorType and headOverlay.color ~= nil then
                local color = clampInteger(headOverlay.color, 0, 63, 0)
                local secondColor = clampInteger(headOverlay.secondColor, 0, 63, color)
                SetPedHeadOverlayColor(ped, overlayId, colorType, color, secondColor)
                if opacity > 0.0 and (color == 0 or secondColor == 0) then
                    appliedTints[#appliedTints + 1] = {
                        overlayId = overlayId,
                        colorType = colorType,
                        color = color,
                        secondColor = secondColor,
                    }
                end
            end
        end

        -- Enhanced pode publicar o material temporario verde para os outros
        -- clientes quando o primeiro tint chega junto da criacao do overlay.
        -- Mudar uma vez para um indice valido, aguardar a rede publicar e so
        -- entao voltar reproduz o intervalo real entre avancar/voltar.
        -- A versao impede que uma thread antiga restaure uma cor ja alterada.
        local tintVersion = (PED_HEAD_OVERLAY_TINT_VERSION[ped] or 0) + 1
        PED_HEAD_OVERLAY_TINT_VERSION[ped] = tintVersion
        local expectedModel = GetEntityModel(ped)
        CreateThread(function()
            Wait(100)
            if PED_HEAD_OVERLAY_TINT_VERSION[ped] ~= tintVersion
                or not DoesEntityExist(ped)
                or GetEntityModel(ped) ~= expectedModel then
                return
            end

            for i = 1, #appliedTints do
                local tint = appliedTints[i]
                local temporaryColor = tint.color == 0 and 1 or tint.color
                local temporarySecond = tint.secondColor == 0 and 1 or tint.secondColor
                SetPedHeadOverlayColor(
                    ped,
                    tint.overlayId,
                    tint.colorType,
                    temporaryColor,
                    temporarySecond
                )
            end

            Wait(350)
            if PED_HEAD_OVERLAY_TINT_VERSION[ped] ~= tintVersion
                or not DoesEntityExist(ped)
                or GetEntityModel(ped) ~= expectedModel then
                return
            end

            for i = 1, #appliedTints do
                local tint = appliedTints[i]
                SetPedHeadOverlayColor(
                    ped,
                    tint.overlayId,
                    tint.colorType,
                    tint.color,
                    tint.secondColor
                )
            end

            -- Uma escrita final cobre peers que começaram a enxergar o ped
            -- durante a transicao acima.
            Wait(500)
            if PED_HEAD_OVERLAY_TINT_VERSION[ped] ~= tintVersion
                or not DoesEntityExist(ped)
                or GetEntityModel(ped) ~= expectedModel then
                return
            end
            for i = 1, #appliedTints do
                local tint = appliedTints[i]
                SetPedHeadOverlayColor(ped, tint.overlayId, tint.colorType, tint.color, tint.secondColor)
            end
        end)
        return true
    end
    return false
end

local function setPedComponent(ped, component)
    if component then
        local componentId = asInteger(component.component_id)
        if isPedFreemodeModel(ped) and (componentId == 0 or componentId == 2) then
            return nil
        end
        -- citizenfx/fivem#4037: aplicar o componente 1 depois do head blend
        -- pode causar access violation dentro do GTA. O ped padrao ja fica
        -- sem mascara apos SetPedDefaultComponentVariation, portanto nao
        -- chamamos o native nem mesmo para drawable 0 durante o workaround.
        if Config.EnhancedMaskCrashWorkaround and isPedFreemodeModel(ped) and componentId == 1 then
            return nil
        end
        return safeComponentVariation(
            ped,
            componentId,
            component.drawable,
            component.texture,
            component.collection,
            component.local_drawable,
            component.palette
        )
    end
    return nil
end

local function setPedComponents(ped, components)
    if components then
        for _, v in pairs(components) do
            setPedComponent(ped, v)
        end
    end
end

local function setPedProp(ped, prop)
    if prop then
        return safePropVariation(
            ped,
            prop.prop_id,
            prop.drawable,
            prop.texture,
            prop.collection,
            prop.local_drawable
        )
    end
    return nil
end

local function setPedProps(ped, props)
    if props then
        for _, v in pairs(props) do
            setPedProp(ped, v)
        end
    end
end

local function setPedTattoos(ped, tattoos)
    if type(tattoos) ~= 'table' then return end
    PED_TATTOOS = tattoos
    setTattoos(ped, tattoos)
end

local function getPedTattoos()
    return PED_TATTOOS
end

local function getPedAppearance(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or not isPedFreemodeModel(ped) then
        return nil
    end

    local eyeColor = GetPedEyeColor(ped)

    return {
        model = GetEntityModel(ped) == GetHashKey('mp_f_freemode_01') and "mp_f_freemode_01" or "mp_m_freemode_01",
        headBlend = getPedHeadBlend(ped),
        faceFeatures = getPedFaceFeatures(ped),
        headOverlays = getPedHeadOverlays(ped),
        components = getPedComponents(ped),
        props = getPedProps(ped),
        hair = getPedHair(ped),
        tattoos = getPedTattoos(),
        eyeColor = eyeColor < #constants.EYE_COLORS and eyeColor or 0
    }
end

local function normalizePlayerHealth(targetHealth, targetArmour)
    local ped = PlayerPedId()
    local currentHealth = tonumber(targetHealth) or GetEntityHealth(ped)
    local currentArmour = tonumber(targetArmour) or GetPedArmour(ped)

    SetEntityMaxHealth(ped, 200)
    Wait(50)
    SetEntityHealth(ped, math.max(100, math.min(200, math.floor(currentHealth))), 0, 0)
    SetPedArmour(ped, math.max(0, math.min(100, math.floor(currentArmour))))
end

local function setPlayerModel(model)
    local modelHash = type(model) == "string" and joaat(model) or model
    if not modelHash or not IsModelInCdimage(modelHash)
        or (type(IsModelValid) == 'function' and not IsModelValid(modelHash))
        or (type(IsModelAPed) == 'function' and not IsModelAPed(modelHash)) then
        return false
    end

    local previousPed = PlayerPedId()
    local previousHealth = GetEntityHealth(previousPed)
    local previousArmour = GetPedArmour(previousPed)
    PED_HEAD_BLEND_CACHE[previousPed] = nil

    RequestModel(modelHash)
    local loadStarted = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() - loadStarted >= MODEL_LOAD_TIMEOUT_MS then
            SetModelAsNoLongerNeeded(modelHash)
            return false
        end
        Wait(0)
    end

    if GetEntityModel(previousPed) ~= modelHash then
        SetPlayerModel(PlayerId(), modelHash)

        local swapStarted = GetGameTimer()
        while GetGameTimer() - swapStarted < HEAD_BLEND_TIMEOUT_MS do
            local currentPed = PlayerPedId()
            if currentPed ~= 0 and DoesEntityExist(currentPed) and GetEntityModel(currentPed) == modelHash then break end
            Wait(0)
        end
    end
    SetModelAsNoLongerNeeded(modelHash)

    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or GetEntityModel(ped) ~= modelHash then return false end

    SetPedDefaultComponentVariation(ped)
    for propId = 0, 7 do ClearPedProp(ped, propId) end
    ClearPedDecorations(ped)
    if type(ClearPedFacialDecorations) == 'function' then ClearPedFacialDecorations(ped) end

    if isPedFreemodeModel(ped) then
        if not setPedHeadBlendAndWait(ped, getDefaultHeadBlend(ped)) then
            normalizePlayerHealth(previousHealth, previousArmour)
            return false
        end
    end

    PED_TATTOOS = {}
    normalizePlayerHealth(previousHealth, previousArmour)
    return true
end

local function applyEnhancedSafeAppearance(ped, appearance)
    -- Este modo continua usando exatamente o modelo freemode do personagem.
    -- Ele apenas elimina os dados cosmeticos como variavel durante o teste de
    -- streaming entre jogadores no Enhanced.
    local female = GetEntityModel(ped) == GetHashKey('mp_f_freemode_01')
    SetPedDefaultComponentVariation(ped)
    for propId = 0, 7 do ClearPedProp(ped, propId) end
    ClearPedDecorations(ped)

    local blendFinished
    if female then
        blendFinished = setPedHeadBlendAndWait(ped, {
            shapeFirst = 45, shapeSecond = 21, shapeThird = 0,
            skinFirst = 20, skinSecond = 15, skinThird = 0,
            shapeMix = 0.3, skinMix = 0.1, thirdMix = 0.0
        })
        setPedComponents(ped, {
            { component_id = 3, drawable = 15, texture = 0 },
            { component_id = 4, drawable = 15, texture = 3 },
            { component_id = 6, drawable = 35, texture = 0 },
            { component_id = 8, drawable = 14, texture = 0 },
            { component_id = 11, drawable = 15, texture = 3 }
        })
    else
        blendFinished = setPedHeadBlendAndWait(ped, {
            shapeFirst = 0, shapeSecond = 0, shapeThird = 0,
            skinFirst = 0, skinSecond = 0, skinThird = 0,
            shapeMix = 0.5, skinMix = 0.5, thirdMix = 0.0
        })
        setPedComponents(ped, {
            { component_id = 3, drawable = 15, texture = 0 },
            { component_id = 4, drawable = 61, texture = 0 },
            { component_id = 6, drawable = 34, texture = 0 },
            { component_id = 8, drawable = 15, texture = 0 },
            { component_id = 11, drawable = 15, texture = 0 }
        })
    end

    setPedHair(ped, { style = 0, texture = 0, color = 0, highlight = 0 }, {})
    setPedEyeColor(ped, 0)
    return blendFinished
end

local function setPedAppearance(ped, appearance)
    if not appearance or not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or not isPedFreemodeModel(ped) then
        return false
    end

    if Config.EnhancedAppearanceSafeTest then
        return applyEnhancedSafeAppearance(ped, appearance)
    end

    -- Same order used by vMenu Enhanced: reset the ped, finish the asynchronous
    -- head blend, then touch face data and clothing. This avoids publishing a
    -- half-applied freemode ped when the creator routing bucket is released.
    SetPedDefaultComponentVariation(ped)
    for propId = 0, 7 do ClearPedProp(ped, propId) end
    ClearPedDecorations(ped)
    if type(ClearPedFacialDecorations) == 'function' then ClearPedFacialDecorations(ped) end

    local blendFinished = true
    if appearance.headBlend and isPedFreemodeModel(ped) then
        blendFinished = setPedHeadBlendAndWait(ped, appearance.headBlend)
    end
    if appearance.faceFeatures then setPedFaceFeatures(ped, appearance.faceFeatures) end
    if appearance.headOverlays then setPedHeadOverlays(ped, appearance.headOverlays) end
    if appearance.eyeColor then setPedEyeColor(ped, appearance.eyeColor) end
    -- setPedComponent ignora mascara enquanto o workaround do crash nativo
    -- estiver ativo. SetPedDefaultComponentVariation acima ja restaurou o
    -- componente 1 seguro, sem publicar HEAD_BLEND -> MASK para outros peers.
    setPedComponents(ped, appearance.components)
    setPedProps(ped, appearance.props)
    if appearance.hair then setPedHair(ped, appearance.hair, appearance.tattoos) end
    if appearance.tattoos then setPedTattoos(ped, appearance.tattoos) end
    Wait(0)
    return blendFinished
end

local function setPlayerAppearance(appearance)
    if not appearance then return false end
    local modelHash = type(appearance.model) == 'string' and joaat(appearance.model) or appearance.model
    -- The character selector has already loaded this model. Recreating the
    -- same ped resets it to GTA defaults for a few frames (green hair flash).
    if modelHash and GetEntityModel(PlayerPedId()) ~= modelHash then
        if not setPlayerModel(appearance.model) then return false end
    end
    return setPedAppearance(PlayerPedId(), appearance)
end

Appearance.getPedAppearance = getPedAppearance
Appearance.setPedAppearance = setPedAppearance
Appearance.setPlayerAppearance = setPlayerAppearance
Appearance.setPedComponent = setPedComponent
Appearance.setPedProp = setPedProp
Appearance.setPedHair = setPedHair
Appearance.setPedHeadOverlays = setPedHeadOverlays
Appearance.setPedEyeColor = setPedEyeColor
Appearance.setPedTattoos = setPedTattoos
Appearance.getPedTattoos = getPedTattoos
Appearance.setPlayerModel = setPlayerModel
Appearance.getPedDecorationType = getPedDecorationType
Appearance.setPedHeadBlend = setPedHeadBlend
Appearance.setPedHeadBlendAndWait = setPedHeadBlendAndWait
Appearance.waitForPedHeadBlend = waitForPedHeadBlend
Appearance.getPedHeadBlendStatus = getPedHeadBlendStatus
Appearance.setPedFaceFeatures = setPedFaceFeatures

exports('setPedAppearance', function(ped, appearance)
    return Appearance.setPedAppearance(ped, appearance)
end)

exports('setPlayerAppearance', function(appearance)
    return Appearance.setPlayerAppearance(appearance)
end)

exports('getPedAppearance', function(ped)
    return Appearance.getPedAppearance(ped)
end)

exports('setPlayerModel', function(model)
    return Appearance.setPlayerModel(model)
end)

exports('normalizePlayerHealth', function(targetHealth, targetArmour)
    return normalizePlayerHealth(targetHealth, targetArmour)
end)

exports('setPedHeadBlend', function(ped, headBlend)
    return Appearance.setPedHeadBlend(ped, headBlend)
end)

exports('setPedHeadBlendAndWait', function(ped, headBlend)
    return Appearance.setPedHeadBlendAndWait(ped, headBlend)
end)

exports('setPedFaceFeatures', function(ped, faceFeatures)
    return Appearance.setPedFaceFeatures(ped, faceFeatures)
end)
