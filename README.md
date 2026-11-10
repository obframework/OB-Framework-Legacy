# OB Framework Legacy

Versao Legacy do OB Framework para servidores FiveM baseados no GTA V Legacy.

Esta variante preserva a mesma arquitetura principal da framework Enhanced,
adaptada ao ambiente Legacy e configurada originalmente para o game build
`3889`.

> O projeto esta pausado e esta versao e disponibilizada como arquivo publico.
> Revise e teste tudo em um ambiente separado antes de usar em producao.

## Como funciona

O `server.cfg` carrega `ob_database`, `ob_lib` e `ob_core` antes dos sistemas
de voz, target, inventario, veiculos, administracao, criacao de personagem e
spawn. Depois sao iniciadas as colecoes `[system]`, `[scripts]`, `[maps]`,
`[props]` e `[cars]`.

A distribuicao inclui sistemas de administracao, inventario, HUD, pause menu,
telefone, organizacoes, economia, lojas, banco, garagem, policia, mecanica,
empregos, clima, evidencias e atividades legais e ilegais.

## Requisitos

- FXServer compativel com GTA V Legacy;
- MariaDB/MySQL;
- OneSync;
- configuracao privada valida do Cfx.re, banco e servicos externos.

## Instalacao

1. Clone este repositorio na pasta desejada do servidor.
2. Copie `server.private.cfg.example` para `server.private.cfg` e substitua os indicadores.
3. Configure `SEU_IDENTIFICADOR` e os demais indicadores do `server.cfg`.
4. Baixe e publique o repositorio de imagens no caminho `/orbis/`.
5. Inicie pelo `server.cfg` e acompanhe o console na primeira inicializacao.

## Imagens obrigatorias

As imagens utilizadas pelas interfaces ficam em um repositorio separado:

**[OB-Framework-Imagens](https://github.com/obframework/OB-Framework-Imagens)**

Publique o conteudo sob `/orbis/`. Sem esses arquivos, imagens de itens,
veiculos, roupas e outras interfaces podem nao aparecer.

## Versao Enhanced

A versao principal para GTA V Enhanced fica no repositorio
**[OB-Framework](https://github.com/obframework/OB-Framework)**.

## Seguranca

Nunca envie para o GitHub um `server.private.cfg` preenchido, tokens, senhas,
chaves Cfx, webhooks ou credenciais de banco. Os arquivos desta copia possuem
somente indicadores publicos.

## Licencas

Os recursos de terceiros mantem suas respectivas licencas e creditos. Confira
cada recurso antes de redistribuir ou operar comercialmente.
