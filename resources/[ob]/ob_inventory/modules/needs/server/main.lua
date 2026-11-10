ORInventoryNeeds = ORInventoryNeeds or {}

local needsBySource = {}

local function clamp(value, fallback)
    value = tonumber(value)
    if not value then value = fallback end
    return math.max(0, math.min(100, value))
end

local function copyNeeds(needs)
    return {
        hunger = clamp(needs and needs.hunger, ORInventoryNeedsConfig.DefaultHunger),
        thirst = clamp(needs and needs.thirst, ORInventoryNeedsConfig.DefaultThirst),
        stress = clamp(needs and needs.stress, ORInventoryNeedsConfig.DefaultStress),
    }
end

local function publish(playerSource, needs)
    local player = Player(playerSource)
    if player then player.state:set('or:needs', copyNeeds(needs), true) end
end

local function persist(playerSource)
    local entry = needsBySource[playerSource]
    if not entry or not entry.dirty then return true end

    local saved = exports.ob_core:SetMetadata(playerSource, 'needs', copyNeeds(entry.needs))
    if saved then entry.dirty = false end
    return saved == true
end

local function entryFor(playerSource)
    local entry = needsBySource[playerSource]
    if entry then return entry end
    local character = exports.ob_core:GetCharacter(playerSource)
    return character and ORInventoryNeeds.Load(playerSource, character) or nil
end

function ORInventoryNeeds.Load(playerSource, character)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 or type(character) ~= 'table' or not character.userId then return nil end

    local current = needsBySource[playerSource]
    if current and current.userId == tonumber(character.userId) then
        publish(playerSource, current.needs)
        return current
    end

    local metadata = type(character.metadata) == 'table' and character.metadata or {}
    local entry = {
        userId = tonumber(character.userId),
        needs = copyNeeds(metadata.needs),
        dirty = false,
        lastSave = GetGameTimer(),
    }
    needsBySource[playerSource] = entry
    publish(playerSource, entry.needs)
    return entry
end

function ORInventoryNeeds.Unload(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return end
    persist(playerSource)
    needsBySource[playerSource] = nil
end

function ORInventoryNeeds.Get(playerSource)
    local entry = entryFor(tonumber(playerSource))
    return entry and copyNeeds(entry.needs) or nil
end

function ORInventoryNeeds.Set(playerSource, hunger, thirst, stress)
    playerSource = tonumber(playerSource)
    local entry = playerSource and entryFor(playerSource)
    if not entry then return false end

    entry.needs.hunger = clamp(hunger, entry.needs.hunger)
    entry.needs.thirst = clamp(thirst, entry.needs.thirst)
    entry.needs.stress = clamp(stress, entry.needs.stress)
    entry.dirty = true
    publish(playerSource, entry.needs)
    return true
end

function ORInventoryNeeds.ApplyEffects(playerSource, effects)
    effects = type(effects) == 'table' and effects or {}
    local entry = entryFor(tonumber(playerSource))
    if not entry then return false, 'Necessidades do personagem ainda nao foram carregadas.' end

    local applied = ORInventoryNeeds.Set(
        playerSource,
        entry.needs.hunger + (tonumber(effects.hunger) or 0),
        entry.needs.thirst + (tonumber(effects.thirst) or 0),
        entry.needs.stress + (tonumber(effects.stress) or 0)
    )
    return applied, applied and nil or 'Nao foi possivel atualizar as necessidades.'
end

exports('GetNeeds', ORInventoryNeeds.Get)
exports('SetNeeds', ORInventoryNeeds.Set)
exports('AddHunger', function(playerSource, amount)
    local entry = entryFor(tonumber(playerSource))
    return entry and ORInventoryNeeds.Set(playerSource, entry.needs.hunger + (tonumber(amount) or 0), entry.needs.thirst, entry.needs.stress) or false
end)
exports('AddThirst', function(playerSource, amount)
    local entry = entryFor(tonumber(playerSource))
    return entry and ORInventoryNeeds.Set(playerSource, entry.needs.hunger, entry.needs.thirst + (tonumber(amount) or 0), entry.needs.stress) or false
end)
exports('SetStress', function(playerSource, stress)
    local entry = entryFor(tonumber(playerSource))
    return entry and ORInventoryNeeds.Set(playerSource, entry.needs.hunger, entry.needs.thirst, stress) or false
end)
exports('AddStress', function(playerSource, amount)
    local entry = entryFor(tonumber(playerSource))
    return entry and ORInventoryNeeds.Set(playerSource, entry.needs.hunger, entry.needs.thirst, entry.needs.stress + (tonumber(amount) or 0)) or false
end)

CreateThread(function()
    Wait(250)
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        local character = exports.ob_core:GetCharacter(playerSource)
        if character then ORInventoryNeeds.Load(playerSource, character) end
    end
end)

CreateThread(function()
    while true do
        Wait(ORInventoryNeedsConfig.TickInterval)
        local now = GetGameTimer()
        for playerSource, entry in pairs(needsBySource) do
            if GetPlayerName(playerSource) then
                entry.needs.hunger = clamp(entry.needs.hunger - ORInventoryNeedsConfig.HungerLossPerTick, 0)
                entry.needs.thirst = clamp(entry.needs.thirst - ORInventoryNeedsConfig.ThirstLossPerTick, 0)
                entry.dirty = true
                publish(playerSource, entry.needs)
                if now - entry.lastSave >= ORInventoryNeedsConfig.SaveInterval then
                    persist(playerSource)
                    entry.lastSave = now
                end
            else
                needsBySource[playerSource] = nil
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for playerSource in pairs(needsBySource) do persist(playerSource) end
end)
