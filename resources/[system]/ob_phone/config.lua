OBPhoneConfig = {
    RingSeconds = 30,
    SpeakerDistance = 3.0,
    CallBatteryInterval = 60, -- segundos; consome mesmo com a tela fechada
    Charging = {
        Step = 10, -- porcentagem adicionada em cada etapa
        IntervalSeconds = 10,
    },
    ShareDistance = 3.0,
    ShareRequestSeconds = 20,
    Security = {
        PinMinimum = 4,
        PinMaximum = 6,
        AttemptsBeforeLock = 3,
        LockSeconds = 60,
    },
    Signal = {
        -- Ative depois de preencher os quatro cantos da area, em ordem.
        Enabled = false,
        Area = {
            { x = 0.0, y = 0.0 },
            { x = 0.0, y = 0.0 },
            { x = 0.0, y = 0.0 },
            { x = 0.0, y = 0.0 },
        },
        EdgeFadeDistance = 500.0,
        TowerRadius = 200.0,
        JammerRadius = 2000.0,
        DeviceDurationSeconds = 30 * 60,
    },
    VehicleTrackingCooldownSeconds = 30,
    VehicleTrackingDurationSeconds = 30,
    VideoIceServers = {
        { urls = 'stun:stun.cloudflare.com:3478' },
        { urls = 'stun:stun.l.google.com:19302' },
    },
    DefaultCase = 'blue',
    DefaultWallpaper = 'ocean',
    GarageImages = {
        BaseUrl = '/orbis/cars/',
        Fallback = 'carro.png',
    },
    -- 'default' instala e mostra, 'store' deixa disponivel na OB Store e
    -- 'disabled' remove. IDs de aplicativos externos tambem podem ser usados.
    Apps = {
        call = 'default', messages = 'default', contacts = 'default',
        bank = 'default', garage = 'default', camera = 'default',
        photos = 'default', obgram = 'default', calc = 'default',
        notes = 'default', store = 'default', settings = 'default',
        darkchat = 'store',
    },
    DarkChat = {
        -- A verificacao independe de estar ou nao em servico.
        BlockedJobs = { 'police' },
    },
}
