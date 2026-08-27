-- Gold · dimensões conformadas
-- Lê SÓ da silver. Cada dimensão é uma linha por chave de negócio, pronta
-- para JOIN direto com o fato — sem cálculo extra do lado de quem consome.

-- Mesma armadilha do fato_vendas: a deduplicação (silver/01-clientes.sql)
-- descartou até 40 cliente_id, mas pedidos antigos ainda apontam para o id
-- descartado. Sem este mapa, o cliente sobrevivente pareceria ter comprado
-- menos do que comprou de verdade.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
WITH mapa_cliente AS (
  SELECT cliente_id AS cliente_id_original, cliente_id AS cliente_id_resolvido
  FROM lakehouse_rotaperfume.silver.clientes
  UNION ALL
  SELECT explode(cliente_ids_duplicados) AS cliente_id_original, cliente_id AS cliente_id_resolvido
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
),
-- pedido CANCELADO não conta como compra: nem para "cliente comprou",
-- nem para "quando foi a última vez que comprou".
pedidos_do_cliente AS (
  SELECT m.cliente_id_resolvido AS cliente_id,
         MIN(p.data_pedido)     AS data_primeiro_pedido,
         MAX(p.data_pedido)     AS data_ultimo_pedido,
         COUNT(*)               AS total_pedidos,
         SUM(p.valor_liquido)   AS receita_acumulada
  FROM lakehouse_rotaperfume.silver.pedidos p
  JOIN mapa_cliente m ON m.cliente_id_original = p.cliente_id
  WHERE NOT p.cancelado
  GROUP BY m.cliente_id_resolvido
)
SELECT
  c.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  pc.data_primeiro_pedido,
  pc.data_ultimo_pedido,
  COALESCE(pc.total_pedidos, 0)     AS total_pedidos,
  COALESCE(pc.receita_acumulada, 0) AS receita_acumulada,
  -- Referência é o último pedido de TODA a base, não a data de hoje: o
  -- dado é fixo por seed, e todo mundo que rodar tem que chegar no mesmo
  -- número. Coincide com 2026-08-31, mas calculado, não hardcoded.
  datediff(
    (SELECT MAX(data_pedido) FROM lakehouse_rotaperfume.silver.pedidos),
    pc.data_ultimo_pedido
  ) AS dias_sem_comprar
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN pedidos_do_cliente pc ON pc.cliente_id = c.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Uma linha por cliente. Métricas de relacionamento pré-calculadas para
   uso direto em dashboard e Genie, sem precisar agregar pedidos de novo.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.dias_sem_comprar IS
  'Dias entre o último pedido do cliente e 31/08/2026 (a data de referência
   fixa do dataset). Base do critério de risco de churn.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.receita_acumulada IS
  'Soma de valor_liquido de todos os pedidos do cliente (pedidos cancelados
   somam zero, não distorcem o total).';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  marca,
  categoria,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  NOT ativo AS descontinuado
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Uma linha por SKU, com o campo descontinuado explícito para quem
   analisa venda de produto fora de linha sem precisar saber que ativo
   existe.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  meta_mensal,
  data_desligamento IS NULL AS ativo
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Uma linha por vendedor. ativo = true quando não há data de
   desligamento.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
SELECT
  data,
  year(data)                                          AS ano,
  month(data)                                         AS mes,
  CASE month(data)
    WHEN 1 THEN 'Janeiro' WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
    WHEN 4 THEN 'Abril'   WHEN 5 THEN 'Maio'      WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho'   WHEN 8 THEN 'Agosto'    WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro'
  END                                                  AS nome_mes,
  quarter(data)                                        AS trimestre,
  CASE dayofweek(data)
    WHEN 1 THEN 'Domingo'    WHEN 2 THEN 'Segunda-feira'
    WHEN 3 THEN 'Terça-feira' WHEN 4 THEN 'Quarta-feira'
    WHEN 5 THEN 'Quinta-feira' WHEN 6 THEN 'Sexta-feira'
    WHEN 7 THEN 'Sábado'
  END                                                  AS dia_semana,
  -- o varejo compra ANTES da data comemorativa: o pico da distribuidora é
  -- o mês anterior a Dia das Mães (mai), Namorados (jun) e Black Friday
  -- (nov) — ou seja, abril, junho e outubro.
  month(data) IN (4, 6, 10)                             AS mes_pico_setor
FROM (
  SELECT explode(sequence(DATE'2024-09-01', DATE'2026-08-31', INTERVAL 1 DAY)) AS data
);

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Uma linha por dia, cobrindo os 24 meses do dataset (set/2024 a ago/2026).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_calendario.mes_pico_setor IS
  'true em abril, junho e outubro — os meses em que o varejo repõe estoque
   ANTES do Dia das Mães, Dia dos Namorados e Black Friday. O pico da
   distribuidora é sempre o mês anterior à data comemorativa, não o mês
   dela.';
