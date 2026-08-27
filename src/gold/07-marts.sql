-- Gold · marts — um por diretoria, todos sobre o MESMO fato_vendas.
-- O que separa um mart do outro é a dimensão dominante e as métricas,
-- nunca a tabela base: criar fato_vendas_comercial e fato_vendas_produto
-- é o erro clássico que faz dois relatórios divergirem em três meses.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
SELECT
  f.vendedor_id,
  v.nome,
  v.regiao,
  f.ano,
  f.mes,
  ROUND(SUM(f.receita), 2)                                   AS receita,
  ROUND(SUM(f.margem), 2)                                    AS margem,
  v.meta_mensal                                              AS meta,
  ROUND(100 * SUM(f.receita) / NULLIF(v.meta_mensal, 0), 1)  AS atingimento_pct,
  COUNT(DISTINCT f.cliente_id)                               AS clientes_atendidos,
  ROUND(SUM(f.receita) / NULLIF(COUNT(DISTINCT f.pedido_id), 0), 2) AS ticket_medio
FROM lakehouse_rotaperfume.gold.fato_vendas f
JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = f.vendedor_id
GROUP BY f.vendedor_id, v.nome, v.regiao, f.ano, f.mes, v.meta_mensal;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Grão vendedor × mês. Para a diretoria comercial: quem vendeu quanto,
   contra qual meta, para quantos clientes.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.atingimento_pct IS
  'Receita do mês dividida pela meta mensal do vendedor, em percentual.
   Acima de 100 significa meta batida.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.ticket_medio IS
  'Receita do mês dividida pelo número de pedidos distintos do vendedor
   no mês — não pelo número de itens.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH por_sku_mes AS (
  SELECT
    sku,
    ano,
    mes,
    ROUND(SUM(receita), 2)                                     AS receita,
    ROUND(SUM(margem), 2)                                      AS margem,
    ROUND(100 * SUM(margem) / NULLIF(SUM(receita), 0), 1)      AS margem_pct,
    SUM(quantidade)                                             AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, ano, mes
),
-- curva ABC é uma classificação do produto no período INTEIRO — não faz
-- sentido reclassificar por mês, senão o mesmo SKU vira A num mês e C no
-- seguinte. Calculada uma vez sobre o total e repetida em toda linha do
-- SKU.
receita_total_por_sku AS (
  SELECT sku, SUM(receita) AS receita_total
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku
),
curva_abc AS (
  SELECT
    sku,
    receita_total,
    SUM(receita_total) OVER (ORDER BY receita_total DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(receita_total) OVER ()                              AS pct_acumulado
  FROM receita_total_por_sku
)
SELECT
  m.sku,
  d.marca,
  d.categoria,
  m.ano,
  m.mes,
  m.receita,
  m.margem,
  m.margem_pct,
  m.quantidade,
  CASE
    WHEN c.pct_acumulado <= 0.80 THEN 'A'
    WHEN c.pct_acumulado <= 0.95 THEN 'B'
    ELSE 'C'
  END AS curva_abc
FROM por_sku_mes m
JOIN curva_abc c ON c.sku = m.sku
JOIN lakehouse_rotaperfume.gold.dim_produto d ON d.sku = m.sku;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Grão SKU × mês. Para o time de produto: receita, margem e curva ABC —
   quais produtos concentram receita e merecem prioridade de reposição.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_produto_performance.curva_abc IS
  'Classificação pela receita acumulada do SKU no período INTEIRO (não por
   mês): A = os produtos que juntos somam até 80% da receita, B = até 95%,
   C = o restante. Fixa por SKU — não muda mês a mês.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  year(data_vencimento)                                       AS ano,
  month(data_vencimento)                                      AS mes,
  ROUND(SUM(valor), 2)                                        AS valor_a_receber,
  ROUND(SUM(valor_liquido)
          FILTER (WHERE status_pagamento IN ('Pago', 'Pago com atraso')), 2) AS valor_recebido,
  ROUND(AVG(datediff(data_pagamento, data_vencimento))
          FILTER (WHERE data_pagamento IS NOT NULL
                     AND data_pagamento > data_vencimento), 1) AS atraso_medio_dias,
  ROUND(SUM(valor - valor_liquido), 2)                        AS custo_taxa
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Grão mês de VENCIMENTO (não de venda). Para o financeiro: quanto tinha
   que entrar, quanto entrou de fato, com que atraso e a que custo de
   taxa da forma de pagamento.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.custo_taxa IS
  'Diferença entre valor nominal e valor líquido — o que a taxa da forma
   de pagamento (ex.: cartão) consumiu do recebimento.';
