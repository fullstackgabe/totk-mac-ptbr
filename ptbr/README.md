# Tears of the Kingdom PT-BR (dublagem + legendas)

Variante deste port nativo que gera um app separado, **Tears of the Kingdom PT-BR**, com a dublagem e as legendas em português de mods da comunidade. Testado no 1.0.0 em um Mac M4.

Este repositório **não contém nenhum arquivo do jogo nem dos mods**. Você precisa ter os seus.

## O que muda em relação ao projeto original

- **App próprio:** `build_app.py` gera `Tears of the Kingdom PT-BR.app` com o identificador `org.macnativegames.totk.ptbr`. Saves e cache de shaders continuam em `~/Library/Application Support/MacNativeGames/TOTK`.
- **Mais arquivos substituídos:** `runtime/romfs.c` aceita até 4096 arquivos substituídos em vez de 16, porque a dublagem tem cerca de 1400. O limite de arquivos abertos do processo também foi aumentado.
- **Analógico esquerdo do Pro Controller:** `runtime/gamepad.m` lê o analógico esquerdo e o D-pad do [pro-bridge](https://github.com/fullstackgabe/pro-bridge) (servidor DSU em `127.0.0.1:26760`) quando ele está rodando. No macOS, o GameController não entrega o analógico esquerdo do Switch Pro Controller via Bluetooth. Sem o pro-bridge, nada muda.
- **`ptbr/make_ptbr_overlay.py`:** monta os arquivos em português para o 1.0.0, junto com os ajustes do próprio port:
  - **Texto:** `Mals/USpt.Product.142.sarc.zs` do mod "Sem Legenda nas Falas Dubladas" ocupa o lugar de `Mals/USen.Product.100.sarc.zs`. As falas dubladas ficam sem legenda e o resto fica em português.
  - **Telas:** de `Common` e `Title.Product.110` do mod de dublagem, só a textura `timg/__Combined.bntx` entra nos arquivos do 1.0.0. Ela é a única diferença entre eles. O ajuste de captura do menu rápido que o port faz em `Common` é reaplicado.
  - **Tabela de tamanhos:** `ResourceSizeTable.Product.100` recebe os tamanhos maiores. Por exemplo, o texto vai de 11,4 MB para 21,6 MB.
  - **Vozes, sons e texturas:** vozes (`Voice/`), sons (`Sound/`) e texturas são copiados nos mesmos caminhos do 1.0.0.

## Como gerar

Você precisa:
- Do jogo base 1.0.0 (XCI ou NSP) e do seu `prod.keys`, como no README principal.
- Do mod **Dublagem Triforce Heroes 3.1**, só a pasta `romfs/`.
- Do mod **Sem Legenda nas Falas Dubladas**, só a pasta `romfs/`. É dele que vem `Mals/USpt.Product.142.sarc.zs`.

```sh
# 1. Build normal (gera a pasta de trabalho e um app ainda em inglês)
python3.14 build_app.py ~/Games/totk.xci -k ~/keys/prod.keys --work ~/Games/TOTK_build

# 2. Troca os arquivos que o port substitui pela versão PT-BR
python3.14 -I ptbr/make_ptbr_overlay.py ~/Games/TOTK_build/totk \
    --dub  "/caminho/Dublagem Triforce Heroes 3.1/romfs" \
    --text "/caminho/Sem Legenda nas Falas Dubladas/romfs"

# 3. Build de novo: cerca de 5 minutos, reaproveita tudo e embala os novos arquivos no app
python3.14 build_app.py ~/Games/totk.xci -k ~/keys/prod.keys --work ~/Games/TOTK_build
```

O texto em português fica no lugar do inglês americano, então o jogo precisa rodar em `en-US`. Com o Mac em português, o port pede o idioma "pt", que o TotK não tem. Para forçar `en-US` e manter depois de reiniciar:

```sh
launchctl setenv TOTK_LANG en-US
```

Para valer em todo login, crie um LaunchAgent que rode esse mesmo comando com `RunAtLoad`.

## Limitações

- Só o 1.0.0. Os mods foram feitos para o 1.2.1 e o 1.4.2. Na prática a dublagem e o texto funcionam, mas alguma fala pode ficar sem voz ou sem tradução.
- Os créditos da dublagem e da tradução são dos autores dos mods (Triforce Heroes).
