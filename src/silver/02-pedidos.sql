-- Silver · pedidos
-- Corrige data em dois formatos, tipa o valor, e explicita o pedido
-- cancelado com uma flag em vez de deixar o valor zerado sem explicação.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  -- mesmo tratamento de data_cadastro: ANSI mode está ligado, então
  -- to_date() abortaria a query em vez de devolver NULL. try_to_date nunca
  -- aborta.
  coalesce(
    try_to_date(data_pedido, 'yyyy-MM-dd'),
    try_to_date(data_pedido, 'dd/MM/yyyy')
  ) AS data_pedido,
  canal,
  status,
  CAST(valor_total AS DECIMAL(18,2)) AS valor_total,
  -- pedido cancelado já vem com valor_total = 0 na origem, mas sem flag
  -- explícita — quem lê a tabela não sabe se é cancelamento ou pedido de
  -- valor zero de verdade. A flag remove a ambiguidade.
  status = 'Cancelado' AS cancelado,
  -- valor_liquido é o número que a gold soma: zero quando cancelado,
  -- valor_total nos demais casos.
  CASE WHEN status = 'Cancelado' THEN CAST(0 AS DECIMAL(18,2))
       ELSE CAST(valor_total AS DECIMAL(18,2))
  END AS valor_liquido,
  year(coalesce(
    try_to_date(data_pedido, 'yyyy-MM-dd'),
    try_to_date(data_pedido, 'dd/MM/yyyy')
  )) AS ano,
  month(coalesce(
    try_to_date(data_pedido, 'yyyy-MM-dd'),
    try_to_date(data_pedido, 'dd/MM/yyyy')
  )) AS mes,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pedidos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pedidos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Pedidos com data corrigida (dois formatos na origem), valor tipado e
   cancelamento explícito. valor_liquido é o número correto para somar
   receita — nunca valor_total direto.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.cancelado IS
  'true quando status = Cancelado. Antes disso a única evidência era
   valor_total = 0, sem flag — fácil de confundir com pedido legítimo
   de valor baixo.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.valor_liquido IS
  'Zero quando cancelado, valor_total nos demais. É este campo, não
   valor_total, que soma para receita.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT data_pedido_preenchida CHECK (data_pedido IS NOT NULL);

-- ATENÇÃO: a regra intuitiva seria `valor_liquido >= 0`, e ela FALHA — 135
-- pedidos têm valor_liquido negativo porque contêm item devolvido, e o
-- saldo do pedido ficou negativo. É negócio legítimo, não sujeira. A
-- regra certa é: se está cancelado, o valor tem que ser exatamente zero.
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedido_cancelado_zerado CHECK (NOT cancelado OR valor_liquido = 0);
