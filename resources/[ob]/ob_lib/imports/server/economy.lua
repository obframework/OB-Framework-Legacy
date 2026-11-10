OR.Economy = OR.Economy or {}

local function unavailable(reason)
    return {
        handled = false,
        fallback = true,
        success = false,
        reason = reason or 'unavailable',
    }
end

local function call(exportName, ...)
    if GetResourceState('ob_economy') ~= 'started' then
        return unavailable('resource_stopped')
    end

    local args = table.pack(...)
    local ok, result = pcall(function()
        if exportName == 'ChargePlayer' then
            return exports.ob_economy:ChargePlayer(table.unpack(args, 1, args.n))
        elseif exportName == 'RefundCharge' then
            return exports.ob_economy:RefundCharge(table.unpack(args, 1, args.n))
        elseif exportName == 'PayPlayer' then
            return exports.ob_economy:PayPlayer(table.unpack(args, 1, args.n))
        elseif exportName == 'ChargeAccount' then
            return exports.ob_economy:ChargeAccount(table.unpack(args, 1, args.n))
        elseif exportName == 'RefundAccountCharge' then
            return exports.ob_economy:RefundAccountCharge(table.unpack(args, 1, args.n))
        elseif exportName == 'GetStatus' then
            return exports.ob_economy:GetStatus()
        end
    end)

    if not ok or type(result) ~= 'table' then
        if not ok then
            print(('[%s] Integracao opcional ob_economy falhou: %s'):format(
                GetCurrentResourceName(), tostring(result)))
        end
        return unavailable(ok and 'invalid_response' or 'export_error')
    end
    return result
end

function OR.Economy.ChargePlayer(source, amount, category, description, metadata, accountKey)
    return call('ChargePlayer', source, amount, category, description, metadata, accountKey)
end

function OR.Economy.RefundCharge(source, receipt, description)
    return call('RefundCharge', source, receipt, description)
end

function OR.Economy.PayPlayer(source, amount, category, description, metadata, accountKey)
    return call('PayPlayer', source, amount, category, description, metadata, accountKey)
end

function OR.Economy.ChargeAccount(source, accountKey, amount, category, description, metadata)
    return call('ChargeAccount', source, accountKey, amount, category, description, metadata)
end

function OR.Economy.RefundAccountCharge(source, receipt, description)
    return call('RefundAccountCharge', source, receipt, description)
end

function OR.Economy.GetStatus()
    return call('GetStatus')
end
