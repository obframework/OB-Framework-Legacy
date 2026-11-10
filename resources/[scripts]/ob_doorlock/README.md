# ob_doorlock

Sistema próprio de trancas da OB Framework.

- `/portaseditor` abre o editor independente.
- O `ob_adminmenu` oferece o módulo **Portas e trancas** quando o recurso está iniciado.
- Grupos concentram permissões do `ob_org`, exigência de serviço, distância, estado padrão e fechamento automático.
- Portas simples ou duplas são capturadas olhando diretamente para cada folha.
- Grupos, portas e o estado atual ficam nas tabelas `ob_doorlock_groups` e `ob_doorlock_doors`.
- O servidor confirma distância e autorização antes de qualquer alteração.

Para permitir uma organização inteira, use sua chave como permissão, por exemplo `police`, `ambulance` ou `mechanic`.
Também podem ser utilizadas permissões adicionais cadastradas no cargo pelo `ob_org`.
