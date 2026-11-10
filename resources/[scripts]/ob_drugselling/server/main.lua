local resource = GetCurrentResourceName()
local offers, pedCooldowns, thefts, activeTheftByOwner = {}, {}, {}, {}

local function uid(src) return tonumber(exports.ob_core:GetUserId(src)) end
local function count(src, item) return tonumber(exports.ob_inventory:GetItemCount(src, item)) or 0 end
local function token() return ('D:%s:%s:%s'):format(os.time(), math.random(100000, 999999), math.random(100000, 999999)) end
local function pedFromNet(netId)
    netId = math.floor(tonumber(netId) or 0)
    if netId <= 0 then return 0 end
    local ped = NetworkGetEntityFromNetworkId(netId)
    return ped ~= 0 and DoesEntityExist(ped) and GetEntityType(ped) == 1 and ped or 0
end
local function nearPed(src, ped, distance)
    local playerPed = GetPlayerPed(src)
    return playerPed ~= 0 and ped ~= 0 and GetPlayerRoutingBucket(src) == GetEntityRoutingBucket(ped)
        and #(GetEntityCoords(playerPed) - GetEntityCoords(ped)) <= distance
end
local function playerPedEntity(ped)
    for _, value in ipairs(GetPlayers()) do if GetPlayerPed(tonumber(value)) == ped then return true end end
    return false
end
local function isPolice(src)
    if GetResourceState('ob_org') ~= 'started' then return false end
    local ok, result = pcall(function() return exports.ob_org:HasPermission(src, 'police', true) end)
    return ok and result == true
end
local function policeCount()
    if GetResourceState('ob_dispatch') == 'started' then
        local ok, amount = pcall(function() return exports.ob_dispatch:CountOnDuty('police') end)
        if ok then return tonumber(amount) or 0 end
    end
    local amount = 0
    for _, value in ipairs(GetPlayers()) do if isPolice(tonumber(value)) then amount = amount + 1 end end
    return amount
end
local function dispatch(src, coords)
    if GetResourceState('ob_dispatch') ~= 'started' then
        print('[ob_drugselling] ob_dispatch indisponivel; denuncia nao enviada.')
        return false
    end
    return exports.ob_dispatch:CreateAlert('drug_sale', {
        actorSource = src,
        coords = coords,
        metadata = { origin = resource },
    })
end

