# ob_economy

Tesouro e livro-caixa opcionais da OB Framework. O recurso nao e dependencia
de lojas, garagem, concessionaria, mecanica, combustivel ou organizacoes.

O modo fica em `shared/config.lua`:

- `active`: o recurso cobra/paga jogadores e movimenta o Tesouro.
- `monitor`: registra a movimentacao simulada e o recurso chamador usa o fluxo
  de pagamento antigo.
- `disabled`: nao registra nem controla valores; o fluxo antigo e usado.

Se a pasta for removida ou o recurso estiver parado, `ob_lib` devolve
`fallback=true` e os demais scripts continuam funcionando. Nao adicione
`dependency 'ob_economy'` nos manifests das integracoes.

O comando administrativo e `/economia`. O acesso exige a permissao configurada
em `AdminPermission` ou o acesso administrativo de emergencia do `ob_core`.

As tabelas `ob_economy_accounts` e `ob_economy_ledger` sao criadas
automaticamente. `initialBalance` somente vale na primeira criacao de cada
conta e nunca sobrescreve um saldo existente.
