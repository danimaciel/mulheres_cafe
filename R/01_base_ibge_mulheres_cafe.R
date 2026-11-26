# =============================================================================
# Atlas das Mulheres do Café: base municipal IBGE (Censo Agro 2017 + PAM)
# Reproduz em R a base_municipal_mulheres_cafe gerada originalmente em Python.
#
# Pacotes: jsonlite, dplyr, tidyr, readr, stringi (arrow é opcional, para parquet)
# Uso: abra atlas_mulheres_cafe.Rproj (a pasta do projeto vira o diretório de
# trabalho) e rode o script inteiro. Os JSONs brutos do SIDRA ficam em cache em
# PASTA_SAIDA/sidra_bruto: com o cache presente, nada é baixado de novo. Apague
# essa pasta para refazer tudo direto da API do IBGE (leva uns 20 minutos).
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(dplyr); library(tidyr); library(readr); library(stringi)
})

PASTA_SAIDA  <- "02_dados_ibge/saida_R"   # onde gravar a base e o cache
CSV_BIGQUERY  <- "entradas/export_bigquery_cafe_socio_prod_municipio.csv"  # opcional
ORGS_PARQUET <- "01_mapeamento_coletivos/coletivos_mulheres_cafe.parquet"              # opcional
CSV_PAINEL   <- "entradas/levantamento_painel_6955_tipologia.csv"   # opcional (painel Café em Números, com cod_mun)
if (!file.exists(CSV_BIGQUERY))  CSV_BIGQUERY  <- NA
if (!file.exists(CSV_PAINEL))   CSV_PAINEL   <- NA
if (!file.exists(ORGS_PARQUET) || !requireNamespace("arrow", quietly = TRUE)) ORGS_PARQUET <- NA

options(timeout = 900)  # o SIDRA demora em consultas municipais grandes
dir.create(file.path(PASTA_SAIDA, "sidra_bruto"), recursive = TRUE, showWarnings = FALSE)
API <- "https://apisidra.ibge.gov.br/values/t/"
UFS <- c(11:17, 21:29, 31:33, 35, 41:43, 50:53)

# -----------------------------------------------------------------------------
# 1. Download do SIDRA
#    Formato da consulta: /t/{tabela}/n6/all (municípios)/v/allxp (todas as
#    variáveis, sem percentuais)/p/all/c{classificação}/{categorias}
#    Classificações não citadas vêm no "Total". O limite é 100 mil valores por
#    consulta; se falhar, a função repete UF por UF (n6/in n3 {uf}).
# -----------------------------------------------------------------------------
le_sidra_json <- function(arq) {
  m <- fromJSON(arq, simplifyVector = TRUE)
  cab <- unlist(m[1, ]); df <- m[-1, , drop = FALSE]
  nome_original <- df$D1N                 # nome do local com acentos, para a saída
  names(df) <- cab[names(df)]
  # nomes e categorias em ASCII (sem acento) para o script rodar igual em
  # qualquer sistema e codificação (Windows, Linux, Mac)
  ascii <- function(x) gsub("\u00aa", "a", gsub("\u00ba", "o", stri_trans_general(x, "Latin-ASCII")))
  names(df) <- ascii(names(df))
  df[] <- lapply(df, function(x) if (is.character(x)) ascii(x) else x)
  df$nome_local <- nome_original
  df
}

baixa_sidra <- function(nome, consulta) {
  arq <- file.path(PASTA_SAIDA, "sidra_bruto", paste0(nome, ".json"))
  if (!file.exists(arq)) {
    url <- paste0(API, consulta, "?formato=json")
    ok <- tryCatch({ download.file(url, arq, quiet = TRUE, mode = "wb"); TRUE },
                   error = function(e) FALSE)
    if (!ok) {
      message(nome, ": consulta grande, baixando por UF")
      partes <- lapply(UFS, function(u) {
        a <- file.path(PASTA_SAIDA, "sidra_bruto", sprintf("%s_uf%d.json", nome, u))
        if (!file.exists(a))
          download.file(paste0(API, sub("n6/all", sprintf("n6/in%%20n3%%20%d", u), consulta),
                               "?formato=json"), a, quiet = TRUE, mode = "wb")
        le_sidra_json(a)
      })
      return(bind_rows(partes) |> trata_valor())
    }
  }
  le_sidra_json(arq) |> trata_valor()
}

