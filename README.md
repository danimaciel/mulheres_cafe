# Mulheres do Café

Site estático com dados sobre as mulheres na cafeicultura brasileira, publicado pelo GitHub Pages.

- **Página inicial** (`index.html`): apresentação do trabalho invisível das mulheres no café, com os principais números.
- **Atlas das Mulheres do Café** (`atlas/`): protótipo com mapas municipais, diagnóstico por município, perfil das dirigentes o cadastro de organizações de mulheres do café e a lista de estudos da Embrapa sobre café com pelo menos uma autora da Embrapa.

## Dados

- Censo Agropecuário 2017 (IBGE/SIDRA), fonte de todos os números por sexo. A Produção Agrícola Municipal aparece só como menção à parte.
- Mapeamento de organizações e iniciativas de mulheres do café, feito em novembro de 2026 a partir de sites, notícias e publicações (`dados/organizacoes_mulheres_cafe.csv`). Só constam canais institucionais; não há contatos pessoais de lideranças.
- Estudos da Embrapa sobre café (`atlas/estudos_autoras.json`): recorte de cafeicultura das publicações e projetos do Redape (exportação de novembro de 2026), com os documentos em que pelo menos uma pessoa da Embrapa identificada na autoria ou na liderança é mulher. A lista não traz nomes de pessoas; cada item leva ao registro original.
- Parte dos números foi conferida com o [painel Café em Números](https://www.embrapa.br/web/cafe/painel-cafe-em-numeros), da Embrapa Café e da Embrapa Territorial.

A base municipal está em `dados/` e o método em `dados/COMO_FOI_PROCESSADO.md`. O script `R/01_base_ibge_mulheres_cafe.R` refaz a base a partir da API do SIDRA.

## Como ver no computador

O Atlas carrega os dados com `fetch`, por isso não abre com duplo clique. Na pasta do repositório, rode `python -m http.server` e abra http://localhost:8000.
