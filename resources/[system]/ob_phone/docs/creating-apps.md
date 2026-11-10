# Criando aplicativos para o OB Phone

A forma recomendada é criar um resource separado. O OB Phone abre a interface
do aplicativo em um `iframe`, instala ou remove pela OB Store e troca eventos
com o resource proprietário.

Existe um modelo funcional em `examples/ob_phone_app_example`.
Copie essa pasta para a pasta de resources do servidor, fora de `ob_phone`,
troque o identificador e adicione `ensure ob_phone_app_example` ao
`server.cfg`. A pasta dentro de `examples` serve apenas como modelo e não é
iniciada automaticamente.

## Manifesto do aplicativo

O resource precisa disponibilizar os arquivos da interface e depender do
`ob_phone`:

```lua
fx_version 'cerulean'
game 'gta5'
dependency 'ob_phone'

client_script 'client.lua'

files {
    'web/index.html',
    'web/app.js',
    'web/style.css',
    'web/icon.svg'
}
```

## Registro no telefone

```lua
local definition = {
    id = 'cidade.exemplo',
    name = 'Exemplo',
    description = 'Meu primeiro aplicativo.',
    developer = 'Cidade OB',
    version = '1.0.0',
    category = 'utilidades',
    icon = 'web/icon.svg',
    entry = 'web/index.html',
    defaultInstalled = false,
    removable = true
}

local function registerApp()
    exports.ob_phone:AddApp(definition)
end

AddEventHandler('ob_phone:client:appsReady', registerApp)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ob_phone' then registerApp() end
end)
```

O `id` deve ser único e conter somente letras minúsculas, números, ponto,
hífen ou sublinhado.

## Comunicação

Da interface para o client Lua:

```js
window.parent.postMessage({
  type: "ob-phone:event",
  event: "confirmar",
  payload: { value: 10 },
}, "*");
```

No client Lua:

```lua
AddEventHandler('ob_phone:client:appEvent', function(owner, appId, event, payload)
    if owner ~= GetCurrentResourceName() or appId ~= definition.id then return end
    if event == 'confirmar' then
        print(('Valor recebido: %s'):format(tostring(payload and payload.value)))
    end
end)
```

Do client Lua para a interface:

```lua
exports.ob_phone:SendAppMessage(definition.id, {
    status = 'atualizado'
})
```

```js
window.addEventListener("message", (event) => {
  if (event.data?.type !== "ob-phone:message") return;
  console.log(event.data.payload);
});
```

O telefone também envia `ob-phone:ready` quando o `iframe` termina de abrir,
incluindo o identificador do aplicativo e o tema atual.
