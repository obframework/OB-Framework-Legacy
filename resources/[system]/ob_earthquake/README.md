# ob_earthquake

Alerta de terremoto independente do `ob_blackout` e sem QBCore ou banco de dados.
O `ensure [system]` existente inicia o recurso na Enhanced.

## Sequencia automatica

Quando o txAdmin anuncia um reinicio agendado, o recurso prepara os ultimos
5 minutos. A chuva comeca fraca nos minutos 5 e 4 e fica forte, com trovoada,
no minuto 3. O aviso e disparado nos minutos 5, 4, 3 e 2. Aos 3 minutos a
energia pisca devagar; aos 2, mais rapido; no ultimo minuto fica desligada e
a camera comeca a tremer. Ao cancelar/pular o reinicio
ou parar o efeito, o clima e a energia normal sao restaurados. Se ja houver
um apagao do `ob_blackout`, a energia permanece desligada por ele; essa
compatibilidade e opcional e nao cria dependencia entre os recursos.

O txAdmin precisa enviar o evento com pelo menos 5 minutos de antecedencia
para que toda a sequencia ocorra. Se o primeiro aviso vier depois, o efeito
comeca na fase correspondente ao tempo restante, sem simular fases passadas.

## Audio

O audio esta desativado ate existir a gravacao. Coloque a sirene e locucao
em `sounds/alerta_terremoto.ogg`, depois altere `Audio.Enabled` para `true`
em `config.lua`. Pode usar `.mp3` ou `.wav`, desde que atualize `Audio.File`.
O arquivo e reproduzido nos minutos configurados em `Audio.PlayAtMinutes`.
Sem arquivo ou com `Enabled = false`, os avisos visuais continuam funcionando.

Texto sugerido para gravacao: "Atencao, atencao. Nao e um treinamento.
Repetindo: nao e um treinamento. Estamos com alerta de terremoto para os
proximos minutos. Corram para os abrigos."

## Comandos e teste

No console: `refresh` e `restart ob_earthquake`. Em jogo, um administrador
com permissao `world.weather` pode usar `/terremoto 300` para testar a
sequencia completa e `/terremoto parar` para cancelar o efeito. O comando
manual nao reinicia o servidor. Duracoes menores entram diretamente na fase
correspondente. O reinicio agendado do txAdmin nao e cancelado por esse comando.

O servidor controla o inicio, a duracao e o cancelamento; clientes apenas
recebem a sincronizacao. Quem entrar no meio recebe a fase atual.
Teste visual e sonoro dentro do FiveM ainda e necessario apos o restart.
