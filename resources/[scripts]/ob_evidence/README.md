# OB Evidence

Sistema de pericia integrado ao `ob_inventory`, `ob_org` e `ob_database`.

- Disparos deixam estojos temporarios no chao, com target preciso na entidade.
- Armas policiais com serial registrado nao geram estojos e nao podem ser examinadas no terminal.
- Os props dos estojos permanecem visiveis para todos. A lupa pericial libera somente os marcadores, targets e a coleta.
- Os props usam streaming local por grade: cada jogador renderiza apenas os estojos proximos, com limite configuravel. O servidor tambem aplica validade de 45 minutos e teto global, evitando acumulo ilimitado.
- Uma unica interacao recolhe ate 12 estojos proximos do mesmo calibre em um raio de 2 metros, usando um saco vazio para cada unidade.
- A bancada configurada em `shared/config.lua` abre a NUI do laboratorio.
- Estojos analisados permanecem quatro dias no arquivo balistico. A arma suspeita precisa ser examinada para revelar correspondencias.
- O kit de pericia examina a arma equipada sem consumir a arma nem o kit.
- Kits residual e quimico sao descartaveis e produzem laudos de campo.
- O kit de digital gera uma amostra lacrada; a identidade so pode ser associada aos vestigios depois do cadastro no laboratorio.
- Vendas do `ob_drugselling` registram contato quimico. O uso de uma droga pelo inventario registra consumo, com mensagem diferente no laudo.
- Outros recursos podem integrar o sistema pelos exports `MarkDrugUse(source, itemName, origin)` e `MarkDrugContact(source, itemName, origin)`.
- Os laudos persistem em `ob_forensic_reports`. Arquivos temporarios usam `ob_ballistic_archive`, `ob_fingerprint_traces` e `ob_chemical_traces`.

Pontos, duracoes, itens e nomes dos calibres ficam em `shared/config.lua`.
