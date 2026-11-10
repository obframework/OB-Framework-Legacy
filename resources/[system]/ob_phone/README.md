# OB Phone 3

## Imagens dos veiculos

Edite `GarageImages` em `config.lua`. `BaseUrl` deve apontar para a pasta publica que contem uma imagem PNG com o mesmo nome de spawn do veiculo. Quando a imagem nao existir, o celular usa o arquivo configurado em `Fallback` (por padrao, `carro.png`).

## Camera e FiveManage

Edite somente `server_config.lua` e preencha `fivemanageApiKey`. O endereco padrao de `uploadServer` ja aponta para a API v3 do FiveManage. Esse arquivo e carregado apenas no servidor; nao transfira a chave para `config.lua`, JavaScript ou qualquer arquivo da NUI.

Fotos, videos e audios sao enviados diretamente da NUI para a URL temporaria autorizada pelo FiveManage. O servidor valida e registra somente o resultado do envio. Os videos sao limitados a 30 segundos na interface.

Celular da OB Framework. Mantém os números, contatos, mensagens, perfis,
publicações e bateria que já existiam. Não instala o Sky Phone nem substitui
o inventário, banco, garagem ou framework por QBCore/ESX.

## Uso

- **K** abre/guarda o celular. ESC guarda. Digitar K nos campos não fecha a tela.
- Desbloqueio por clique ou arrastando para cima; barra inferior volta ao início.
- Telefone: teclado, chamadas recebidas/efetuadas e histórico das últimas 40.
- Ligação: atender, recusar, desligar, silenciar o microfone da chamada e viva-voz.
- Guardar a tela não desliga a ligação. Abra novamente com K para controlar.
- Ajustes: 5 cases, 3 papéis de parede, tema claro/escuro e toque silencioso.
- Powerbank: use o item `powerbank` no inventário; não existe recarga pelos Ajustes.
- Contatos compartilháveis, mensagens com foto/video/audio, Obgram, DarkChat,
  banco, garagem/rastreamento, calculadora e notas.
- A OB Store instala e remove aplicativos externos por personagem.
- Notas e aparência são salvas neste computador, separadas por número. Não são
  sincronizadas com outro computador nem transferidas pelo item.

## Chamadas e viva-voz

Requer `ob_voice` atualizado/iniciado para telefonar. Os demais aplicativos não
têm dependência rígida dele. As rotas privadas são autorizadas no servidor;
não são canais PMA que o cliente escolhe. A compatibilidade PMA existente no
ob_voice continua separada e não permite ingressar nessas rotas do telefone.

Viva-voz: jogadores até `SpeakerDistance` metros do aparelho escutam a pessoa
do outro lado. São apenas ouvintes, **não** entram na chamada nem têm seu
microfone transmitido para ela. Ao sair do raio ou desligar o viva-voz, essa
rota é removida. Somente o mesmo routing bucket é permitido. O som é de chamada
(não uma fonte 3D posicionada no prop). No Legacy usa destinos/volume do Mumble;
no Enhanced usa canais direcionais com mute/deaf no servidor.

Silenciar corta sua transmissão **na chamada**; não remove sua voz ambiente
normal. A câmera grava fotos e vídeos da visão do jogo e usa o FiveManage,
mas chamadas continuam somente por voz. Não há promessa de compatibilidade
completa com exports do LB Phone. Os cases alteram a moldura
da NUI, não a textura do prop 3D que o personagem segura.

`config.lua` contém tempo de espera, raio do viva-voz, intervalo de
consumo em ligação e aparência inicial. Calls, item, bateria, ocupado,
participantes, queda/morte/restrição e troca de personagem são checados no
servidor. Chamadas consomem bateria com tela fechada. Encerramento/saída/restart
remove as rotas de áudio e libera os participantes. Não há migração destrutiva;
apenas a nova tabela `ob_phone_calls` é criada automaticamente na inicialização.

## Aplicativos externos

### Aplicativos padrão, loja ou desativados

Em `config.lua`, `Apps` aceita três valores por ID:

