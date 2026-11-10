# ob_database

Camada MySQL/MariaDB compartilhada pelos recursos OB.

## Reconexao

Erros de transporte como `ECONNREFUSED`, `ECONNRESET`, `ETIMEDOUT` e
`PROTOCOL_CONNECTION_LOST` colocam o banco como indisponivel e iniciam novas
tentativas automaticamente. O intervalo padrao e 5 segundos e pode ser
ajustado antes do `ensure ob_database`:

```cfg
set ob_database_reconnect_ms 5000
```

O valor aceito fica entre 1000 e 60000 ms. A consulta que detectou a queda nao
e repetida automaticamente, pois repetir uma escrita pode duplicar dados. Os
recursos inscritos recebem o estado indisponivel e, depois, o estado pronto
quando uma nova conexao for estabelecida.