# Convenções do SIDRA: "-" = zero absoluto; "X" = valor inibido por sigilo
# (fica NA, nunca zero); "..", "..." = não se aplica / não disponível.
trata_valor <- function(df) {
  df |> mutate(V = case_when(Valor == "-" ~ 0,
                             Valor %in% c("X", "..", "...") ~ NA_real_,
                             TRUE ~ suppressWarnings(as.numeric(Valor))),
               cod_ibge = if ("Municipio (Codigo)" %in% names(df))
                 as.integer(`Municipio (Codigo)`) else NA_integer_)
}

sexo <- function(x) recode(x, "Homens" = "h", "Mulheres" = "m", "Total" = "t",
                           "Nao se aplica" = "na")

# soma que preserva NA quando todos os valores são NA (equivale a min_count=1)
soma_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

# Tabela 6883: estabelecimentos e área por grupo/classe de atividade × sexo
#   c12440 = Grupos e classes de atividade (112888 = Cultivo de café; 110016 = Total)
#   c12564 = Sexo do produtor (all)
t6883_cafe <- baixa_sidra("t6883_cafe", "6883/n6/all/v/allxp/p/all/c12440/112888/c12564/all")
t6883_agro <- baixa_sidra("t6883_agro", "6883/n6/all/v/allxp/p/all/c12440/110016/c12564/all")
# Tabela 6779: orientação técnica (c12567 = 113111 "Recebe") × sexo
t6779 <- baixa_sidra("t6779_orient", "6779/n6/all/v/allxp/p/all/c12567/113111/c12564/all")
# Tabela 6851: associação (c12598: 114543 "É associado"; 113455 "Cooperativa") × sexo
t6851 <- baixa_sidra("t6851_assoc", "6851/n6/all/v/allxp/p/all/c12598/114543,113455/c12564/all")
# Tabela 6869: tratores × sexo
t6869 <- baixa_sidra("t6869_trat", "6869/n6/all/v/allxp/p/all/c12564/all")
# Tabela 6776: dirigidos pelo produtor por cor ou raça (c830) × sexo (homens, mulheres)
t6776 <- baixa_sidra("t6776_raca", "6776/n6/all/v/allxp/p/all/c830/all/c12564/112634,112635")
# PAM 1613: café total (2723), arábica (31619), canéfora (31620); área colhida,
# quantidade e valor; último ano disponível
pam <- baixa_sidra("pam1613", "1613/n6/all/v/216,214,215/p/last/c82/2723,31619,31620")

# Censo 2017, tabela 6955: quantidade produzida de café arábica (111647) e
# canéfora (111648) nos estabelecimentos com 50 pés ou mais. É a base da
# classificação dos municípios cafeeiros e da espécie predominante, para que
# a classificação use o mesmo ano e a mesma fonte dos dados por sexo.
t6955q <- baixa_sidra("t6955_quant_cafe", "6955/n6/all/v/9506/p/all/c227/111647,111648")

# -----------------------------------------------------------------------------
# 2. Pivot para o formato largo (uma linha por município)
# -----------------------------------------------------------------------------
larga <- function(df, prefixo, ...) {
  df |> group_by(cod_ibge, ...) |> summarise(V = soma_na(V), .groups = "drop") |>
    pivot_wider(names_from = c(...), values_from = V, names_prefix = prefixo, names_sep = "_")
}

prep6883 <- function(df) df |> mutate(s = sexo(`Sexo do produtor`),
  var = if_else(startsWith(`Variavel`, "Numero"), "estab", "area"))
b_cafe <- t6883_cafe |> prep6883() |> larga("cafe_", var, s)
b_agro <- t6883_agro |> prep6883() |> larga("agro_", var, s)

b_orient <- t6779 |> mutate(s = sexo(`Sexo do produtor`)) |> larga("agro_orient_tec_", s)

b_assoc <- t6851 |>
  mutate(s = sexo(`Sexo do produtor`),
         a = recode(`Associacao do produtor a cooperativa e/ou a entidade de classe`,
                    "E associado" = "assoc", "Cooperativa" = "coop")) |>
  larga("agro_", a, s)

b_trat <- t6869 |> filter(startsWith(`Variavel`, "Numero de estabelecimentos")) |>
  mutate(s = sexo(`Sexo do produtor`)) |> larga("agro_tratores_", s)

b_dirig <- t6776 |> filter(`Cor ou raca do produtor` == "Total") |>
  mutate(s = sexo(`Sexo do produtor`)) |> larga("agro_dirigidos_", s)
