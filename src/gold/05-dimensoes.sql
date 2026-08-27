-- Gold · dimensões conformadas
-- Lê SÓ da silver. Cada dimensão é uma linha por chave de negócio, pronta
-- para JOIN direto com o fato — sem cálculo extra do lado de quem consome.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
SELECT
  c.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  MIN(p.data_pedido)                                        AS data_primeiro_pedido,
  MAX(p.data_pedido)                                        AS data_ultimo_pedido,
  COUNT(p.pedido_id)                                        AS total_pedidos,
  COALESCE(SUM(p.valor_liquido), 0)                         AS receita_acumulada,
  -- "hoje" é a data fixa do dataset (2026-08-31), nunca current_date():
  -- o dado é gerado uma vez e o número tem que dar igual pra sempre.
  datediff(DATE'2026-08-31', MAX(p.data_pedido))            AS dias_sem_comprar
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN lakehouse_rotaperfume.silver.pedidos p ON p.cliente_id = c.cliente_id
GROUP BY c.cliente_id, c.razao_social, c.segmento, c.cidade, c.uf, c.data_cadastro;

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