OR.Callback.register('offer', function(src, netId)
    if offers[src] then return nil, 'Conclua a abordagem atual.' end
    local owner = uid(src)
    local activeTheft = activeTheftByOwner[owner]
    if activeTheft and thefts[activeTheft] and thefts[activeTheft].expires > os.time() then
        return nil, 'Recupere a mercadoria roubada antes de negociar novamente.'
    end
    activeTheftByOwner[owner] = nil
    local ped = pedFromNet(netId)
    if ped == 0 or not nearPed(src, ped, DrugSelling.interactDistance + 1.5) or playerPedEntity(ped) or GetEntityHealth(ped) <= 0 then return nil, 'Pessoa invalida.' end
    if pedCooldowns[netId] and pedCooldowns[netId] > os.time() then return nil, 'Esta pessoa ja foi abordada recentemente.' end
    local available, variety = {}, 0
    for item, drug in pairs(DrugSelling.drugs) do
        local owned = count(src, item)
        if owned > 0 then available[#available + 1] = { item = item, owned = owned, data = drug }; variety = variety + 1 end
    end
    if #available == 0 then return nil, 'Voce nao possui mercadoria para oferecer.' end
    local selected = available[math.random(#available)]
    local amount = math.min(selected.owned, math.random(1, 3))
    local cops = policeCount()
    local multiplier = 1.0 + math.min(DrugSelling.maximumPoliceBonus, cops * DrugSelling.policeBonusPerOfficer)
        + math.min(DrugSelling.maximumVarietyBonus, math.max(0, variety - 1) * DrugSelling.varietyBonusPerExtraDrug)
    local price = math.floor(math.random(selected.data.minPrice, selected.data.maxPrice) * amount * multiplier)
    local roll, outcome = math.random(1, 100), 'sale'
    if roll <= DrugSelling.refuseChance then outcome = 'refuse'
    elseif roll <= DrugSelling.refuseChance + math.random(DrugSelling.minimumStealChance, DrugSelling.maximumStealChance) then outcome = 'steal' end
    pedCooldowns[netId] = os.time() + DrugSelling.pedCooldownSeconds
    if outcome == 'refuse' then return { refused = true, message = 'A pessoa recusou e encerrou a conversa.' } end
    local id = token()
    offers[src] = { token = id, netId = netId, item = selected.item, label = selected.data.label, amount = amount,
        price = price, outcome = outcome, expires = os.time() + DrugSelling.offerSeconds + 8, owner = uid(src), cops = cops }
    return { token = id, label = selected.data.label, amount = amount, price = price, cops = cops, variety = variety }
end, { rateLimit = { limit = 5, window = 10000 } })

OR.Callback.register('cancelOffer', function(src, supplied)
    if offers[src] and offers[src].token == supplied then offers[src] = nil end
    return true
end, { rateLimit = { limit = 8, window = 10000 } })

OR.Callback.register('accept', function(src, supplied, netId)
    local offer = offers[src]
    if not offer or offer.token ~= supplied or offer.netId ~= tonumber(netId) or os.time() > offer.expires then offers[src] = nil; return false, 'A proposta expirou.' end
    local ped = pedFromNet(netId)
    if ped == 0 or not nearPed(src, ped, DrugSelling.interactDistance + 2.0) or uid(src) ~= offer.owner then offers[src] = nil; return false, 'A pessoa se afastou.' end
    if count(src, offer.item) < offer.amount then offers[src] = nil; return false, 'A mercadoria nao esta mais no inventario.' end
    local removed, removeError = exports.ob_inventory:RemoveItem(src, offer.item, offer.amount)
    if not removed then offers[src] = nil; return false, removeError or 'Nao foi possivel retirar a mercadoria.' end
    offers[src] = nil
    if offer.outcome == 'steal' then
        thefts[offer.token] = { owner = offer.owner, item = offer.item, amount = offer.amount, netId = offer.netId,
            expires = os.time() + DrugSelling.theftRecoverySeconds, claimed = false }
        activeTheftByOwner[offer.owner] = offer.token
        Entity(ped).state:set('ob_drugselling_theft', offer.token, true)
        dispatch(src, GetEntityCoords(ped))
        return true, { stolen = true, recoverySeconds = DrugSelling.theftRecoverySeconds,
            message = 'A pessoa pegou a mercadoria sem pagar e denunciou voce! Voce tem 1 minuto para recuperar.' }
    end
    local added, addError = exports.ob_inventory:AddItem(src, DrugSelling.paymentItem, offer.price)
    if not added then exports.ob_inventory:AddItem(src, offer.item, offer.amount); return false, addError or 'Pagamento recusado; mercadoria devolvida.' end
    if GetResourceState('ob_evidence') == 'started' then
        exports.ob_evidence:MarkDrugContact(src, offer.item, 'drug_sale')
    end
    if math.random(1, 100) <= DrugSelling.normalReportChance then dispatch(src, GetEntityCoords(ped)) end
    return true, { stolen = false, message = ('Venda concluida por $%s.'):format(offer.price) }
end, { rateLimit = { limit = 5, window = 10000 } })

OR.Callback.register('recover', function(src, netId, suppliedToken)
    local theft = thefts[tostring(suppliedToken or '')]
    local ped = pedFromNet(netId)
    if not theft or theft.claimed or theft.netId ~= tonumber(netId) or os.time() > theft.expires then return false, 'A mercadoria nao esta mais aqui.' end
    if theft.owner ~= uid(src) then return false, 'Essa mercadoria nao pertence a voce.' end
    if ped == 0 or GetEntityHealth(ped) > 0 or not nearPed(src, ped, DrugSelling.interactDistance + 1.5) then return false, 'Revista invalida.' end
    local added, addError = exports.ob_inventory:AddItem(src, theft.item, theft.amount)
    if not added then return false, addError or 'Sem espaco para recuperar a mercadoria.' end
    theft.claimed = true; thefts[suppliedToken] = nil
    if activeTheftByOwner[theft.owner] == suppliedToken then activeTheftByOwner[theft.owner] = nil end
    Entity(ped).state:set('ob_drugselling_theft', nil, true)
    return true, ('Voce recuperou %sx %s.'):format(theft.amount, DrugSelling.drugs[theft.item].label)
end, { rateLimit = { limit = 5, window = 10000 } })

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for src, offer in pairs(offers) do if not GetPlayerName(src) or now > offer.expires then offers[src] = nil end end
        for netId, expires in pairs(pedCooldowns) do if now > expires then pedCooldowns[netId] = nil end end
        for id, theft in pairs(thefts) do
            if now > theft.expires then
                local ped = pedFromNet(theft.netId)
                if ped ~= 0 then Entity(ped).state:set('ob_drugselling_theft', nil, true) end
                thefts[id] = nil
                if activeTheftByOwner[theft.owner] == id then activeTheftByOwner[theft.owner] = nil end
            end
        end
    end
end)

AddEventHandler('playerDropped', function() offers[tonumber(source)] = nil end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    for _, theft in pairs(thefts) do
        local ped = pedFromNet(theft.netId)
        if ped ~= 0 then Entity(ped).state:set('ob_drugselling_theft', nil, true) end
    end
end)