b_negras <- t6776 |> filter(`Cor ou raca do produtor` %in% c("Preta", "Parda")) |>
  mutate(s = sexo(`Sexo do produtor`)) |> larga("agro_negras_", s)

# Escolaridade das mulheres dirigentes (tabela 6776, c800 = todas as categorias,
# sexo = 112635 Mulheres), agrupada em quatro niveis
t6776e <- baixa_sidra("t6776_escol", "6776/n6/all/v/allxp/p/all/c800/all/c12564/112635")
GRUPO_ESC <- c(
  "Nunca frequentou escola" = "nunca",
  "Classe de alfabetizacao - CA" = "fundamental", "Alfabetizacao de jovens e adultos - AJA" = "fundamental",
  "Antigo primario (elementar)" = "fundamental", "Antigo ginasial (medio 1o ciclo)" = "fundamental",
  "Regular do ensino fundamental ou 1o grau" = "fundamental",
  "EJA - educacao de jovens e adultos e supletivo do ensino fundamental ou do 1o grau" = "fundamental",
  "Antigo cientifico, classico, etc. (medio 2o ciclo)" = "medio", "Regular de ensino medio ou 2o grau" = "medio",
  "Tecnico de ensino medio ou do 2o grau" = "medio",
  "EJA - Educacao de jovens e adultos e supletivo do ensino medio ou do 2o grau" = "medio",
  "Superior - graduacao" = "superior", "Mestrado ou doutorado" = "superior",
  "Sabe ler e escrever - nao" = "nao_sabe_ler")
b_escol <- t6776e |> mutate(g = unname(GRUPO_ESC[`Escolaridade do produtor`])) |> filter(!is.na(g)) |>
  larga("agro_escol_", g) |>
  rename_with(~ paste0(.x, "_m"), -cod_ibge) |> rename(agro_nao_sabe_ler_m = agro_escol_nao_sabe_ler_m)

pam_ano <- as.integer(pam$Ano[1])
b_pam <- pam |>
  mutate(prod = recode(`Produto das lavouras permanentes`,
                       "Cafe (em grao) Total" = "total", "Cafe (em grao) Arabica" = "arabica",
                       "Cafe (em grao) Canephora" = "canephora"),
         var = recode(`Variavel`, "Area colhida" = "area_colhida_ha",
                      "Quantidade produzida" = "producao_t", "Valor da producao" = "valor_mil_reais")) |>
  larga("pam_", var, prod)

b_c6955 <- t6955q |>
  mutate(prod = if_else(grepl("ar.bica", `Produtos da lavoura permanente`, ignore.case = TRUE),
                        "arabica", "canefora")) |>
  larga("censo_producao_t_", prod)

nomes <- t6883_cafe |> distinct(cod_ibge, nome_local) |>
  mutate(municipio = sub(" - [A-Z]{2}$", "", nome_local),
         uf = sub("^.* - ", "", nome_local)) |> select(-nome_local)

REG <- c("1" = "Norte", "2" = "Nordeste", "3" = "Sudeste", "4" = "Sul", "5" = "Centro-Oeste")

base <- nomes |>
  mutate(regiao = unname(REG[substr(cod_ibge, 1, 1)])) |>
  left_join(b_cafe, by = "cod_ibge") |> left_join(b_agro, by = "cod_ibge") |>
  left_join(b_orient, by = "cod_ibge") |> left_join(b_assoc, by = "cod_ibge") |>
  left_join(b_trat, by = "cod_ibge") |> left_join(b_dirig, by = "cod_ibge") |>
  left_join(b_negras, by = "cod_ibge") |> left_join(b_escol, by = "cod_ibge") |> left_join(b_pam, by = "cod_ibge") |>
  left_join(b_c6955, by = "cod_ibge")

# coordenadas das sedes municipais (base aberta kelvins/municipios-brasileiros)
coords <- read_csv("https://raw.githubusercontent.com/kelvins/municipios-brasileiros/main/csv/municipios.csv",
                   show_col_types = FALSE) |>
  transmute(cod_ibge = as.integer(codigo_ibge), lat = latitude, lon = longitude)
base <- base |> left_join(coords, by = "cod_ibge")

