# Mulheres do Café

Site estático com dados sobre as mulheres na cafeicultura brasileira, publicado pelo GitHub Pages.

- **Página inicial** (`index.html`): apresentação do trabalho invisível das mulheres no café, com os principais números.
- **Atlas das Mulheres do Café** (`atlas/`): protótipo com mapas municipais, diagnóstico por município, perfil das dirigentes e o cadastro de organizações de mulheres do café.

## Dados

- Censo Agropecuário 2017 e Produção Agrícola Municipal (IBGE/SIDRA).
- Mapeamento de organizações e iniciativas de mulheres do café, feito em novembro de 2026 a partir de sites, notícias e publicações (`dados/organizacoes_mulheres_cafe.csv`). Só constam canais institucionais; não há contatos pessoais de lideranças.
- Parte dos números foi conferida com o [painel Café em Números](https://www.embrapa.br/web/cafe/painel-cafe-em-numeros), da Embrapa Café e da Embrapa Territorial.

A base municipal está em `dados/` e o método em `dados/COMO_FOI_PROCESSADO.md`. O script `R/01_base_ibge_mulheres_cafe.R` refaz a base a partir da API do SIDRA.

## Como ver no computador

O Atlas carrega os dados com `fetch`, por isso não abre com duplo clique. Na pasta do repositório, rode `python -m http.server` e abra http://localhost:8000.
