-- Silver · clientes
-- Normaliza CNPJ (3 formatos → 14 dígitos), padroniza razão social,
-- corrige data em dois formatos e deduplica os 40 CNPJs com dois cadastros.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH normalizado AS (
  SELECT
    cliente_id,
    -- CNPJ nunca vira número: trim tira o espaço em volta, regexp_replace
    -- tira ponto/barra/traço, lpad devolve o zero à esquerda que o Spark
    -- teria apagado se lêssemos como INT.
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    -- initcap trata a caixa (CAIXA ALTA -> Caixa Alta), regexp_replace
    -- colapsa espaço duplo antes de capitalizar.
    initcap(regexp_replace(trim(razao_social), '\\s+', ' ')) AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    -- data_cadastro vem em ISO (yyyy-MM-dd) e em dd/MM/yyyy misturadas.
    -- try_to_date nunca aborta: tenta o primeiro formato, senão o segundo.
    coalesce(
      try_to_date(data_cadastro, 'yyyy-MM-dd'),
      try_to_date(data_cadastro, 'dd/MM/yyyy')
    ) AS data_cadastro,
    ativo = 'S' AS ativo,
    _ingerido_em
  FROM lakehouse_rotaperfume.bronze.clientes
),
deduplicado AS (
  SELECT
    *,
    -- 40 CNPJs têm dois cliente_id. Mantemos o cadastro MAIS ANTIGO
    -- (menor data_cadastro; nulls por último, para não perder o registro
    -- só porque a data também veio suja).
    row_number() OVER (
      PARTITION BY cnpj
      ORDER BY data_cadastro ASC NULLS LAST, cliente_id ASC
    ) AS ordem
  FROM normalizado
),
descartados_por_cnpj AS (
  -- para cada CNPJ que sobrou, a lista de cliente_id que foram descartados
  -- (os pedidos antigos continuam apontando para eles).
  SELECT cnpj, collect_list(cliente_id) AS todos_os_ids
  FROM deduplicado
  WHERE ordem > 1
  GROUP BY cnpj
)
SELECT
  d.cliente_id,
  d.cnpj,
  d.razao_social,
  d.segmento,
  d.cidade,
  d.uf,
  d.bairro,
  d.data_cadastro,
  d.ativo,
  descarte.todos_os_ids AS cliente_ids_duplicados,
  current_timestamp()               AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes) AS _linhas_origem
FROM deduplicado d
LEFT JOIN descartados_por_cnpj descarte ON descarte.cnpj = d.cnpj
WHERE d.ordem = 1;

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados por CNPJ. 3.040 cadastros na bronze viram
   3.000 clientes únicos aqui — 40 CNPJs tinham dois cadastros, mantido o
   mais antigo.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cnpj IS
  'Normalizado para 14 dígitos numéricos (trim + regexp_replace + lpad).
   Nunca convertido para número, senão o zero à esquerda some.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cliente_ids_duplicados IS
  'IDs de cadastros duplicados descartados na deduplicação, para
   rastreabilidade — pedidos antigos podem apontar para esses IDs.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT cnpj_14_digitos CHECK (length(cnpj) = 14);

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT data_cadastro_preenchida CHECK (data_cadastro IS NOT NULL);
