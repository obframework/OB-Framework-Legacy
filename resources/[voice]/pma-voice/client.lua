-- Somente encaminhamento: sem threads, captura de audio, UI ou controle Mumble.
-- Nome real preservado para celulares que usam GetResourceState('pma-voice').
for _, name in ipairs({
    'setCallChannel', 'SetCallChannel', 'addPlayerToCall', 'removePlayerFromCall',
    'setRadioChannel', 'SetRadioChannel', 'addPlayerToRadio', 'removePlayerFromRadio',
    'setRadioVolume', 'getRadioVolume', 'setCallVolume', 'getCallVolume',
    'registerCustomSubmix', 'setEffectSubmix',
    'setVoiceProperty', 'SetMumbleProperty', 'SetTokoProperty',
    'setAllowProximityCycleState', 'overrideProximityRange', 'clearProximityOverride',
    'overrideProximityCheck', 'resetProximityCheck', 'setListenerOverride',
    'toggleMutePlayer', 'isPlayerMuted', 'getMutedPlayers',
    'setDisableRadioAnim', 'toggleRadioAnim', 'getRadioAnimState',
    'addRadioDisableBit', 'removeRadioDisableBit', 'GetStatus', 'GetCapabilities',
}) do
    exports(name, function(...)
        local target = exports['ob_voice']
        return target[name](target, ...)
    end)
end
