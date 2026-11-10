OR.Callback.register('getMenu', function(source)
    if not exports.ob_admin:HasPermission(source, 'panel.open') then
        return nil, 'Sem permissao para abrir a administracao.'
    end

    return {
        modules = {
            { id = 'register_editor', label = 'Registradoras / roubos', description = 'Cadastre registradoras, premios, policiais e tempos de recuperacao.', icon = 'garage', enabled = GetResourceState('ob_registerrobbery') == 'started' and exports.ob_admin:HasPermission(source, 'world.shops') },
            { id = 'inventory_shop_editor', label = 'Lojas do inventario', description = 'Atendentes, produtos, precos, permissoes e blips.', icon = 'garage', enabled = GetResourceState('ob_inventory') == 'started' and exports.ob_admin:HasPermission(source, 'world.shops') },
            { id = 'moneywash_editor', label = 'Lavagens de dinheiro', description = 'Cadastre atendentes, maquinas, taxas, limites e duracao.', icon = 'garage', enabled = GetResourceState('ob_moneywash') == 'started' and exports.ob_admin:HasPermission(source, 'world.shops') },
            { id = 'doorlock_editor', label = 'Portas e trancas', description = 'Crie grupos de acesso e capture portas simples ou duplas.', icon = 'shield', enabled = GetResourceState('ob_doorlock') == 'started' and exports.ob_admin:HasPermission(source, 'world.doors') },
            { id = 'appearance_store_editor', label = 'Roupas, cabelo e tatuagens', description = 'Locais, tipos de atendimento, categorias, precos e camera.', icon = 'map', enabled = GetResourceState('ob_stores') == 'started' and exports.ob_admin:HasPermission(source, 'world.stores') },
            { id = 'panel', label = 'Painel administrativo', description = 'Jogadores, cargos, veiculos e ferramentas.', icon = 'shield', enabled = true },
            { id = 'offline_players', label = 'Jogadores offline', description = 'Contas, personagens, inventarios, cargos, bans e operacoes protegidas.', icon = 'users', enabled = exports.ob_admin:HasPermission(source, 'offline.players.view') },
            { id = 'org_admin', label = 'Organizacoes e servicos', description = 'Abra o painel administrativo do ob_org sem precisar lembrar do comando.', icon = 'users', enabled = GetResourceState('ob_org') == 'started' },
            { id = 'editor', label = 'Editor do mundo', description = 'Blips, pontos, lojas, empregos e outros editores.', icon = 'map', enabled = GetResourceState('ob_editor') == 'started' },
            { id = 'heist_editor', label = 'Roubos, props e animacoes', description = 'Posicione pontos do Pacific/Fleeca, capture props e teste animacoes.', icon = 'map', enabled = GetResourceState('ob_editor') == 'started' and exports.ob_admin:HasPermission(source, 'world.shops') },
            { id = 'carshop', label = 'Concessionarias', description = 'Crie lojas, pontos de entrega, catalogos e estoques.', icon = 'car', enabled = GetResourceState('ob_carshop') == 'started' },
            { id = 'feedback', label = 'Feedback dos testes', description = 'Leia relatos e capturas enviadas pelos jogadores.', icon = 'bug', enabled = GetResourceState('ob_feedback') == 'started' },
            { id = 'wallmap', label = 'Jogadores no mapa', description = 'Ativa ou desativa os blips administrativos.', icon = 'users', enabled = exports.ob_admin:HasPermission(source, 'tools.wallmap') },
            { id = 'entity_laser', label = 'Mira de entidades', description = 'Identifique props, veiculos e peds, com modelo, hash e coordenadas.', icon = 'crosshair', enabled = exports.ob_admin:HasPermission(source, 'tools.wall') },
            { id = 'garage_admin', label = 'Garagens dos personagens', description = 'Consulte os veiculos e entregue carros usando o ID fixo.', icon = 'garage', enabled = GetResourceState('ob_garage') == 'started' and exports.ob_admin:HasPermission(source, 'players.view') },
            { id = 'garage_editor', label = 'Editor de garagens', description = 'Crie pontos, vagas, permissoes, blips e catalogos sem reiniciar.', icon = 'garage', enabled = GetResourceState('ob_garage') == 'started' and exports.ob_admin:HasPermission(source, 'world.garages') },
            { id = 'blackout_admin', label = 'Energia da cidade', description = 'Consulte o apagao, desligue, ligue ou retorne ao horario automatico.', icon = 'power', enabled = GetResourceState('ob_blackout') == 'started' and exports.ob_admin:HasPermission(source, 'world.time') },
        }
    }
end)

