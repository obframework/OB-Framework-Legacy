local busy = false

local function notify(message, notificationType)
    -- Usa o padrao da base; OR.Notify ja tem fallback se ob_notification sair.
    OR.Notify(message, notificationType or 'info')
end

RegisterNetEvent('ob_core:client:tuningNotice', function(message)
    if source ~= 65535 then return end
    notify(message)
end)

local function maxMod(vehicle, index)
    local count = GetNumVehicleMods(vehicle, index)
    if count > 0 then
        SetVehicleMod(vehicle, index, count - 1, GetVehicleModVariation(vehicle, index))
    end
end

-- Escolhe outra opcao valida sem reiniciar a semente a cada comando/modelo.
-- Inclui a peca original (-1), para variar ate slots com apenas um acessorio.
local function randomDifferent(current, minimum, maximum)
    if maximum <= minimum then return minimum end
    if current < minimum or current > maximum then return math.random(minimum, maximum) end
    local choice = math.random(minimum, maximum - 1)
    return choice >= current and choice + 1 or choice
end

local function randomVisualMod(vehicle, index)
    local count = GetNumVehicleMods(vehicle, index)
    if count > 0 then
        SetVehicleMod(vehicle, index, randomDifferent(GetVehicleMod(vehicle, index), -1, count - 1),
            GetVehicleModVariation(vehicle, index))
    end
end

RegisterNetEvent('ob_core:client:applyTuning', function(netId, visual)
    if source ~= 65535 or busy then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped
        or NetworkGetNetworkIdFromEntity(vehicle) ~= netId then return end

    busy = true
    local ok, err = pcall(function()
        local deadline = GetGameTimer() + 1500
        while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
            NetworkRequestControlOfEntity(vehicle)
            Wait(0)
        end
        if not DoesEntityExist(vehicle) or GetVehiclePedIsIn(ped, false) ~= vehicle
            or GetPedInVehicleSeat(vehicle, -1) ~= ped or not NetworkHasControlOfEntity(vehicle) then
            notify('Nao foi possivel obter controle do veiculo. Tente novamente.', 'error')
            return
        end

        SetVehicleModKit(vehicle, 0)
        -- Motor, freios, transmissao e blindagem. Suspensao muda a altura,
        -- por isso fica apenas no tuning2. Turbo e toggle, nao mod numerico.
        for _, index in ipairs({ 11, 12, 13, 16 }) do maxMod(vehicle, index) end

        if visual == true then
            -- Desempenho continua no maximo; somente os slots visuais variam.
            -- 17..22 sao toggles e nao devem receber SetVehicleMod.
            -- Referencia: github.com/citizenfx/natives/blob/master/VEHICLE/SetVehicleMod.md
            for index = 0, 49 do
                if (index < 11 or index == 14 or index > 22) then randomVisualMod(vehicle, index) end
            end
            maxMod(vehicle, 15) -- suspensao maxima apenas no tuning2
            ToggleVehicleMod(vehicle, 20, true)
            ToggleVehicleMod(vehicle, 22, true)
            local liveries = GetVehicleLiveryCount(vehicle)
            if GetNumVehicleMods(vehicle, 48) == 0 and liveries > 0 then
                SetVehicleLivery(vehicle, randomDifferent(GetVehicleLivery(vehicle), 0, liveries - 1))
            end
            -- Preserva pintura, placa, familia das rodas e extras: extras
            -- podem ser mutuamente exclusivos (como conjuntos de sirenes).
        end

        -- Reaplica apos as pecas para builds que resetam o toggle do turbo.
        for _ = 1, 6 do
            if not DoesEntityExist(vehicle) then return end
            ToggleVehicleMod(vehicle, 18, true)
            Wait(0)
        end
        notify(visual == true and 'Desempenho maximo aplicado com pecas visuais aleatorias.'
            or 'Desempenho maximo aplicado. Visual e suspensao preservados.', 'success')
    end)
    busy = false
    if not ok then
        print(('[ob_core] Falha ao aplicar tuning: %s'):format(tostring(err)))
        notify('Nao foi possivel concluir o tuning.', 'error')
    end
end)
