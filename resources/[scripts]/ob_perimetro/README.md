# ob_perimetro

Instalado somente em corerp (Enhanced), resources/[scripts]/ob_perimetro.
O `ensure [scripts]` do server.cfg ja inclui o recurso no proximo inicio.
Para carregar agora: `refresh` e `ensure ob_perimetro` no console.

## Uso

Policial em servico: `/perimetro`. Informe nome, raio e minutos e clique em
**Interditar area**. O centro vem da posicao do policial no servidor, nao do NUI.
Qualquer policial autorizado pode **Liberar area** antes do prazo. ESC fecha o menu.
Mapa e avisos sao visiveis a todos. Entrar no circulo gera um alerta, sem spam
continuo. Nao bloqueia movimento, nao cria props e nao expulsa jogadores.

Usa ob_org (permissao police + servico), ob_core, ob_lib e ob_notification.
Nao usa QBCore, qb-menu, qb-input, ox_lib, PolyZone ou banco proprio.
Somente ob_lib e dependencia de inicializacao; ob_org/core ausentes bloqueiam
o gerenciamento com seguranca. A ordem existente [system] antes de [scripts]
ja atende as integracoes. Nenhum outro recurso foi modificado.

Limites, cores, cilindro de sinalizacao e intervalos estao em config.lua.
Por padrao: raio 10-500m, duracao 1-120min, ate 10 areas simultaneas.
Gerenciamento apenas no mundo principal (routing bucket 0).
Estado temporario: restart libera todos os perimetros; desconectar o criador
nao libera a area antes do prazo. Criacao/remocao ficam registradas no console.

## Verificacao no jogo

1. Civil e policial fora de servico: comando e operacoes devem ser negados.
2. Em servico: criar, conferir circulo no mapa e aviso com outro jogador.
3. Entrar/sair do raio; remover manualmente; criar por 1min e aguardar expirar.
4. Entrar na cidade durante um perimetro: receber os blips ativos.
5. Reiniciar recurso com menu aberto: liberar cursor e limpar blips.

Testes automatizados usam natives simuladas; nao validam renderizacao no GTA.
