OBWeatherConfig = {
    defaultWeather = 'EXTRASUNNY', -- sol, sem chuva
    defaultHour = 12,
    defaultMinute = 0,
    -- false: /time define o ponto inicial e o relogio continua correndo.
    -- true: mantem exatamente a hora definida.
    freezeClock = false,
    -- Ritmo padrao do GTA/FiveM: 1 minuto do jogo a cada 2 segundos reais.
    secondsPerGameMinute = 2.0,
    -- So reposiciona o relogio se a diferenca ultrapassar este limite. Abaixo
    -- disso, o GTA continua a interpolacao natural do sol sem pequenos saltos.
    clockCorrectionThresholdSeconds = 5,
    -- Reafirma o clima e corrige somente desvios relevantes entre clientes.
    resyncIntervalSeconds = 30,
    -- Se o recurso parar/reiniciar, conserva a ultima hora na tela em vez de
    -- liberar o ciclo acelerado nativo do GTA.
    freezeOnResourceStop = true,
    transitionSeconds = 15.0,
}