RegisterNetEvent('ob_adminmenu:server:openOrg', function()
    local playerSource = source
    if not exports.ob_admin:HasPermission(playerSource, 'panel.open') then
        TriggerClientEvent('ob_notification:client:notify', playerSource,
            'Sem permissao para abrir o painel de organizacoes.', 'error')
        return
    end
    if GetResourceState('ob_org') ~= 'started' then
        TriggerClientEvent('ob_notification:client:notify', playerSource,
            'O sistema de organizacoes esta indisponivel.', 'error')
        return
    end
    TriggerClientEvent('ob_org:client:openPanel', playerSource, 'admin')
end)

local function cleanText(value, maximum)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maximum and #value > maximum then value = value:sub(1, maximum) end
    return value
end

local function validUserId(value)
    value = tonumber(value)
    if not value or value < 1 or value ~= math.floor(value) then return nil end
    return value
end

local function hasPermission(playerSource, permission)
    return exports.ob_admin:HasPermission(playerSource, permission) == true
end

local function characterName(row)
    local name = cleanText(('%s %s'):format(row.firstname or '', row.lastname or ''), 80)
    return name ~= '' and name or ('Personagem #%s'):format(row.user_id)
end

local function generatePlate()
    for _ = 1, 30 do
        local plate = ('OB%02d%03d'):format(math.random(10, 99), math.random(0, 999))
        local exists = OR.Database.scalar.await('SELECT id FROM ob_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end
end

OR.Callback.register('authorizeTool', function(source, tool)
    if tool ~= 'entity_laser' or not hasPermission(source, 'tools.wall') then
        return nil, 'Sem permissao para usar esta ferramenta.'
    end
    return true
end)

OR.Callback.register('garageVehicles', function(source, rawUserId)
    if not hasPermission(source, 'players.view') then
        return nil, 'Sem permissao para consultar garagens.'
    end
    if not OR.Security.rateLimit(source, 'adminmenu:garage:list', 8, 10000) then
        return nil, 'Aguarde um instante antes de consultar novamente.'
    end

    local userId = validUserId(rawUserId)
    if not userId then return nil, 'Informe um ID fixo valido.' end

    local character = OR.Database.single.await([[SELECT user_id, firstname, lastname
        FROM ob_characters WHERE user_id = ? AND deleted_at IS NULL LIMIT 1]], { userId })
    if not character then return nil, 'Personagem nao encontrado.' end

    local vehicles = OR.Database.query.await([[SELECT id, plate, model, label, garage, stored,
        fuel, body, engine FROM ob_vehicles WHERE owner_user_id = ? AND vehicle_type <> 'free' ORDER BY garage, label, id]], { userId }) or {}

    for index = 1, #vehicles do
        local vehicle = vehicles[index]
        vehicle.id = tonumber(vehicle.id)
        vehicle.stored = tonumber(vehicle.stored) == 1
        vehicle.fuel = tonumber(vehicle.fuel) or 0
        vehicle.body = tonumber(vehicle.body) or 0
        vehicle.engine = tonumber(vehicle.engine) or 0
    end

    return {
        character = { userId = userId, name = characterName(character) },
        vehicles = vehicles,
        canGive = hasPermission(source, 'vehicle.spawn'),
        canRemove = hasPermission(source, 'vehicle.delete'),
    }
end)

OR.Callback.register('garageRemoveVehicle', function(source, payload)
    if not hasPermission(source, 'vehicle.delete') then
        return nil, 'Sem permissao para remover veiculos.'
    end
    if not OR.Security.rateLimit(source, 'adminmenu:garage:remove', 3, 10000) then
        return nil, 'Aguarde um instante antes de remover outro veiculo.'
    end

    payload = type(payload) == 'table' and payload or {}
    local userId = validUserId(payload.userId)
    local vehicleId = validUserId(payload.vehicleId)
    if not userId or not vehicleId then return nil, 'Personagem ou veiculo invalido.' end

    local row = OR.Database.single.await([[SELECT id, plate, model, label, stored
        FROM ob_vehicles WHERE id = ? AND owner_user_id = ? AND vehicle_type <> 'free' LIMIT 1]], { vehicleId, userId })
    if not row then return nil, 'Esse veiculo nao pertence ao personagem consultado.' end
    if tonumber(row.stored) ~= 1 then
        return nil, 'Guarde o veiculo antes de remove-lo da garagem.'
    end

    local statements = {
        { kind = 'update', statement = 'DELETE FROM ob_vehicle_tax_payments WHERE vehicle_id = ? AND owner_user_id = ?', parameters = { vehicleId, userId } },
    }
    local hasMaintenance = OR.Database.scalar.await([[SELECT 1 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'ob_vehicle_maintenance' LIMIT 1]])
    if hasMaintenance then
        statements[#statements + 1] = { kind = 'update', statement = 'DELETE FROM ob_vehicle_maintenance WHERE plate = ?', parameters = { row.plate } }
    end
    statements[#statements + 1] = {
        kind = 'update', statement = "DELETE FROM ob_vehicles WHERE id = ? AND owner_user_id = ? AND stored = 1 AND vehicle_type <> 'free'",
        parameters = { vehicleId, userId }, expectAffectedMin = 1,
    }
    local results, transactionError = OR.Database.transaction.await(statements)
    if not results then return nil, transactionError or 'Nao foi possivel remover o veiculo.' end

    local actorUserId = tonumber(exports.ob_core:GetUserId(source))
    print(('[ob_adminmenu] ID fixo %s removeu %s (%s, registro %s) da garagem do ID fixo %s.'):format(
        actorUserId or 'console', tostring(row.model), tostring(row.plate), vehicleId, userId
    ))

    local target = exports.ob_core:GetPlayerByUserId(userId)
    local targetSource = type(target) == 'table' and tonumber(target.source or target.playerSource)
    if targetSource and GetPlayerName(targetSource) then
        TriggerClientEvent('ob_notification:client:notify', targetSource,
            ('O veiculo %s (%s) foi removido da sua garagem pela administracao.'):format(row.label or row.model, row.plate), 'info')
    end
    return true, ('Veiculo %s removido da garagem.'):format(row.plate)
end)

OR.Callback.register('garageGiveVehicle', function(source, payload)
    if not hasPermission(source, 'vehicle.spawn') then
        return nil, 'Sem permissao para entregar veiculos.'
    end
    if not OR.Security.rateLimit(source, 'adminmenu:garage:give', 3, 10000) then
        return nil, 'Aguarde um instante antes de entregar outro veiculo.'
    end
    if GetResourceState('ob_garage') ~= 'started' then
        return nil, 'O sistema de garagem esta indisponivel.'
    end

    payload = type(payload) == 'table' and payload or {}
    local userId = validUserId(payload.userId)
    local model = cleanText(payload.model, 64):lower()
    local label = cleanText(payload.label, 96)
    local garage = cleanText(payload.garage, 48):lower()
    local plate = cleanText(payload.plate, 8):upper():gsub('%s+', '')

    if not userId then return nil, 'Informe um ID fixo valido.' end
    if model == '' or not model:match('^[%w_%-]+$') then return nil, 'Informe um modelo de veiculo valido.' end
    if garage == '' then garage = 'central' end
    if not garage:match('^[%w_%-]+$') then return nil, 'Informe uma garagem valida.' end
    if label == '' then label = model:upper() end

    local character = OR.Database.single.await([[SELECT user_id, firstname, lastname
        FROM ob_characters WHERE user_id = ? AND deleted_at IS NULL LIMIT 1]], { userId })
    if not character then return nil, 'Personagem nao encontrado.' end

    if plate ~= '' then
        if not plate:match('^[A-Z0-9]+$') then return nil, 'A placa deve conter apenas letras e numeros.' end
        if OR.Database.scalar.await('SELECT id FROM ob_vehicles WHERE plate = ? LIMIT 1', { plate }) then
            return nil, 'Essa placa ja esta em uso.'
        end
    else
        plate = generatePlate()
        if not plate then return nil, 'Nao foi possivel gerar uma placa livre.' end
    end

    local vehicleId, errorMessage = exports.ob_garage:RegisterVehicleForUser(userId, {
        plate = plate,
        model = model,
        label = label,
        garage = garage,
        fuel = 100,
        properties = {},
    })
    if not vehicleId then return nil, errorMessage or 'Nao foi possivel registrar o veiculo.' end

    local actorUserId = tonumber(exports.ob_core:GetUserId(source))
    print(('[ob_adminmenu] ID fixo %s entregou %s (%s) ao ID fixo %s na garagem %s.'):format(
        actorUserId or 'console', model, plate, userId, garage
    ))

    local target = exports.ob_core:GetPlayerByUserId(userId)
    local targetSource = type(target) == 'table' and tonumber(target.source or target.playerSource)
    if targetSource and GetPlayerName(targetSource) then
        TriggerClientEvent('ob_notification:client:notify', targetSource,
            ('O veiculo %s (%s) foi adicionado a sua garagem.'):format(label, plate), 'success')
    end

    return {
        id = tonumber(vehicleId), plate = plate, model = model, label = label,
        garage = garage, stored = true, fuel = 100, body = 1000, engine = 1000,
    }, ('Veiculo entregue para %s.'):format(characterName(character))
end)
