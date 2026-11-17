# Como a base IBGE do Atlas foi processada

Script: `R/01_base_ibge_mulheres_cafe.R`. Ele refaz toda a base municipal e chega aos mesmos números da versão em Python (`ibge_build.py`). A conferência coluna a coluna, nos 5.563 municípios e nas 144 colunas, mostrou apenas diferenças de 0,1 no arredondamento de 1 ou 2 municípios.

## Como rodar
1. Abra `atlas_mulheres_cafe.Rproj` no RStudio.
2. Instale os pacotes, se faltarem: `install.packages(c("jsonlite","dplyr","tidyr","readr","stringi","arrow"))`.
3. Para rodar sem baixar nada, descompacte `02_dados_ibge/sidra_bruto.zip` dentro de `02_dados_ibge/saida_R/`. Fica `saida_R/sidra_bruto/*.json`, com as respostas exatas da API usadas na base. Se preferir baixar tudo de novo do IBGE, não descompacte: o download leva uns 20 minutos.
4. Rode o script. As saídas ficam em `02_dados_ibge/saida_R/`:
   - `base_municipal_mulheres_cafe_R.csv` (e o `.parquet`, se o arrow estiver instalado): base completa, com 144 colunas.
   - `base_municipal_so_mulheres_R.csv`: só o recorte feminino, com 97 colunas.
   - `conferencia_brasil_regiao_uf.csv`: totais oficiais de Brasil, regiões e UFs, para conferir.

## Passo a passo
| etapa | tabela SIDRA | consulta | o que vira |
|---|---|---|---|
| 1 | 6883 | classe 112888 "Cultivo de café" × sexo do produtor | `cafe_estab_*`, `cafe_area_*` (t = total, h = homens, m = mulheres, na = não se aplica) |
| 2 | 6883 | classe 110016 "Total" × sexo | `agro_estab_*`, `agro_area_*` (todas as atividades) |
| 3 | 6779 | orientação técnica 113111 "Recebe" × sexo | `agro_orient_tec_*` |
| 4 | 6851 | 114543 "É associado" e 113455 "Cooperativa" × sexo | `agro_assoc_*`, `agro_coop_*` |
| 5 | 6869 | estabelecimentos com tratores × sexo | `agro_tratores_*` |
| 6 | 6776 | dirigidos pelo produtor, por cor ou raça × sexo | `agro_dirigidos_*` (cor = Total) e `agro_negras_*` (Preta + Parda) |
| 6b | 6776 | escolaridade (c800, todas as categorias) × mulheres, agrupada em nunca frequentou / fundamental / médio ou técnico / superior | `agro_escol_*_m`, `agro_nao_sabe_ler_m` |
| 6c | 6768 | direção dos trabalhos (c346: Total e "Casal (codireção)") × sexo, em lavouras permanentes | `lp_dir_tot_*`, `lp_dir_cod_*` |
| 6d | 6768 | todas as atividades (c12517 = 113601), por idade × sexo de quem dirige (produtor ou administrador) | `dir68_<idade>_<t,h,m>` |
| 6e | 6776 | escolaridade dos homens e cor ou raça por categoria × sexo | `agro_escol_*_h`, `agro_raca_<cor>_<h,m>` |
| 7 | 1613 (PAM) | café total, arábica e canéfora; área colhida, quantidade e valor; último ano (2025) | `pam_*` |

Regras aplicadas em todas as tabelas:
- `"-"` vira 0.
- `"X"`, que é sigilo do IBGE, vira NA, e nunca 0. Uma soma de valores que são todos NA continua NA.
- As classificações que não aparecem na consulta vêm no "Total" do IBGE: tipologia, idade, escolaridade e outras.
- Quando a consulta municipal passa de 100 mil valores, o script baixa UF por UF.

