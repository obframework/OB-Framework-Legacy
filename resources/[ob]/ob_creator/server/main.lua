-- All character creators use the same underground coordinate.  Keeping each
-- player in a private routing bucket prevents unfinished freemode peds and
-- component changes from being streamed to other players in that room.
local CREATob_BUCKET_OFFSET = 10000
local creatorBuckets = {}
local appearanceEdits = {}
local appearanceSchemaReady = false

local function setCreatorInstance(src, enabled)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false end

    if enabled then
        local edit = appearanceEdits[src]
        if edit and edit.returnBucket == nil then edit.returnBucket = GetPlayerRoutingBucket(src) end
        local bucket = CREATob_BUCKET_OFFSET + src
        SetPlayerRoutingBucket(src, bucket)
        creatorBuckets[src] = bucket
        return true
    end

    local edit = appearanceEdits[src]
    SetPlayerRoutingBucket(src, (edit and edit.returnBucket) or exports['ob_core']:GetSelectionBucket(src) or 0)
    creatorBuckets[src] = nil
    return true
end

OR.Callback.register('enterCreatorInstance', function(source)
    return setCreatorInstance(source, true)
end)

OR.Callback.register('leaveCreatorInstance', function(source)
    return setCreatorInstance(source, false)
end)

-- Usado somente para liberar a instancia caso o cliente do criador seja
-- reiniciado durante a criacao. Nao altera personagem nem aparencia.
RegisterNetEvent('ob_creator:server:abortCreator', function()
    setCreatorInstance(source, false)
    appearanceEdits[source] = nil
end)

