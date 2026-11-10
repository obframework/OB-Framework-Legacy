-- Restrito ao ID do interior; nao remove pedestres das ruas ao redor.
local blocked = {}
local function nativeTrue(value) return value == true or value == 1 end

local function refreshInteriors()
    blocked = {}
    if not IplConfig.DisableInteriorAmbientPeds then return end
    for _, location in pairs(IplConfig.SurfaceInteriors) do
        local p = location.interiorPoint
        if location.enabled and p then
            local interior = GetInteriorAtCoords(p.x, p.y, p.z)
            if interior and interior ~= 0 then blocked[interior] = true end
        end
    end
end

AddEventHandler('populationPedCreating', function(x, y, z)
    if IplConfig.DisableInteriorAmbientPeds and blocked[GetInteriorAtCoords(x, y, z)] then
        CancelEvent()
    end
end)

CreateThread(function()
    while true do
        refreshInteriors()
        if next(blocked) then
            for _, ped in ipairs(GetGamePool('CPed')) do
                -- Tipos 1-5: populacao aleatoria. Mission/permanent/player ficam intactos.
                local population = GetEntityPopulationType(ped)
                if population >= 1 and population <= 5
                    and nativeTrue(DoesEntityExist(ped))
                    and not nativeTrue(IsPedAPlayer(ped))
                    and not nativeTrue(IsEntityAMissionEntity(ped))
                    and blocked[GetInteriorFromEntity(ped)] then
                    if not nativeTrue(NetworkGetEntityIsNetworked(ped)) or nativeTrue(NetworkHasControlOfEntity(ped)) then
                        SetEntityAsMissionEntity(ped, true, true)
                        DeletePed(ped)
                    end
                end
            end
        end
        Wait(2000)
    end
end)
