# Zelda nativo no Mac — PT-BR

Versão do [MacNativeGames](https://github.com/ly05010419/MacNativeGames) (de ly05010419, licença MIT) para jogar
**Tears of the Kingdom** e **Breath of the Wild** em português, com duas correções de controle que valem para os dois
jogos.

| Jogo | Versão | Português |
|---|---|---|
| Tears of the Kingdom | 1.4.3 | dublagem + legendas |
| Breath of the Wild | 1.6.0 + DLCs 1 e 2 | legendas (vozes em inglês) |
 O port em si — o código do jogo rodando direto no Apple Silicon,
os serviços do Switch e os gráficos NVN sobre Metal — é todo do projeto original. Os créditos da dublagem e da tradução
são dos autores dos mods (Triforce Heroes).

Este repositório **não contém nenhum arquivo do jogo, keys nem dos mods**. Você precisa ter os seus.

## O que muda em relação ao original

- **Analógicos e D-pad do Pro Controller via [pro-bridge](https://github.com/fullstackgabe/pro-bridge)**
  (`games/totk/runtime/gamepad.m`). No macOS, o GameController não entrega o analógico esquerdo do Switch Pro Controller
  pelo Bluetooth (ele chega como D-pad). Com o pro-bridge rodando (servidor DSU em `127.0.0.1:26760`), os analógicos e o
  D-pad vêm dele. Sem o pro-bridge, nada muda.
- **Desvio do giroscópio** (`games/totk/runtime/motion_fusion.c`). Alguns Pro Controllers têm calibração de fábrica
  ruim (um deles lia 4, 8 e 1,5 graus/s parado), e a mira com movimento escorregava sozinha. Agora o desvio é medido
  sempre que o controle fica parado por cerca de meio segundo e é descontado, como no SDL/Ryujinx.
  `TOTK_GYRO_BIAS=0` desliga essa correção.

As correções ficam no runtime compartilhado (`games/totk/runtime`), que os dois apps usam.

O português entra como **mod do jogador** (o projeto original já carrega mods de RomFS), sem mudar o build.

## Tears of the Kingdom (1.4.3)

Você precisa do jogo base 1.0.0 (XCI ou NSP), do update **1.4.3**, do seu `prod.keys` e de duas pastas `romfs/`:

- **Dublagem Triforce Heroes 3.1** (versão para emulador)
- **Sem Legenda nas Falas Dubladas** (traz `Mals/USpt.Product.142.sarc.zs`)

Monte a pasta do mod:

```sh
M=~/Games/mod_ptbr_143
mkdir -p "$M/romfs/Mals"
rsync -a --exclude 'Mals/USen.Product.121.sarc.zs' \
         --exclude 'System/Resource/ResourceSizeTable.Product.121.rsizetable.zs' \
         --exclude 'UI/LayoutArchive/Common.Product.110.Nin_NX_NVN.blarc' \
         "/caminho/Dublagem Triforce Heroes 3.1/romfs/" "$M/romfs/"
# O texto em português nos dois idiomas: o jogo roda em en-US (vozes dubladas no lugar das inglesas)
cp "/caminho/Sem Legenda nas Falas Dubladas/romfs/Mals/USpt.Product.142.sarc.zs" "$M/romfs/Mals/USpt.Product.142.sarc.zs"
cp "/caminho/Sem Legenda nas Falas Dubladas/romfs/Mals/USpt.Product.142.sarc.zs" "$M/romfs/Mals/USen.Product.142.sarc.zs"
```

E faça o build com o mod (`--install-mod-romfs` instala em
`~/Library/Application Support/MacNativeGames/TOTK/mods/v143` e ajusta a tabela de heap e o arquivo `Common` do port):

```sh
python3.14 build_app.py ~/Games/totk.xci -k ~/keys/prod.keys \
    --update ~/Games/totk-1.4.3.nsp --mod ~/Games/mod_ptbr_143 --install-mod-romfs
```

O jogo precisa rodar em `en-US`. Para fixar (e manter depois de reiniciar, com um LaunchAgent que rode o mesmo comando):

```sh
launchctl setenv TOTK_LANG en-US
```

## Breath of the Wild (1.6.0 + DLCs)

Você precisa do jogo base (NSP), do update **1.6.0** (`v786432`), das DLCs que tiver e do seu `prod.keys`:

```sh
python3.14 build_app.py ~/Games/botw.nsp -k ~/keys/prod.keys --update ~/Games/botw-1.6.0.nsp \
    --dlc ~/Games/botw-dlc1.nsp --dlc ~/Games/botw-dlc2.nsp
```

A legenda em português vem do mod **Tradução Triforce Heroes** (só textos). Copie o conteúdo da pasta `romfs/` dele para
a pasta de mods da 1.6.0 e gere o manifesto:

```sh
MODDIR="$HOME/Library/Application Support/MacNativeGames/BotW/mods/botw160"
mkdir -p "$MODDIR" && cp -R "/caminho/Tradução Triforce Heroes/romfs/." "$MODDIR/"
python3 games/totk/scripts/make_mod_manifest.py "$MODDIR" --app "/caminho/Breath of the Wild.app"
```

O mod traz a própria `ResourceSizeTable` (o texto em português é maior que o original). O jogo precisa rodar em
`en-US`: `defaults write org.macnativegames.botw AppleLanguages -array en-US`.

## Saves

O TOTK guarda em `~/Library/Application Support/MacNativeGames/TOTK/profile` e o BOTW em `.../MacNativeGames/BotW/profile`,
fora do app. Na primeira vez que uma versão nova
abre, o app faz um backup completo (`profile-before-1.4.3`). Um save de versão mais nova não abre numa versão mais antiga.

## Limitações

- TOTK: a tela de título e algumas texturas de menu ficam em inglês: os arquivos `Common`/`Title.Product.110` do mod foram
  feitos para a 1.2.1 e a 1.4.3 não os carrega.
- TOTK: os mods foram feitos para 1.2.1/1.4.2: alguma fala pode ficar sem voz ou sem tradução.
