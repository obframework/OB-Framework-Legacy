OBChatConfig = {
    OpenKey = 'T',
    MaxCommandLength = 300,
    MaxDepartmentMessageLength = 220,
    MessageLifetimeMs = 12000,
    MaximumMessages = 40,

    DepartmentCommand = 'pd',
    DepartmentLabel = 'SERVICOS PUBLICOS',
    DepartmentColour = { 43, 184, 255 },
    DepartmentKeys = {
        police = true,
        ambulance = true,
        fire = true,
        firefighter = true,
        mechanic = true,
    },

    -- Esta lista e o unico catalogo exibido no autocomplete. Comandos de
    -- staff e comandos tecnicos nao devem ser adicionados aqui.
    Suggestions = {
        { command = 'me', arguments = '[acao]', description = 'Descreve uma acao do personagem.' },
        { command = 'id', description = 'Mostra nome e ID das pessoas em ate 2 metros.' },
        { command = 'emotes', description = 'Abre o menu de animacoes.' },
        { command = 'voz', arguments = '[volume]', description = 'Ajusta o volume da voz.' },
        { command = 'chave', description = 'Gerencia a chave do veiculo.' },
        { command = 'licenca', description = 'Abre o Centro de Licencas quando estiver proximo.' },
        { command = 'empregos', description = 'Abre a Central de Empregos quando estiver proximo.' },
        { command = 'garagem', description = 'Consulta a garagem disponivel.' },
        { command = 'phone', description = 'Abre ou fecha o celular.' },
        { command = 'hud', description = 'Abre as configuracoes da interface.' },
        { command = 'economia', description = 'Consulta informacoes da economia.' },
        { command = 'painel', description = 'Abre o painel da organizacao legal.', organisationType = 'legal' },
        { command = 'tablet', description = 'Abre o tablet da organizacao ilegal.', organisationType = 'illegal' },
        { command = 'mdt', description = 'Abre o terminal policial.', organisationKeys = { police = true }, requireDuty = true },
        { command = 'patrulha', description = 'Abre o sistema de patrulha.', organisationKeys = { police = true }, requireDuty = true },
        { command = 'pd', arguments = '[mensagem]', description = 'Chat interno dos servicos publicos.', department = true, requireDuty = true },
    },
}