# -----------------------------------------------------------------------------
# 3. Indicadores
#    pct() devolve NA quando o denominador é 0 ou NA.
#    Os indicadores de acesso usam como denominador os estabelecimentos
#    DIRIGIDOS pelo produtor do mesmo sexo (tabela 6776, cor/raça = Total),
#    em TODAS as atividades agropecuárias: o IBGE não cruza esses temas com café.
# -----------------------------------------------------------------------------
pct <- function(a, b) ifelse(!is.na(b) & b > 0, round(100 * a / b, 1), NA_real_)

base <- base |> mutate(
  ind_pct_estab_cafe_mulheres = pct(cafe_estab_m, cafe_estab_t),
  ind_pct_area_cafe_mulheres  = pct(cafe_area_m, cafe_area_t),
  ind_area_media_cafe_mulheres_ha = ifelse(cafe_estab_m > 0, round(cafe_area_m / cafe_estab_m, 1), NA),
  ind_area_media_cafe_homens_ha   = ifelse(cafe_estab_h > 0, round(cafe_area_h / cafe_estab_h, 1), NA),
  ind_pct_orientacao_tecnica_mulheres = pct(agro_orient_tec_m, agro_dirigidos_m),
  ind_pct_orientacao_tecnica_homens   = pct(agro_orient_tec_h, agro_dirigidos_h),
  ind_pct_cooperativa_mulheres = pct(agro_coop_m, agro_dirigidos_m),
  ind_pct_cooperativa_homens   = pct(agro_coop_h, agro_dirigidos_h),
  ind_pct_associada_qualquer_entidade_mulheres = pct(agro_assoc_m, agro_dirigidos_m),
  ind_pct_associada_qualquer_entidade_homens   = pct(agro_assoc_h, agro_dirigidos_h),
  ind_pct_tratores_mulheres = pct(agro_tratores_m, agro_dirigidos_m),
  ind_pct_tratores_homens   = pct(agro_tratores_h, agro_dirigidos_h),
  ind_pct_dirigentes_mulheres_negras = pct(agro_negras_m, agro_dirigidos_m),
  ind_pct_estab_agro_mulheres = pct(agro_estab_m, agro_estab_t),
  pam_ano = pam_ano
)

# -----------------------------------------------------------------------------
# 4. Opcionais: CSV do BigQuery (estabelecimentos COM café, sem recorte de sexo)
#    e contagem de organizações mapeadas na fase 1
# -----------------------------------------------------------------------------
norm <- function(x) gsub("[-']", " ", tolower(stri_trans_general(x, "Latin-ASCII"))) |> trimws()

if (!is.na(CSV_BIGQUERY)) {
  c <- read_csv(CSV_BIGQUERY, show_col_types = FALSE) |> filter(!is.na(uf)) |>
    distinct(uf, municipio, .keep_all = TRUE) |>
    transmute(k = paste(uf, norm(municipio), sep = "|"),
              censo_estab_com_cafe = estabelecimentos_cafe_total,
              censo_estab_com_arabica = estabelecimentos_arabica,
              censo_estab_com_conilon = estabelecimentos_conilon)
  base <- base |> mutate(k = paste(uf, norm(municipio), sep = "|")) |>
    left_join(c, by = "k") |> select(-k) |>
    mutate(proxy_estab_cafe_mulheres_estimado =
             round(censo_estab_com_cafe * agro_dirigidos_m / (agro_dirigidos_m + agro_dirigidos_h)))
} else base$censo_estab_com_cafe <- NA_real_

# Levantamento do painel Café em Números (tabela 6955 por tipologia, com código IBGE).
# Quando existe, substitui o casamento por nome e traz a agricultura familiar.
if (!is.na(CSV_PAINEL)) {
  pn <- read_csv(CSV_PAINEL, show_col_types = FALSE) |>
    transmute(cod_ibge = as.integer(cod_mun),
              censo_estab_com_cafe = estabelecimentos_cafe_total,
              censo_estab_com_arabica = estabelecimentos_arabica,
              censo_estab_com_conilon = estabelecimentos_conilon,
              censo_estab_cafe_familiar = estabelecimentos_familiar)
  base <- base |> select(-any_of(c("censo_estab_com_cafe", "censo_estab_com_arabica", "censo_estab_com_conilon"))) |>
    left_join(pn, by = "cod_ibge") |>
    mutate(proxy_estab_cafe_mulheres_estimado =
             round(censo_estab_com_cafe * agro_dirigidos_m / (agro_dirigidos_m + agro_dirigidos_h)))
}
# Universo do painel Café em Números: municípios com pelo menos 1 estabelecimento com café
base <- base |> mutate(municipio_com_cafe = coalesce(censo_estab_com_cafe, 0) > 0)

