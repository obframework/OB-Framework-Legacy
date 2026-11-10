# ob_fiscal

Camada fiscal opcional para lojas de conveniencia pertencentes a jogadores.

- O dinheiro sujo depositado sai do inventario e entra em um caixa nao declarado.
- O proprietario declara parte do caixa, paga a taxa configurada e recebe o liquido no saldo empresarial da loja.
- O pro-labore debita a loja e credita a conta bancaria do proprietario.
- A capacidade diaria depende das vendas reais registradas pela loja.
- Declaracoes incompativeis recebem uma pontuacao de risco e podem gerar investigacao e alerta no `ob_dispatch`.

## Independencia

`ob_fiscal` nao e dependencia do `ob_inventory`, `ob_moneywash`, `ob_economy`, `ob_bank` ou `ob_dispatch`.
Se ele parar, lojas e lavagens comuns continuam funcionando. Se as lojas estiverem paradas, o painel fiscal empresarial apenas fica indisponivel.

## Acesso

- NPC de gerenciamento da loja: opcao `Contabilidade e declaracao fiscal`.
- Proprietario: `/fiscal`.
- Policia em servico: `/fiscalpolicia`.

Os limites, imposto, permissao policial e limiares de risco ficam em `shared/config.lua`.

## Ativacao e teste

Em uma manutencao, reinicie primeiro `ob_inventory` para carregar os exports e a
tabela de movimentos idempotentes; depois inicie `ob_fiscal`:

```text
restart ob_inventory
ensure ob_fiscal
```

Teste com uma loja de conveniencia que possua dono:

1. Abra o atendente e escolha a opcao fiscal.
2. Deposite dinheiro sujo e confirme que saiu do inventario.
3. Declare parte do caixa e confirme imposto, saldo empresarial e historico.
4. Retire pro-labore e confirme o credito no banco.
5. Entre em servico como policial e abra `/fiscalpolicia`.

As tabelas sao criadas automaticamente. Testes estaticos nao substituem este
fluxo com FXServer, banco real e dois jogadores.
