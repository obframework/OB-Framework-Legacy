local config = {
    selectOnFirstSpawn = true,
}

OR.Callback.register('getLastLocation', function(source)
    return exports.ob_core:GetLastPosition(source), nil
end)

OR.Callback.register('alreadySpawned', function(source)
    if not config.selectOnFirstSpawn then return true end
    if exports.ob_core:HasSpawned(source) then return true end
    return exports.ob_core:HasCharacterSpawnedThisBoot(source)
end)

RegisterNetEvent('ob_spawn:server:markSpawned', function()
    exports.ob_core:MarkSpawned(source)
end)
