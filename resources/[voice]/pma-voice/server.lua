for _, name in ipairs({ 'setPlayerCall', 'setPlayerRadio', 'getPlayersInRadioChannel',
    'GetPlayersInRadioChannel', 'isValidPlayer', 'GetBackend' }) do
    exports(name, function(...)
        local target = exports['ob_voice']
        return target[name](target, ...)
    end)
end
-- Preserva o dono real dos callbacks para invalidar permissoes quando ele para.
exports('addChannelCheck', function(channel, callback)
    return exports.ob_voice:addChannelCheck(channel, callback, GetInvokingResource())
end)
exports('overrideRadioNameGetter', function(callback)
    return exports.ob_voice:overrideRadioNameGetter(callback, GetInvokingResource())
end)
