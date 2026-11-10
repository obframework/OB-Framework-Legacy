OBVoiceConfig = {
    -- A API disponivel no servidor determina o backend. Nao mudar entre versoes.
    CycleKey = 'HOME',
    RadioKey = 'LMENU',
    DefaultMode = 2,
    Modes = {
        { distance = 1.5, label = 'Sussurrando' },
        { distance = 5.0, label = 'Normal' },
        { distance = 12.0, label = 'Gritando' },
    },
    MaxOverrideDistance = 30.0,
    UpdateInterval = 250,
    -- Legacy: folga da atenuacao do audio nativo. O envio continua limitado
    -- exatamente a Modes.distance; isto nao aumenta o alcance mostrado na HUD.
    LegacyAudioDistanceMultiplier = 3.0,
    RadioVolume = 60,
    CallVolume = 80,
    -- Telefone/radio em instancias diferentes nao se ouvem por padrao.
    IsolateCommunicationBuckets = true,
    -- Compatibilidade com celulares PMA que ingressam em chamadas pelo cliente.
    -- Para chamadas privadas estritas, desative e use setPlayerCall no servidor.
    AllowClientCalls = true,
    AllowClientRadio = true,
    -- [frequencia] = permissao ACE; checks de scripts via addChannelCheck tambem funcionam.
    RestrictedRadio = {},
}
