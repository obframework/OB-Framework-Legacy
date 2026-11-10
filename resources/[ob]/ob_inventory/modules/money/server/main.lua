ORInventoryMoney = ORInventoryMoney or {}

local function accountDefinition(account)
    account = type(account) == 'string' and account:lower() or ''
    return ORInventoryMoneyConfig.Accounts[account], account
end

local function amount(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

function ORInventoryMoney.Get(playerSource, account)
    local definition, accountName = accountDefinition(account)
    if not definition then return nil, 'Tipo de dinheiro invalido.' end
    return ORInventory.GetItemCount(playerSource, accountName)
end

function ORInventoryMoney.Add(playerSource, account, value)
    local definition, accountName = accountDefinition(account)
    value = amount(value)
    if not definition or value < 1 then return false, 'Tipo de dinheiro ou quantidade invalida.' end
    return ORInventory.AddItem(playerSource, accountName, value)
end

function ORInventoryMoney.Remove(playerSource, account, value)
    local definition, accountName = accountDefinition(account)
    value = amount(value)
    if not definition or value < 1 then return false, 'Tipo de dinheiro ou quantidade invalida.' end
    return ORInventory.RemoveItem(playerSource, accountName, value)
end

exports('GetMoney', ORInventoryMoney.Get)
exports('AddMoney', ORInventoryMoney.Add)
exports('RemoveMoney', ORInventoryMoney.Remove)

-- Limpa somente o formato de conta virtual introduzido durante o bootstrap.
-- A partir daqui dinheiro existe exclusivamente como item na mochila.
AddEventHandler('ob_core:server:playerLoaded', function(playerSource, character)
    local metadata = type(character) == 'table' and character.metadata or nil
    if type(metadata) == 'table' and type(metadata.money) == 'table' then
        exports.ob_core:SetMetadata(playerSource, 'money', nil)
    end
end)
