-- Silver · produtos e itens_pedido
-- produtos: tipagem simples. itens_pedido: quantidade negativa é devolução,
-- não erro — sinaliza em vez de descartar. Marca item de SKU descontinuado.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18,2)) AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18,2)) AS custo_unitario,
  unidade,
  ativo = 'S' AS ativo,
  try_to_date(data_lancamento, 'yyyy-MM-dd') AS data_lancamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.produtos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Catálogo de produtos tipado: preços em DECIMAL, ativo em boolean,
   data_lancamento em DATE.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
SELECT
  i.item_id,
  i.pedido_id,
  i.sku,
  CAST(i.quantidade AS INT) AS quantidade,
  -- quantidade negativa é DEVOLUÇÃO, não erro. Nunca descartamos a linha:
  -- descartar infla o faturamento, manter sem flag polui toda soma. A
  -- flag deixa a análise decidir se quer o número bruto ou o líquido.
  CAST(i.quantidade AS INT) < 0 AS devolucao,
  abs(CAST(i.quantidade AS INT)) AS quantidade_abs,
  CAST(i.preco_praticado AS DECIMAL(18,2)) AS preco_praticado,
  CAST(i.desconto_pct AS DECIMAL(9,4)) AS desconto_pct,
  CAST(i.valor_bruto AS DECIMAL(18,2)) AS valor_bruto,
  -- produto pode ter sido descontinuado DEPOIS da venda: o item continua
  -- válido, mas o gestor precisa saber que está vendendo algo fora de linha.
  NOT coalesce(p.ativo = 'S', true) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.itens_pedido i
LEFT JOIN lakehouse_rotaperfume.bronze.produtos p ON p.sku = i.sku;

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Itens de pedido com devolução sinalizada (nunca descartada) e SKU
   descontinuado marcado via join com produtos.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.devolucao IS
  'true quando a quantidade original era negativa. A linha é mantida —
   descartar infla o faturamento, manter sem flag polui toda soma.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.sku_descontinuado IS
  'true quando o produto vendido não está mais ativo no catálogo — a
   venda aconteceu, mas o item não pode ser reposto.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT quantidade_abs_positiva CHECK (quantidade_abs > 0);