# Classificacao so com o Censo 2017 (a PAM nao entra): municipio cafeeiro tem
# 20+ estabelecimentos com cafe como atividade principal (6883), 50+ com cafe
# (6955) ou 100+ t produzidas no Censo (6955)
base <- base |> mutate(
  censo_producao_t_total = coalesce(censo_producao_t_arabica, 0) + coalesce(censo_producao_t_canefora, 0),
  municipio_cafeeiro = coalesce(censo_estab_com_cafe, 0) > 0 &
    (coalesce(cafe_estab_t, 0) >= 20 | coalesce(censo_estab_com_cafe, 0) >= 50 |
     censo_producao_t_total >= 100))

# Especie predominante: >= 80% da quantidade produzida no Censo (6955) de uma
# especie; com sigilo ou sem producao, usa os estabelecimentos com arabica/conilon
if (!"censo_estab_com_arabica" %in% names(base)) {
  base$censo_estab_com_arabica <- NA_real_; base$censo_estab_com_conilon <- NA_real_ }
base <- base |> mutate(
  .sh_q   = ifelse(!is.na(censo_producao_t_arabica) & !is.na(censo_producao_t_canefora) &
                   censo_producao_t_total > 0, censo_producao_t_arabica / censo_producao_t_total, NA),
  .n_cen  = censo_estab_com_arabica + censo_estab_com_conilon,
  .sh_cen = ifelse(!is.na(.n_cen) & .n_cen > 0, censo_estab_com_arabica / .n_cen, NA),
  .sh     = coalesce(.sh_q, .sh_cen),
  especie_predominante = case_when(!municipio_cafeeiro ~ NA_character_,
                                   .sh >= 0.8 ~ "Arabica", .sh <= 0.2 ~ "Canefora",
                                   !is.na(.sh) ~ "Misto", TRUE ~ NA_character_),
  # mesma regra para todos os municípios com café no Censo, inclusive os de
  # pequena produção
  .univ = coalesce(censo_estab_com_cafe, 0) > 0,
  especie_predominante_todos = case_when(!.univ ~ NA_character_,
                                   .sh >= 0.8 ~ "Arabica", .sh <= 0.2 ~ "Canefora",
                                   !is.na(.sh) ~ "Misto", TRUE ~ NA_character_)) |>
  select(-starts_with("."))

if (!is.na(ORGS_PARQUET)) {
  org <- arrow::read_parquet(ORGS_PARQUET) |> filter(!is.na(cod_ibge)) |>
    count(cod_ibge = as.integer(cod_ibge), name = "n_organizacoes_mulheres_mapeadas")
  base <- base |> left_join(org, by = "cod_ibge") |>
    mutate(n_organizacoes_mulheres_mapeadas = coalesce(n_organizacoes_mulheres_mapeadas, 0L))
}

# -----------------------------------------------------------------------------
# 4b. Indicadores-sintese
# -----------------------------------------------------------------------------
# Envelhecimento: dirigentes com 65+ anos / dirigentes com menos de 25 anos, no
# grupo "Producao de lavouras permanentes" (onde esta o cafe), tabela 6768.
#   c12517 = 111521 lavouras permanentes; c12551 = classe de idade
#   (112044 menor de 25; 46436 65 a 74; 46438 75 e mais); c12566 = sexo
t6768 <- baixa_sidra("t6768_idade_lp",
  "6768/n6/all/v/allxp/p/all/c12517/111521/c12551/112044,46436,46438/c12566/46500,112643,112644")
b_env <- t6768 |>
  mutate(f = if_else(grepl("Menor de 25", `Classe de idade da pessoa que dirige o estabelecimento`), "jov", "ido"),
         s = recode(`Sexo da pessoa que dirige o estabelecimento (produtor ou administrador)`,
                    "Total" = "t", "Homens" = "h", "Mulheres" = "m")) |>
  larga("lp_", f, s)
base <- base |> left_join(b_env, by = "cod_ibge")

