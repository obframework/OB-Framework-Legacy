# Trucker Job

Emprego cooperativo de caminhoneiro. A NUI segue o padrão visual dos empregos de ônibus e táxi, mantendo o azul como identidade da transportadora e usando ícones na navegação lateral. O recurso fica em `[scripts]`, grupo que já é iniciado pelo `server.cfg` da base.

## Fluxo

1. Use o target no encarregado em `1208.6292, -3115.4504, 5.5403`.
2. Monte uma equipe de até quatro pessoas e distribua os pontos de habilidade.
3. O líder escolhe uma das 40 ofertas globais. A oferta escolhida é substituída imediatamente por outra da mesma faixa, mantendo sempre 40 opções sem esperar a renovação completa de 120 segundos. Cada faixa mantém pelo menos cinco opções sem exigência de licença; as cinco curtas também respeitam o alcance inicial de 2 km.
   A lista preserva a ordem das faixas de distância, mas embaralha as ofertas dentro de cada faixa; valor, XP e distância exata não empurram sempre a melhor oferta para o fim.
4. O caminhão e a carreta de cada integrante nascem juntos, depois que o servidor confirma uma vaga livre para cada um. O caminhão nasce trancado e recebe chave temporária pelo `ob_vehiclekeys`.
5. O cone azul serve apenas para identificar cada veículo: o do caminhão desaparece depois que o motorista entra e o da carreta depois do primeiro engate. Todos usam o mesmo modelo, carga e destino da oferta.
6. No destino, desacople a carreta dentro do checkpoint e pressione E. Se a carga for destruída, volte ao pátio e retire outra sem aceitar o serviço novamente.
7. Devolva o cavalo mecânico na área azul de 20 metros e pressione E para receber.

O valor bruto da oferta é dividido pelo tamanho original do grupo. Cada participante recebe seu próprio bônus de integridade, cuidado e eficiência, além do bônus por equipe. Quem não entrega e devolve seu conjunto não recebe.

## Progressão

O nível máximo é 30. Um ponto é liberado por nível depois do primeiro. Cada habilidade aceita até 7 pontos:

- Distância: define o alcance individual; no grupo é usada a média em quilômetros.
- Licenças de carga: libera cargas especiais; somente o nível do líder é exigido.
- Cuidado com a carga: aumenta o bônus individual de integridade.
- Eficiência: aumenta dinheiro e XP individuais.

## Configuração

Tudo fica em `config.lua`:

- `Trucker.depot.truckSpawns`: vagas dos caminhões.
- `Trucker.depot.trailerSpawns`: vagas das carretas.
- `Trucker.depot.returnArea`: centro e raio da devolução.
- `Trucker.trucks`: modelos e porcentagens relativas.
- `Trucker.cargoTypes`: modelos, licenças, multiplicadores e porcentagens.
- `Trucker.distanceGroups`: destinos separados em `short`, `medium`, `long` e `extreme`.
- `Trucker.offers`: quantidade, tempo de atualização e economia base.
- `Trucker.offers.minimumPerDistanceGroup`: mínimo garantido de ofertas por faixa.
- `Trucker.payment`: bônus, tempo mínimo e limite de destruição.

As ofertas são exibidas da menor para a maior distância. `Trucker.payment.damageToIntegrity` controla quanto do dano bruto da carreta afeta a carga; o padrão `0.20` transforma apenas 20% da perda nativa em perda de integridade.

O início do serviço reserva uma vaga de caminhão e uma de carreta. Cada vaga é verificada como uma faixa retangular independente, comprida no sentido de saída e estreita lateralmente, para não liberar cedo enquanto um veículo ainda está saindo nem bloquear a vaga vizinha. Se não existir uma dupla livre, o contrato não é iniciado.

Ao desconectar, quitar ou sofrer crash, o evento `playerDropped` remove imediatamente o caminhão e a carreta somente daquele integrante. Uma repetição curta da remoção cobre entidades que estejam migrando de proprietário de rede no instante da queda. Se quem saiu era o líder, a liderança passa para outro integrante conectado e a entrega dos demais continua.

Para manter compatibilidade com Legacy, a validação servidor procura o NetID somente entre os veículos que ainda existem. Isso evita a sequência de avisos `GetNetworkObject: no object by ID` durante remoção ou migração da entidade.

As porcentagens funcionam como pesos e não precisam somar exatamente 100.

## Aplicação

Na primeira instalação, reinicie o grupo ou inicie o recurso:

```text
ensure ob_truckerjob
```

O recurso cria automaticamente a tabela `ob_trucker_progress`. Validação estática não confirma colisões, espaço das vagas, posição dos checkpoints, engate das sete carretas ou equilíbrio da economia; faça o primeiro teste no FiveM com quatro jogadores.

As coordenadas iniciais de destinos foram inspiradas na lista do projeto MIT `lama-development/TruckJob`; nenhuma lógica, interface ou integração de framework foi copiada.
