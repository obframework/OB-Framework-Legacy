-- Este arquivo e carregado apenas no servidor. Nunca coloque a chave no config.lua compartilhado.
OBPhoneServerConfig = {
    fivemanageApiKey = GetConvar('ob_phone_fivemanage_key', ''),
    uploadServer = 'https://api.fivemanage.com/api/v3/file',
    uploadTimeoutMs = 25000,
    maxVideoSeconds = 30,
}