AddEventHandler('playerDropped', function()
    creatorBuckets[source] = nil
    appearanceEdits[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src in pairs(creatorBuckets) do
        if GetPlayerName(src) then
            local edit = appearanceEdits[src]
            SetPlayerRoutingBucket(src, (edit and edit.returnBucket) or exports['ob_core']:GetSelectionBucket(src) or 0)
        end
    end
end)

-- `playerskins` veio de uma base Legacy e contem valores que o Enhanced nao
-- aceita mais. O cliente ainda confere cada drawable antes de aplica-lo, mas
-- os dados nao podem continuar sendo gravados crus no banco: outro recurso
-- pode le-los depois e repassar um indice invalido ao ped nativo.
local function clampNumber(value, minimum, maximum, fallback, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    if integer then value = math.floor(value) end
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeCollection(value)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('%z', '')
    if #value > 96 then value = value:sub(1, 96) end
    return value
end

local overlayNames = {
    'blemishes', 'beard', 'eyebrows', 'ageing', 'makeUp', 'blush',
    'complexion', 'sunDamage', 'lipstick', 'moleAndFreckles',
    'chestHair', 'bodyBlemishes'
}

local function normalizeAppearance(appearance)
    if type(appearance) ~= 'table' then return nil end

    local model = type(appearance.model) == 'string' and appearance.model:lower() or ''
    if model ~= 'mp_m_freemode_01' and model ~= 'mp_f_freemode_01' then
        return nil
    end

    appearance.model = model
    local components, seenComponents = {}, {}
    for _, component in pairs(type(appearance.components) == 'table' and appearance.components or {}) do
        if type(component) == 'table' then
            local id = clampNumber(component.component_id, 0, 11, -1, true)
            if id >= 0 and not seenComponents[id] then
                seenComponents[id] = true
                if Config.EnhancedMaskCrashWorkaround and id == 1 then
                    -- Nao perpetue no banco uma mascara que o cliente nao pode
                    -- aplicar com seguranca depois de SET_PED_HEAD_BLEND_DATA.
                    components[#components + 1] = {
                        component_id = 1,
                        drawable = 0,
                        texture = 0,
                        palette = 0,
                        collection = '',
                        local_drawable = -1
                    }
                else
                    components[#components + 1] = {
                        component_id = id,
                        drawable = clampNumber(component.drawable, 0, 2047, 0, true),
                        texture = clampNumber(component.texture, 0, 255, 0, true),
                        palette = clampNumber(component.palette, 0, 3, 0, true),
                        collection = normalizeCollection(component.collection),
                        local_drawable = clampNumber(component.local_drawable, -1, 2047, -1, true)
                    }
                end
            end
        end
    end
    appearance.components = components

    local props, seenProps = {}, {}
    for _, prop in pairs(type(appearance.props) == 'table' and appearance.props or {}) do
        if type(prop) == 'table' then
            local id = clampNumber(prop.prop_id, 0, 7, -1, true)
            if id >= 0 and not seenProps[id] then
                seenProps[id] = true
                local drawable = clampNumber(prop.drawable, -1, 2047, -1, true)
                props[#props + 1] = {
                    prop_id = id,
                    drawable = drawable,
                    texture = drawable < 0 and 0 or clampNumber(prop.texture, 0, 255, 0, true),
                    collection = drawable < 0 and '' or normalizeCollection(prop.collection),
                    local_drawable = drawable < 0 and -1 or clampNumber(prop.local_drawable, -1, 2047, -1, true)
                }
            end
        end
    end
    appearance.props = props

    local hair = type(appearance.hair) == 'table' and appearance.hair or {}
    appearance.hair = {
        style = clampNumber(hair.style, 0, 2047, 0, true),
        texture = clampNumber(hair.texture, 0, 255, 0, true),
        palette = clampNumber(hair.palette, 0, 3, 0, true),
        collection = normalizeCollection(hair.collection),
        local_drawable = clampNumber(hair.local_drawable, -1, 2047, -1, true),
        color = clampNumber(hair.color, 0, 63, 0, true),
        highlight = clampNumber(hair.highlight, 0, 63, 0, true)
    }
    appearance.eyeColor = clampNumber(appearance.eyeColor, 0, 31, 0, true)

    local blend = type(appearance.headBlend) == 'table' and appearance.headBlend or {}
    appearance.headBlend = {
        shapeFirst = clampNumber(blend.shapeFirst, 0, 45, 0, true),
        shapeSecond = clampNumber(blend.shapeSecond, 0, 45, 0, true),
        shapeThird = clampNumber(blend.shapeThird, 0, 45, 0, true),
        skinFirst = clampNumber(blend.skinFirst, 0, 45, 0, true),
        skinSecond = clampNumber(blend.skinSecond, 0, 45, 0, true),
        skinThird = clampNumber(blend.skinThird, 0, 45, 0, true),
        shapeMix = clampNumber(blend.shapeMix, 0.0, 1.0, 0.5, false),
        skinMix = clampNumber(blend.skinMix, 0.0, 1.0, 0.5, false),
        thirdMix = clampNumber(blend.thirdMix, 0.0, 1.0, 0.0, false)
    }

    local faceFeatures = {}
    for name, value in pairs(type(appearance.faceFeatures) == 'table' and appearance.faceFeatures or {}) do
        if type(name) == 'string' and #name <= 48 then
            faceFeatures[name] = clampNumber(value, -1.0, 1.0, 0.0, false)
        end
    end
    appearance.faceFeatures = faceFeatures

    local overlays = type(appearance.headOverlays) == 'table' and appearance.headOverlays or {}
    local normalizedOverlays = {}
    for _, name in ipairs(overlayNames) do
        local overlay = type(overlays[name]) == 'table' and overlays[name] or {}
        normalizedOverlays[name] = {
            style = clampNumber(overlay.style, 0, 255, 0, true),
            opacity = clampNumber(overlay.opacity, 0.0, 1.0, 0.0, false),
            color = clampNumber(overlay.color, 0, 63, 0, true),
            secondColor = clampNumber(overlay.secondColor, 0, 63, 0, true)
        }
    end
    appearance.headOverlays = normalizedOverlays

    local tattoos = {}
    for zone, entries in pairs(type(appearance.tattoos) == 'table' and appearance.tattoos or {}) do
        if type(zone) == 'string' and #zone <= 64 and type(entries) == 'table' then
            local cleanEntries = {}
            for _, tattoo in ipairs(entries) do
                if #cleanEntries >= 40 then break end
                if type(tattoo) == 'table' and type(tattoo.collection) == 'string'
                    and type(tattoo.hashMale) == 'string' and type(tattoo.hashFemale) == 'string'
                    and #tattoo.collection <= 96 and #tattoo.hashMale <= 96 and #tattoo.hashFemale <= 96 then
                    cleanEntries[#cleanEntries + 1] = {
                        name = type(tattoo.name) == 'string' and tattoo.name:sub(1, 96) or nil,
                        collection = tattoo.collection,
                        hashMale = tattoo.hashMale,
                        hashFemale = tattoo.hashFemale,
                        opacity = clampNumber(tattoo.opacity, 0.0, 1.0, 0.1, false)
                    }
                end
            end
            if #cleanEntries > 0 then tattoos[zone] = cleanEntries end
        end
    end
    appearance.tattoos = tattoos

    return appearance
end

exports('NormalizeAppearance', normalizeAppearance)

CreateThread(function()
    local deadline = GetGameTimer() + 15000
    while not exports['ob_core']:IsDatabaseReady() and GetGameTimer() < deadline do
        Wait(100)
    end

    if not exports['ob_core']:IsDatabaseReady() then
        print('[ob_creator] Schema do ob_core nao ficou pronto; tabela de aparencias nao foi criada.')
        return
    end

    OR.Database.query.await([[CREATE TABLE IF NOT EXISTS `ob_character_appearances` (
        `user_id` bigint unsigned NOT NULL,
        `model` varchar(64) NOT NULL,
        `appearance` mediumtext NOT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`user_id`),
        CONSTRAINT `fk_ob_character_appearances_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]])
    appearanceSchemaReady = true
end)

local function waitForAppearanceSchema()
    local deadline = GetGameTimer() + 15000
    while not appearanceSchemaReady and GetGameTimer() < deadline do
        Wait(100)
    end
    return appearanceSchemaReady
end

local function getAppearance(source)
    if not waitForAppearanceSchema() then return nil end
    local userId = exports['ob_core']:GetUserId(source)
    if not userId then return nil end

    local appearanceJson = OR.Database.scalar.await('SELECT appearance FROM ob_character_appearances WHERE user_id = ? LIMIT 1', { userId })
    if not appearanceJson then return nil end

    local ok, appearance = pcall(json.decode, appearanceJson)
    return ok and normalizeAppearance(appearance) or nil
end

OR.Callback.register('getAppearance', getAppearance)
exports('GetAppearanceForSource', getAppearance)

local function saveAppearance(src, appearance, expectedUserId)
    if not waitForAppearanceSchema() then return false end
    appearance = normalizeAppearance(appearance)
    local userId = exports['ob_core']:GetUserId(src)
    if expectedUserId and userId ~= expectedUserId then return false end
    if not userId or not appearance then return false end

    local result = OR.Database.query.await([[INSERT INTO ob_character_appearances (user_id, model, appearance)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE model = VALUES(model), appearance = VALUES(appearance), updated_at = current_timestamp()]], {
        userId, appearance.model, json.encode(appearance)
    })
    if result == nil then return false end
    return true
end

OR.Callback.register('saveAppearance', function(source, appearance)
    return saveAppearance(source, appearance)
end)

-- Checkout de lojas externas usa a mesma normalizacao e a mesma tabela do
-- criador, sem duplicar regras de aparencia no recurso que realiza a cobranca.
exports('SaveAppearanceForSource', saveAppearance)

-- Autorizacao de uso unico concedida pelo servidor administrativo. Nao apaga
-- aparencia nem cria personagem: salva apenas ob_character_appearances.
local function editIdentity(src)
    local player = exports.ob_core:GetPlayer(src)
    return player and player.character and player.character.userId
end

local function validAppearanceEdit(src)
    local edit = appearanceEdits[src]
    return edit and GetGameTimer() <= edit.expiresAt
        and editIdentity(src) == edit.userId and editIdentity(edit.actor) == edit.actorUserId
        and GetResourceState('ob_admin') == 'started'
        and exports.ob_admin:CanResetAppearance(edit.actor, src) == true and edit or nil
end

exports('BeginAppearanceEdit', function(src, actor)
    src, actor = tonumber(src), tonumber(actor)
    if GetInvokingResource() ~= 'ob_admin' or not src or not actor then return false, 'Origem invalida.' end
    if not exports.ob_admin:CanResetAppearance(actor, src) then return false, 'Nao e permitido editar outro staff.' end
    local userId, actorUserId = editIdentity(src), editIdentity(actor)
    if not userId or not actorUserId then return false, 'Personagem ainda nao esta pronto.' end
    local previous = appearanceEdits[src]
    if previous and not previous.opened and GetGameTimer() > previous.expiresAt then appearanceEdits[src] = nil end
    if creatorBuckets[src] or appearanceEdits[src] then return false, 'O jogador ja tem uma edicao em andamento.' end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 or Player(src).state['or:downed'] == true then
        return false, 'O jogador precisa estar consciente e fora de veiculos.'
    end
    appearanceEdits[src] = {actor=actor, actorUserId=actorUserId, userId=userId, expiresAt=GetGameTimer()+60000}
    TriggerClientEvent('ob_creator:client:editAppearance', src)
    return true
end)

OR.Callback.register('beginAppearanceEdit', function(src)
    local edit = validAppearanceEdit(src)
    if not edit or edit.opened then return false, 'Autorizacao de aparencia invalida ou expirada.' end
    edit.opened = true
    edit.expiresAt = GetGameTimer()+1800000
    local appearance = getAppearance(src)
    if validAppearanceEdit(src) ~= edit then return false, 'A sessao foi alterada.' end
    if not setCreatorInstance(src, true) then return false, 'Nao foi possivel isolar a edicao.' end
    return true, appearance
end)

OR.Callback.register('finishAppearanceEdit', function(src, appearance)
    local edit = validAppearanceEdit(src)
    if not edit or not edit.opened or edit.saving then return false, 'Autorizacao de aparencia invalida ou expirada.' end
    if not OR.Security.validatePayload(appearance, {maxDepth=7, maxNodes=1200, maxStringBytes=65536}) then
        return false, 'Aparencia invalida.'
    end
    edit.saving = true
    local ok, saved = pcall(saveAppearance, src, appearance, edit.userId)
    edit.saving = false
    if not ok or not saved then return false, 'Nao foi possivel salvar a aparencia.' end
    -- Nao restaurar bucket de uma nova sessao que reutilizou o mesmo source.
    if appearanceEdits[src] ~= edit or editIdentity(src) ~= edit.userId then return false, 'A sessao foi alterada.' end
    setCreatorInstance(src, false)
    appearanceEdits[src] = nil
    return true
end)

OR.Callback.register('cancelAppearanceEdit', function(src)
    local edit = appearanceEdits[src]
    if edit and edit.saving then return false end
    if edit then
        if edit.returnBucket ~= nil then setCreatorInstance(src, false) end
        appearanceEdits[src] = nil
    end
    return true
end)

RegisterNetEvent('ob_creator:server:saveAppearance', function(appearance)
    if not OR.Security.rateLimit(source, 'creator:save_appearance', 3, 15000) then return end
    if not OR.Security.validatePayload(appearance, { maxDepth = 7, maxNodes = 1200, maxStringBytes = 65536 }) then return end
    saveAppearance(source, appearance)
end)

RegisterNetEvent('ob_creator:server:purchaseAndSave', function()
    if not OR.Security.rateLimit(source, 'creator:purchase', 2, 10000) then return end
    TriggerClientEvent('ob_creator:client:purchaseResult', source, false, 'A economia da OB Framework ainda nao esta disponivel.')
end)

local function diagnosticInteger(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return minimum end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

RegisterNetEvent('ob_creator:server:hairDiagnostic', function(data)
    local src = source
    if src <= 0 or not IsPlayerAceAllowed(src, 'or.developer') or type(data) ~= 'table' then return end
    if not OR.Security.rateLimit(src, 'creator:hair_diagnostic', 4, 10000) then return end

    local rgb0 = type(data.rgb0) == 'table' and data.rgb0 or {}
    local rgb1 = type(data.rgb1) == 'table' and data.rgb1 or {}
    print(('[ob_creator] hairdiag source=%d model=%d blend=%s cached=%s settled=%s timeout=%s finalized=%s style=%d texture=%d palette=%d color=%d highlight=%d rgb0=%d,%d,%d rgb1=%d,%d,%d'):format(
        src,
        diagnosticInteger(data.model, -2147483648, 4294967295),
        data.blendFinished == true and 'ready' or 'pending',
        data.blendCached == true and 'yes' or 'no',
        data.blendSettled == true and 'yes' or 'no',
        data.blendTimedOut == true and 'yes' or 'no',
        data.blendFinalized == true and 'yes' or 'no',
        diagnosticInteger(data.style, 0, 4095),
        diagnosticInteger(data.texture, 0, 255),
        diagnosticInteger(data.palette, 0, 3),
        diagnosticInteger(data.color, 0, 63),
        diagnosticInteger(data.highlight, 0, 63),
        diagnosticInteger(rgb0[1], 0, 255),
        diagnosticInteger(rgb0[2], 0, 255),
        diagnosticInteger(rgb0[3], 0, 255),
        diagnosticInteger(rgb1[1], 0, 255),
        diagnosticInteger(rgb1[2], 0, 255),
        diagnosticInteger(rgb1[3], 0, 255)
    ))
end)
