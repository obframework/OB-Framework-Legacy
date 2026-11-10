# OB Job Center

Central provisoria para ingresso voluntario em organizacoes legais do `ob_org`.

## Configuracao

- Local, NPC, blip, prazos, regras e empregos ficam em `config.lua`.
- A chave de cada emprego precisa ser igual ao `org_key` criado no `/adminorg`.
- Apenas organizacoes ativas com tipo `legal` sao liberadas pelo servidor.
- O jogador entra sempre no cargo com maior `level`, que e o menor cargo da hierarquia atual.
- Permanencia minima padrao: 24 horas.
- Blacklist depois da saida voluntaria: 1 hora.

O recurso esta dentro de `[scripts]` e inicia automaticamente no proximo boot.
Para testar sem reiniciar toda a cidade:

```text
refresh
restart ob_org
ensure ob_jobcenter
```

Reiniciar `ob_org` em producao pode atualizar o estado de trabalho dos jogadores
conectados. Prefira testar em ambiente de desenvolvimento ou no proximo boot.
