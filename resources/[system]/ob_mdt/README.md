# ob_mdt

MDT da OB Framework reaproveitando o fluxo visual do antigo `orbis-mdt`, sem QBCore ou oxmysql.

## Acesso

- `/mdt`: organização/permissão `police`, em serviço por padrão.
- `/adv`: organização/permissão `lawyer`.
- limpeza de ficha: acesso externo `mdt.clear` no cargo ou administrador.
- auditoria: acesso externo `mdt.audit` no cargo ou administrador.

Todas as buscas e ações usam o `user_id` fixo do personagem. Prisões registradas são enviadas ao `ob_prison`, inclusive para personagens offline. A multa é registrada como pendente; a cobrança automática ficará para o futuro fluxo financeiro do sistema de justiça.

As tabelas são criadas automaticamente pelo recurso.
