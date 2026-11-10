OBEarthquakeConfig = {
    Automatic = true,
    SecondsBeforeRestart = 300,
    Permission = 'world.weather',
    DefaultDuration = 300,
    MaxDuration = 300,
    LightWeather = 'RAIN',
    LightRain = 0.25,
    StrongRainStartsAtSeconds = 180,
    Weather = 'THUNDER',
    Rain = 1.0,
    Shake = 'SMALL_EXPLOSION_SHAKE',
    Intensity = 0.45,
    ShakeIntervalMs = 3000,
    ShakeStartsAtSeconds = 60,
    Power = {
        SlowStartsAtSeconds = 180,
        FastStartsAtSeconds = 120,
        OffAtSeconds = 60,
        SlowCycleMs = 8000,
        SlowOffMs = 700,
        -- Aos 2 minutos: apaga por 3s e volta por 2s antes de repetir.
        FastCycleMs = 5000,
        FastOffMs = 3000,
    },
    Audio = {
        -- Adicione a gravacao em sounds/alerta_terremoto.ogg e mude para true.
        Enabled = true,
        File = 'sounds/alerta_terremoto.ogg',
        Volume = 0.8,
        PlayAtMinutes = { 5, 4, 3, 2 },
    },
    NotificationDurationMs = 15000,
}
