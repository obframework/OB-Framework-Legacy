# orbis-taxijob

Novo trabalho de taxi com:
- Corridas NPC com aceitar/recusar
- NUI de progresso
- XP + level + estatisticas por jogador
- Pagamento validado no servidor (anti-dump de dinheiro)
- Integracao de chave com `mri_Qcarkeys`

## Dependencias
- `ob_lib`
- `ob_database`
- `ob_core`
- `ob_inventory`
- `ob_notification`
- `ob_target`

## Instalar
1. Coloque a pasta em `resources/[scripts_externos]/[orbis]/orbis-taxijob`
2. No `server.cfg` adicione:

```cfg
ensure orbis-taxijob
```

3. Reinicie o recurso:

```cfg
restart orbis-taxijob
```

## Uso
- Va ate a central taxi (blip no mapa)
- Inicie o turno no NPC
- Aguarde chamadas, aceite e conclua corridas
- Painel NUI: comando `/taxi` (atalho `F6`)

## Configuracoes
Tudo esta em `config.lua`:
- Coordenadas boss/spawn
- Tempo entre chamadas
- Formula de pagamento
- XP e level
- Rotas de pickup/dropoff
- Textos