# Codirecao: tabela 6768, c346 "Direcao dos trabalhos" (41149 Total; 40592 Casal
# (codirecao)) x sexo de quem respondeu como dirigente, em lavouras permanentes.
# O IBGE nao informa o sexo do conjuge; quando o dirigente e homem e a direcao e do
# casal, supoe-se que a mulher divide a direcao.
t6768d <- baixa_sidra("t6768_direcao_lp",
  "6768/n6/all/v/allxp/p/all/c346/41149,40592/c12566/46500,112643,112644/c12517/111521")
b_dir <- t6768d |>
  mutate(f = if_else(grepl("Casal", `Direcao dos trabalhos do estabelecimento agropecuario`), "cod", "tot"),
         s = recode(`Sexo da pessoa que dirige o estabelecimento (produtor ou administrador)`,
                    "Total" = "t", "Homens" = "h", "Mulheres" = "m")) |>
  larga("lp_dir_", f, s)
base <- base |> left_join(b_dir, by = "cod_ibge")

# Todas as pessoas que dirigem (produtor ou administrador), todas as atividades, por idade
# e sexo: tabela 6768 (c12517 = 113601 Total). Somada nos municípios com café, dá o
# recorte do painel Café em Números (Brasil: 1.855.894 dirigentes, 319.900 mulheres).
t6768t <- baixa_sidra("t6768_total_idade",
  "6768/n6/all/v/183/p/all/c12517/113601/c12551/all/c12566/46500,112643,112644")
ID68 <- c("Total" = "tot", "Menor de 25 anos" = "menor25", "De 25 a menos de 35 anos" = "25a34",
          "De 35 a menos de 45 anos" = "35a44", "De 45 a menos de 55 anos" = "45a54",
          "De 55 a menos de 65 anos" = "55a64", "De 65 a menos de 75 anos" = "65a74",
          "De 75 anos e mais" = "75mais")
b_68 <- t6768t |>
  mutate(f = unname(ID68[`Classe de idade da pessoa que dirige o estabelecimento`]),
         s = recode(`Sexo da pessoa que dirige o estabelecimento (produtor ou administrador)`,
                    "Total" = "t", "Homens" = "h", "Mulheres" = "m")) |>
  filter(!is.na(f)) |> larga("dir68_", f, s)
base <- base |> left_join(b_68, by = "cod_ibge")

# Estimativa de mulheres na direção de estabelecimentos COM café (mesmo método do painel
# Café em Números): estabelecimentos com café (6955) × proporção de mulheres entre quem
# dirige os estabelecimentos agropecuários do município (6768). Brasil: 33.685
# (23.217 arábica + 10.468 canéfora).
if ("censo_estab_com_cafe" %in% names(base)) base <- base |> mutate(
  .sh = ifelse(coalesce(dir68_tot_t, 0) > 0, dir68_tot_m / dir68_tot_t, NA_real_),
  proxy_estab_cafe_mulheres_estimado = round(censo_estab_com_cafe * .sh),
  est_m_arabica  = censo_estab_com_arabica * .sh,
  est_m_canefora = censo_estab_com_conilon * .sh) |> select(-.sh)

# Escolaridade dos homens dirigentes (6776), para comparar com a das mulheres
t6776eh <- baixa_sidra("t6776_escol_h", "6776/n6/all/v/allxp/p/all/c800/all/c12564/112634")
b_escol_h <- t6776eh |> mutate(g = unname(GRUPO_ESC[`Escolaridade do produtor`])) |> filter(!is.na(g)) |>
  larga("agro_escol_", g) |>
  rename_with(~ paste0(.x, "_h"), -cod_ibge) |> rename(agro_nao_sabe_ler_h = agro_escol_nao_sabe_ler_h)
# Cor ou raça por categoria e sexo (6776)
b_raca <- t6776 |>
  mutate(cor = recode(`Cor ou raca do produtor`, "Branca" = "branca", "Preta" = "preta", "Parda" = "parda",
                      "Amarela" = "amarela", "Indigena" = "indigena", .default = NA_character_),
         s = sexo(`Sexo do produtor`)) |>
  filter(!is.na(cor)) |> larga("agro_raca_", cor, s)
base <- base |> left_join(b_escol_h, by = "cod_ibge") |> left_join(b_raca, by = "cod_ibge")