- `default`: instalado para todos e fora da loja;
- `store`: disponível para instalar/remover na OB Store;
- `disabled`: não aparece no celular.

Isso funciona para aplicativos internos e para IDs publicados por outros
resources. O `darkchat` vem configurado como `store`, servindo também como
exemplo funcional. Em `DarkChat.BlockedJobs`, informe um ou mais nomes de
trabalho que não podem abrir o aplicativo. A verificação ignora o estado de
serviço (`onDuty`). Uma lista vazia libera o aplicativo para todos.

### Publicação por outro resource

Outro resource pode publicar um aplicativo na OB Store sem editar o `ob_phone`.
O resource dono deve declarar seus arquivos web no próprio `fxmanifest.lua` e
registrar o app no cliente:

```lua
local function registerApp()
    exports.ob_phone:AddApp({
        id = 'minha_empresa',
        name = 'Minha Empresa',
        description = 'Serviços e pedidos da empresa.',
        developer = 'Minha cidade',
        version = '1.0.0',
        category = 'servicos',
        icon = 'web/icon.png',
        entry = 'web/index.html',
        defaultInstalled = false,
        removable = true
    })
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then registerApp() end
end)
AddEventHandler('ob_phone:client:appsReady', registerApp)
```

O app roda em um `iframe` isolado. Ele recebe `ob-phone:ready` e mensagens do
resource por `exports.ob_phone:SendAppMessage(id, payload)`. Para enviar uma
ação da página ao resource dono:

```js
window.parent.postMessage({
  type: 'ob-phone:event',
  event: 'pedido',
  payload: { produto: 'agua' }
}, '*')
```

No cliente Lua, escute `ob_phone:client:appEvent`; os argumentos são resource
dono, id do app, nome do evento e payload. Sempre valide no servidor qualquer
ação que altere dinheiro, itens ou dados.

## Ativação e teste na cidade

Nenhum restart foi executado automaticamente. Fora de chamadas em andamento:

```text
restart ob_voice
restart ob_phone
```

Se o restart do ob_voice parar o bridge compatível, use `ensure pma-voice`
(o bridge OB já instalado, não o pma original arquivado).

Com 3 jogadores e celulares na mochila:

1. A liga para B; B atende. Testar a distância, recusar, número ocupado e não atender.
2. C fica perto de B, A fica longe. Sem viva-voz C não deve ouvir A.
3. B ativa viva-voz: C ouve A. C afasta mais de 3m ou B desativa: para de ouvir.
4. C nunca deve ser transmitido para A apenas por estar perto de B.
5. A silencia a chamada, guarda com ESC e reabre com K. Testar desligar/sair.
6. Verificar consumo e recarga com powerbank, inclusive de tela fechada.
7. Repetir em Legacy e Enhanced; áudio real depende de microfone/artifact e não
   é validado por simulação. Referência: https://docs.fivem.net/docs/scripting-manual/voice/

Testes automatizados na raiz da base:

```text
node tests/ob-phone-calls-check.cjs
node tests/ob-phone-data-check.cjs
node tests/ob-phone-ui-check.cjs
node tests/ob-voice-check.cjs
```

## Assets e licença

Ícones WEBP, molduras e wallpaper copiados sem modificação do pacote local
Sky Phone 0.3.14, de Sky Systems (https://github.com/sky-systems/sky_phone).
O README de origem declara GPL-3.0. Foram mantidas cópias da licença e dos
avisos upstream em `web/assets/SKY-LICENSE.txt` e `SKY-THIRD-PARTY-NOTICES.md`.
A fonte Inter mantém sua licença OFL em `web/assets/INTER-LICENSE.txt`.
Os SVG de contatos/mensagens e o restante da integração foram escritos para OB.
O renderizador de captura da visão do jogo foi adaptado da implementação GPL-3.0
do Sky Phone; os bundles completos e os scripts servidor/cliente não foram copiados.
Antes de redistribuir comercialmente, revise as obrigações das licenças dos
assets; não os anuncie como autoria exclusiva da OB ou como assets do LB Phone.
