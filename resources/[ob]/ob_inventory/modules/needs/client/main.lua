-- O modulo needs publica os valores pelo state bag `or:needs` no servidor.
-- A HUD e outros modulos clientes leem esse state bag sem acoplamento extra.
ORInventoryNeedsClient = ORInventoryNeedsClient or {}

-- Diagnostico local: compara um objeto nativo com o modelo personalizado,
-- fora da mao/animacao. Nao consome itens e nao cria entidades de rede.
local previewObjects, previewGeneration = {}, 0
local function nativeTrue(value) return value == true or value == 1 end
local function clearPreview()
    previewGeneration = previewGeneration + 1
    for _, object in ipairs(previewObjects) do
        if nativeTrue(DoesEntityExist(object.entity)) and GetEntityModel(object.entity) == object.model then
            DeleteEntity(object.entity)
        end
    end
    previewObjects = {}
end

RegisterCommand('testepropcomida', function()
    clearPreview()
    local generation = previewGeneration
    local food = ORInventoryNeedsConfig.Consumables.coxinha_molho
    local custom = food and food.use and food.use.prop and food.use.prop.model
    if not custom then return print('[needs] Coxinha sem prop no cadastro.') end
    CreateThread(function()
        local ped = PlayerPedId()
        for index, name in ipairs({ 'prop_cs_burger_01', custom }) do
            local model = type(name) == 'number' and name or joaat(name)
            if nativeTrue(IsModelInCdimage(model)) and nativeTrue(IsModelValid(model)) then
                RequestModel(model)
                local timeout = GetGameTimer() + 5000
                while generation == previewGeneration and not nativeTrue(HasModelLoaded(model))
                    and GetGameTimer() < timeout do Wait(0) end
                if generation ~= previewGeneration then SetModelAsNoLongerNeeded(model) return end
                if nativeTrue(HasModelLoaded(model)) then
                    local coords = GetOffsetFromEntityInWorldCoords(ped, index == 1 and -0.35 or 0.35, 1.2, 0.25)
                    local entity = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
                    if entity ~= 0 and nativeTrue(DoesEntityExist(entity)) then
                        SetEntityAsMissionEntity(entity, true, true)
                        SetEntityCollision(entity, false, false)
                        FreezeEntityPosition(entity, true)
                        SetEntityVisible(entity, true, false)
                        ResetEntityAlpha(entity)
                        previewObjects[#previewObjects + 1] = { entity = entity, model = model }
                        local lo, hi = GetModelDimensions(model)
                        print(('[needs] %s: entidade=%s visivel=%s tamanho=%.3f/%.3f/%.3f m'):format(
                            name, entity, tostring(IsEntityVisible(entity)), hi.x-lo.x, hi.y-lo.y, hi.z-lo.z))
                    else
                        print('[needs] Falha ao criar: ' .. tostring(name))
                    end
                else
                    print('[needs] Timeout ao carregar: ' .. tostring(name))
                end
                SetModelAsNoLongerNeeded(model)
            else
                print('[needs] Modelo indisponivel: ' .. tostring(name))
            end
        end
        print('[needs] Teste por 30 segundos: hamburguer a esquerda, coxinha a direita, suspensos a sua frente. /testepropcomida recria.')
        Wait(30000)
        if generation == previewGeneration then clearPreview() end
    end)
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'ob_foodprops' then clearPreview() end
end)
