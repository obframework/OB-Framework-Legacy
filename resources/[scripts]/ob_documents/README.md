# ob_documents

Recurso central dos documentos pessoais da OB Framework. Nao cria NPC nem
local de atendimento: outros recursos decidem onde emitir ou solicitar vias.
O Centro de Licencas nunca oferece servico de identidade.

O recurso inicia e administra a identidade sem `ob_licenca`. A integracao da
CNH e detectada em tempo de execucao: se a autoescola nao estiver instalada ou
estiver parada, somente as operacoes de CNH ficam indisponiveis. Nenhum dos dois
recursos declara o outro como dependencia no manifesto.

Itens administrados:

- `identity_card`: nao vence. Primeira emissao vem de um recurso autorizado,
  como o futuro kit inicial; depois disso somente o futuro local de identidade
  deve solicitar a segunda via por $2.500.
- `driver_license`: vence em 14 dias, renova por $1.500 e custa $2.500 para
  segunda via. Categorias sao lidas dos registros oficiais do `ob_licenca`.

Exports de servidor:

```lua
exports.ob_documents:GiveInitialIdentity(source) -- identidade inicial, uma vez
exports.ob_documents:GiveInitialDocuments(source) -- alias para integracao futura
exports.ob_documents:IssueIdentity(source) -- alias da identidade inicial
exports.ob_documents:ReplaceIdentity(source) -- somente segunda via, cobra taxa
exports.ob_documents:IssueDriverAfterApproval(source)
exports.ob_documents:ProcessDriverDmv(source)
exports.ob_documents:GetStatus(source)
exports.ob_documents:GetInspection(userId, source)
exports.ob_documents:HasLicense(userId, 'car')
```

A tabela `ob_license_documents` e criada automaticamente. Os itens tem
durabilidade infinita. `GiveInitialIdentity` entrega apenas a identidade; a CNH
nasce somente depois de uma aprovacao na autoescola. Sua validade fica no registro
oficial e na metadata, portanto editar a descricao do item nao concede habilitacao.
