# Moeda global do OB Framework

A moeda de todos os recursos OB adaptados e definida em `currency.json`.
O padrao e dolar americano. Se o arquivo estiver ausente, vazio ou com JSON
invalido, os recursos continuam funcionando e usam dolar automaticamente.

Campos:

- `code`: codigo informativo da moeda, como `USD`, `BRL` ou `EUR`;
- `locale`: localidade informativa da interface;
- `symbol`: simbolo exibido;
- `symbolPosition`: `before` ou `after`;
- `spaceBetween`: adiciona um espaco entre simbolo e valor;
- `decimals`: quantidade de casas decimais, de 0 a 4;
- `thousandsSeparator`: separador de milhares;
- `decimalSeparator`: separador decimal.

Exemplo para real brasileiro:

```json
{
  "code": "BRL",
  "locale": "pt-BR",
  "symbol": "R$",
  "symbolPosition": "before",
  "spaceBetween": true,
  "decimals": 0,
  "thousandsSeparator": ".",
  "decimalSeparator": ","
}
```

Novos scripts Lua devem exibir valores com `OR.FormatMoney(valor)`. Novas NUIs
devem carregar `https://cfx-nui-ob_lib/web/currency.js` antes do JavaScript da
tela e usar `window.OBCurrency.format(valor)`.
