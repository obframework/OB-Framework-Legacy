# Módulos do inventário

Cada funcionalidade acoplada ao inventário fica em sua própria pasta, com
cliente e servidor separados quando necessário:

```text
modules/<nome>/client/main.lua
modules/<nome>/server/main.lua
data/<nome>.lua
```

`modules/inventory/` é o módulo-base: slots, peso, persistência, NUI, itens no
chão e exports comuns. Módulos como `needs`, `shops`, baús, crafting e
inventário de veículos usam esses exports, sem transformar cada um em um
recurso independente.
