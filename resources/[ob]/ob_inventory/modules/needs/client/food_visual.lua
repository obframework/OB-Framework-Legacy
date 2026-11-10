-- Apenas representacao visual. Inventario/consumo continuam validados no servidor.
-- Cada observador desenha um objeto local, sem depender do streaming de um
-- objeto de rede anexado ao ped (mesmo caminho do teste de props).
ORInventoryFoodVisual = {}
local remotes, serial, active = {}, 0, nil
local function yes(value) return value == true or value == 1 end
local function remove(entry)
    entry.cancelled = true
    if entry.object and yes(DoesEntityExist(entry.object)) and GetEntityModel(entry.object) == entry.model then
        DeleteEntity(entry.object)
    end
end
function ORInventoryFoodVisual.Start(name)
    if not (ORInventoryNeedsConfig.Consumables or {})[name] then return end
    serial = serial + 1
    active = serial
    TriggerServerEvent('ob_inventory:server:foodVisual', name, active)
end
function ORInventoryFoodVisual.Stop()
    if not active then return end
    local token = active
    active = nil
    TriggerServerEvent('ob_inventory:server:foodVisual', nil, token)
end

local function createRemote(entry, config)
    CreateThread(function()
        local model = type(config.model) == 'number' and config.model or joaat(config.model)
        if not yes(IsModelInCdimage(model)) or not yes(IsModelValid(model)) then return end
        RequestModel(model)
        local deadline = GetGameTimer() + 3000
        while not entry.cancelled and not yes(HasModelLoaded(model)) and GetGameTimer() < deadline do Wait(0) end
        if entry.cancelled or not yes(HasModelLoaded(model)) or not yes(DoesEntityExist(entry.ped)) then
            SetModelAsNoLongerNeeded(model)
            return
        end
        local p = GetEntityCoords(entry.ped)
        local object = CreateObjectNoOffset(model, p.x, p.y, p.z, false, false, false)
        entry.object, entry.model = object, model
        SetModelAsNoLongerNeeded(model)
        if object == 0 or not yes(DoesEntityExist(object)) then return end
        SetEntityAsMissionEntity(object, true, true)
        SetEntityCollision(object, false, false)
        SetEntityVisible(object, true, false)
        local pos, rot = config.position or {}, config.rotation or {}
        AttachEntityToEntity(object, entry.ped, GetPedBoneIndex(entry.ped, config.bone or 18905),
            pos.x or 0.0, pos.y or 0.0, pos.z or 0.0, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0,
            false, false, false, true, 2, true)
    end)
end

CreateThread(function()
    while true do
        local seen, origin = {}, GetEntityCoords(PlayerPedId())
        for _, player in ipairs(GetActivePlayers()) do
            if player ~= PlayerId() then
                local ped, serverId = GetPlayerPed(player), GetPlayerServerId(player)
                local visual = Player(serverId).state['ob:foodVisual']
                local food = type(visual) == 'table' and type(visual.name) == 'string'
                    and (ORInventoryNeedsConfig.Consumables or {})[visual.name]
                local use = food and food.use
                if use and type(use.prop) == 'table' and type(visual.token) == 'number'
                    and yes(DoesEntityExist(ped)) and not yes(IsEntityDead(ped))
                    and #(GetEntityCoords(ped) - origin) < 75.0 then
                    seen[serverId] = true
                    local entry = remotes[serverId]
                    if not entry or entry.ped ~= ped or entry.token ~= visual.token or entry.name ~= visual.name then
                        if entry then remove(entry) end
                        entry = { ped = ped, token = visual.token, name = visual.name,
                            expires = GetGameTimer() + math.min(30000, tonumber(use.duration) or 5000) + 1500 }
                        remotes[serverId] = entry
                        createRemote(entry, use.prop)
                    elseif GetGameTimer() >= entry.expires and not entry.cancelled then
                        remove(entry) -- state bag antigo nao deixa objeto preso na mao.
                    end
                end
            end
        end
        for serverId, entry in pairs(remotes) do
            if not seen[serverId] then remove(entry); remotes[serverId] = nil end
        end
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'ob_foodprops' then return end
    ORInventoryFoodVisual.Stop()
    for _, entry in pairs(remotes) do remove(entry) end
    remotes = {}
end)