razao <- function(a, b, min_b = 1) ifelse(!is.na(b) & b >= min_b, a / b, NA_real_)
base <- base |> mutate(
  # minimo de 3 jovens no denominador, para evitar razoes instaveis
  ind_envelhecimento_total    = round(razao(lp_ido_t, lp_jov_t, 3), 1),
  ind_envelhecimento_mulheres = round(razao(lp_ido_m, lp_jov_m, 3), 1),
  ind_envelhecimento_homens   = round(razao(lp_ido_h, lp_jov_h, 3), 1),
  # Razao de escala: area media das mulheres / area media dos homens (6883)
  ind_razao_area_media_m_h = ifelse(coalesce(cafe_estab_m, 0) >= 5,
    round(ind_area_media_cafe_mulheres_ha / ind_area_media_cafe_homens_ha, 2), NA_real_),
  # Codirecao (lavouras permanentes, 10+ estabelecimentos):
  #   % dirigidos pelo casal; % com mulher como dirigente principal; e participacao
  #   ampliada = (mulher dirigente + casal com homem respondente) / total
  .ok_dir = coalesce(lp_dir_tot_t, 0) >= 10,
  ind_codirecao = ifelse(.ok_dir, round(100 * lp_dir_cod_t / lp_dir_tot_t, 1), NA_real_),
  ind_pct_dirigentes_mulheres_lp = ifelse(.ok_dir, round(100 * lp_dir_tot_m / lp_dir_tot_t, 1), NA_real_),
  ind_participacao_ampliada_mulheres = ifelse(.ok_dir,
    round(100 * (coalesce(lp_dir_tot_m, 0) + coalesce(lp_dir_cod_h, 0)) / lp_dir_tot_t, 1), NA_real_)) |>
  select(-starts_with("."))

if ("proxy_estab_cafe_mulheres_estimado" %in% names(base) && "n_organizacoes_mulheres_mapeadas" %in% names(base)) {
  base <- base |> mutate(
    # Lacuna organizativa
    ind_org_por_mil_mulheres = ifelse(coalesce(proxy_estab_cafe_mulheres_estimado, 0) >= 20,
      round(1000 * n_organizacoes_mulheres_mapeadas / proxy_estab_cafe_mulheres_estimado, 1), NA_real_),
    territorio_prioritario = municipio_cafeeiro & coalesce(proxy_estab_cafe_mulheres_estimado, 0) >= 100 &
      n_organizacoes_mulheres_mapeadas == 0)
}

write_csv(base, file.path(PASTA_SAIDA, "base_municipal_mulheres_cafe_R.csv"), na = "")

# Versão só com o recorte feminino (sem as colunas de homens e "não se aplica")
so_mulheres <- base |> select(-matches("(_h|_na)$|_homens"))
write_csv(so_mulheres, file.path(PASTA_SAIDA, "base_municipal_so_mulheres_R.csv"), na = "")
if (requireNamespace("arrow", quietly = TRUE))
  arrow::write_parquet(base, file.path(PASTA_SAIDA, "base_municipal_mulheres_cafe_R.parquet"))
message("Base: ", nrow(base), " municípios x ", ncol(base), " colunas; cafeeiros: ",
        sum(base$municipio_cafeeiro))

# -----------------------------------------------------------------------------
# 5. Totais oficiais para conferência (Brasil e UF direto do SIDRA)
#    Por causa do sigilo ("X"), NÃO some municípios para chegar a totais de UF ou
#    Brasil: use estas consultas nos níveis n1 (Brasil), n2 (região) e n3 (UF).
# -----------------------------------------------------------------------------
ger <- baixa_sidra("t6883_cafe_geo", "6883/n1/all/n2/all/n3/all/v/allxp/p/all/c12440/112888/c12564/all")
conf <- ger |>
  mutate(s = sexo(`Sexo do produtor`),
         var = if_else(startsWith(`Variavel`, "Numero"), "estab", "area"),
         nivel = `Nivel Territorial`,
         local = nome_local) |>
  select(nivel, local, var, s, V) |>
  pivot_wider(names_from = c(var, s), values_from = V) |>
  mutate(pct_estab_mulheres = pct(estab_m, estab_t), pct_area_mulheres = pct(area_m, area_t),
         area_media_mulheres_ha = round(area_m / estab_m, 1),
         area_media_homens_ha = round(area_h / estab_h, 1)) |>
  arrange(match(nivel, c("Brasil", "Grande Regiao", "Unidade da Federacao")), desc(estab_t))
write_csv(conf, file.path(PASTA_SAIDA, "conferencia_brasil_regiao_uf.csv"), na = "")
print(conf |> select(local, estab_t, estab_m, pct_estab_mulheres, pct_area_mulheres) |> head(12))