Indicadores (`ind_*`):
- `ind_pct_estab_cafe_mulheres` = mulheres ÷ total de estabelecimentos com café como atividade principal.
- `ind_pct_area_cafe_mulheres` = área das mulheres ÷ área total, nos mesmos estabelecimentos.
- `ind_area_media_*` = área ÷ número de estabelecimentos, por sexo.
- `ind_pct_orientacao_tecnica_*`, `_cooperativa_*`, `_associada_qualquer_entidade_*` e `_tratores_*`: o numerador é a tabela do tema e o denominador são os estabelecimentos **dirigidos** por pessoas do mesmo sexo (6776, cor = Total). O recorte é de **todas as atividades**.
- `ind_pct_dirigentes_mulheres_negras` = (pretas + pardas) ÷ total de mulheres dirigentes.
- `especie_predominante` (só municípios cafeeiros): Arábica quando 80% ou mais da produção da PAM é arábica, Canéfora quando 80% ou mais é canéfora, Misto entre os dois. Sem produção na PAM, usa os estabelecimentos com arábica e com conilon do Censo (tabela 6955, via CSV do BigQuery). São 608 municípios de arábica, 169 de canéfora e 25 mistos. A mesma regra, aplicada a todos os municípios com café no Censo ou com produção na PAM (2.059 municípios, inclusive os de baixa produção), gera `especie_predominante_todos`: 1.528 de arábica, 388 de canéfora e 143 mistos. É a camada de espécie do mapa, com cor forte para os municípios cafeeiros e cor clara para os de baixa produção (pouca quantidade produzida, sem relação com agricultura familiar).
- `municipio_cafeeiro` = 20 ou mais estabelecimentos de café (6883), **ou** 100 t ou mais (PAM), **ou** 50 ou mais estabelecimentos com café (CSV do BigQuery).

## Números do painel Café em Números e o que o Atlas destaca
Alguns dados do Atlas foram trazidos do [painel Café em Números](https://www.embrapa.br/web/cafe/painel-cafe-em-numeros), da Embrapa Café e da Embrapa Territorial.

**O que vem do painel e bate com ele:**
- 264.361 estabelecimentos com café (tabela 6955): 188.392 com arábica e 75.969 com canéfora, dos quais 205.620 (77,8%) são da agricultura familiar. São 1.983 municípios com café (`municipio_com_cafe`).
- Mulheres na direção dos estabelecimentos com café, **estimativa** (`proxy_estab_cafe_mulheres_estimado`, `est_m_arabica`, `est_m_canefora`). Em cada município, os estabelecimentos com café são multiplicados pela proporção de mulheres entre quem dirige os estabelecimentos agropecuários do município (tabela 6768). O resultado é 33.685: 23.217 no arábica e 10.468 no canéfora. No painel, os números são 23.091 e 10.396. A diferença é de 0,5%, provavelmente pelo arredondamento. Arredondando município a município, a soma dá 33.562.
- Para validar, há o único dado observado de café por sexo: 14.297 mulheres entre os 136.604 estabelecimentos com café como atividade principal (6883).

**Cuidado com os 1.855.894 e os 319.900:** eles vêm da tabela 6768 somada nos municípios com café. São estabelecimentos agropecuários de **todas as atividades**, contados pelo sexo de quem os dirige. Não são cafeicultoras nem população. Por exemplo, Ji-Paraná (RO) tem 408 estabelecimentos dirigidos por mulheres, mas só 109 estabelecimentos com café. No Atlas, a 6768 aparece só como **perfil em %** (idade) desses territórios, e a 6776 da mesma forma (escolaridade e raça).

Entradas opcionais:
- **Levantamento do painel** (`levantamento_painel_6955_tipologia.csv`). Traz a tabela 6955 por município, com código IBGE e agricultura familiar. Quando existe, é ele que define os municípios com café: 1.983, com 264.361 estabelecimentos, iguais ao CSV do BigQuery.
- **CSV do BigQuery.** Traz os estabelecimentos *com* café, por espécie, e é unido pelo nome do município e pela UF: 5.486 municípios casaram. Ele também gera `proxy_estab_cafe_mulheres_estimado`, uma estimativa e não um dado observado.
- **Parquet dos coletivos.** Fornece `n_organizacoes_mulheres_mapeadas`.

## Indicadores-síntese
| indicador | cálculo | leitura | Brasil (municípios cafeeiros) |
|---|---|---|---|
| `ind_envelhecimento_*` | dirigentes com 65 anos ou mais ÷ dirigentes com menos de 25, no grupo "lavoura permanente" (tabela 6768: c12517 = 111521, c12551, c12566), com mínimo de 3 jovens | "para cada jovem, há N idosos" | total 11,4 · mulheres 10,6 · homens 11,5 |
| `ind_paridade_acesso` | média de (% mulheres ÷ % homens) em orientação técnica, cooperativa e trator, com 10 ou mais mulheres dirigentes | 1 = paridade; 0,5 = metade do acesso | 0,52 (orientação 0,64, cooperativa 0,48, trator 0,43) |
| `ind_codirecao` | estabelecimentos dirigidos pelo casal ÷ total, em lavouras permanentes (6768, c346), com 10 ou mais estabelecimentos | quanto da direção é compartilhada | 15,2% |
| `ind_participacao_ampliada_mulheres` | (mulher como dirigente principal + casal em que o homem respondeu) ÷ total, no mesmo recorte; compare com `ind_pct_dirigentes_mulheres_lp` | presença feminina na direção, contando a codireção | 26,0% (contra 13,1% só como dirigente principal) |
| `ind_razao_area_media_m_h` | área média dos estabelecimentos de café dirigidos por mulheres ÷ a dos dirigidos por homens (6883), com 5 ou mais estabelecimentos de mulheres. É a área total do estabelecimento, não só a lavoura de café | abaixo de 1 = estabelecimentos femininos menores | 0,78 |
| `ind_org_por_mil_mulheres` | organizações mapeadas ÷ mulheres dirigentes estimadas × 1.000 | densidade organizativa | 1,3 |
| `territorio_prioritario` | município cafeeiro, 100 ou mais mulheres dirigentes estimadas e nenhuma organização mapeada | onde articular primeiro | 93 municípios |

Sobre a codireção: o IBGE registra que a direção é do casal, mas não informa o sexo do cônjuge. Quando quem respondeu é homem, supomos que a mulher divide a direção. É uma estimativa, e por isso o índice aparece separado do percentual de mulheres dirigentes.

Para Brasil, regiões e UFs, o Atlas soma numeradores e denominadores dos municípios cafeeiros antes de dividir.

## Ao comparar com os números da Embrapa
Estas são as diferenças mais prováveis e de onde elas vêm:
1. **Atividade principal × presença do café.** A tabela 6883 só conta os estabelecimentos *cuja atividade principal é o café*: são 136.604 no Brasil. As tabelas de produção do Censo contam todos os que *têm* café: cerca de 264 mil, como no CSV exportado do BigQuery. Esse é o principal motivo de divergência, sobretudo em RO e no ES conilon.
2. **Sexo do produtor.** O IBGE separa "Não se aplica" (pessoa jurídica, condomínio etc.). Por isso homens + mulheres ≠ total. O percentual feminino aqui usa o **total** como denominador. Se a Embrapa usar homens + mulheres, o número dela sai um pouco maior.
3. **Sigilo.** Somar municípios não fecha com o total da UF, porque os valores com "X" ficam fora. Compare as UFs com `conferencia_brasil_regiao_uf.csv`, que vem direto do IBGE.
4. **Ano.** O Censo Agro é de 2017 e a PAM é de 2025. Painéis com PAM de outro ano vão mostrar outra produção.
5. **CSV do BigQuery.** A coluna `valor` (sexo × faixa etária) é o total de estabelecimentos agropecuários do município, e não só os de café, com valores fracionários de rateio.

Para comparar município a município, una a tabela da Embrapa à base pela coluna `cod_ibge` (7 dígitos):

```r
emb  <- readr::read_csv("caminho/tabela_embrapa.csv")   # precisa ter cod_ibge
base <- readr::read_csv("02_dados_ibge/saida_R/base_municipal_mulheres_cafe_R.csv")
cmp  <- dplyr::inner_join(base, emb, by = "cod_ibge") |>
  dplyr::mutate(dif = cafe_estab_m - estab_mulheres_embrapa)   # ajuste o nome da coluna
dplyr::arrange(cmp, dplyr::desc(abs(dif)))
```
