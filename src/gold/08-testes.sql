-- Gold · testes de qualidade
-- Cada teste levanta raise_error() dentro de um CASE WHEN quando falha —
-- isso INTERROMPE a tarefa e o job para. Teste que não quebra o job não é
-- teste, é relatório: o dashboard ficaria com número errado e cara de
-- certo. Se um teste falhar, corrija a TRANSFORMAÇÃO, nunca o teste.

-- 1 · O teste que mais importa: limpeza não pode mudar o faturamento.
SELECT
  '1. receita gold = receita silver' AS teste,
  ROUND(SUM(receita), 2) AS valor_calculado,
  (SELECT ROUND(SUM(valor_liquido), 2) FROM lakehouse_rotaperfume.silver.pedidos) AS valor_esperado,
  CASE WHEN abs(
      SUM(receita) - (SELECT SUM(valor_liquido) FROM lakehouse_rotaperfume.silver.pedidos)
    ) <= 0.01
    THEN 'PASSOU'
    ELSE raise_error('Teste 1 FALHOU: receita da gold diverge da silver em mais de R$ 0,01')
  END AS resultado
FROM lakehouse_rotaperfume.gold.fato_vendas;

-- 2 · Nenhum CNPJ duplicado na silver.clientes.
SELECT
  '2. CNPJ único em silver.clientes' AS teste,
  COUNT(*) - COUNT(DISTINCT cnpj) AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) = COUNT(DISTINCT cnpj)
    THEN 'PASSOU'
    ELSE raise_error('Teste 2 FALHOU: existe CNPJ duplicado em silver.clientes')
  END AS resultado
FROM lakehouse_rotaperfume.silver.clientes;

-- 3 · Nenhuma data_pedido nula na silver.pedidos.
SELECT
  '3. data_pedido sem nulo' AS teste,
  COUNT(*) FILTER (WHERE data_pedido IS NULL) AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) FILTER (WHERE data_pedido IS NULL) = 0
    THEN 'PASSOU'
    ELSE raise_error('Teste 3 FALHOU: existe data_pedido nula em silver.pedidos')
  END AS resultado
FROM lakehouse_rotaperfume.silver.pedidos;

-- 4 · Receita negativa só pode existir em linha marcada como devolução.
SELECT
  '4. receita negativa só em devolução' AS teste,
  COUNT(*) FILTER (WHERE receita < 0 AND NOT devolucao) AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) FILTER (WHERE receita < 0 AND NOT devolucao) = 0
    THEN 'PASSOU'
    ELSE raise_error('Teste 4 FALHOU: existe receita negativa fora de linha de devolução')
  END AS resultado
FROM lakehouse_rotaperfume.gold.fato_vendas;

-- 5 · Volume do fato dentro da faixa esperada — pega JOIN que duplicou
-- linha (muito alto) ou filtro que descartou item de propósito (muito
-- baixo).
SELECT
  '5. volume de fato_vendas na faixa' AS teste,
  COUNT(*) AS valor_calculado,
  '140000-250000' AS valor_esperado,
  CASE WHEN COUNT(*) BETWEEN 140000 AND 250000
    THEN 'PASSOU'
    ELSE raise_error('Teste 5 FALHOU: fato_vendas fora da faixa 140.000-250.000 linhas')
  END AS resultado
FROM lakehouse_rotaperfume.gold.fato_vendas;

-- 6 · Nenhum pedido_id no fato que não exista na silver — prova de que o
-- JOIN não inventou linha.
SELECT
  '6. pedido_id do fato existe na silver' AS teste,
  COUNT(*) AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) = 0
    THEN 'PASSOU'
    ELSE raise_error('Teste 6 FALHOU: existe pedido_id no fato ausente em silver.pedidos')
  END AS resultado
FROM (
  SELECT DISTINCT f.pedido_id
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT ANTI JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
);

-- 7 · Nenhum cliente_id no fato que não exista na silver.
SELECT
  '7. cliente_id do fato existe na silver' AS teste,
  COUNT(*) AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) = 0
    THEN 'PASSOU'
    ELSE raise_error('Teste 7 FALHOU: existe cliente_id no fato ausente em silver.clientes')
  END AS resultado
FROM (
  SELECT DISTINCT f.cliente_id
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT ANTI JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
);

-- 8 · Conformado: mart_produto_performance tem que somar o mesmo que
-- fato_vendas — é a prova de que "conformado" não é só uma palavra.
SELECT
  '8. mart_produto_performance conforma com fato' AS teste,
  ROUND((SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.mart_produto_performance), 2) AS valor_calculado,
  ROUND((SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas), 2) AS valor_esperado,
  CASE WHEN abs(
      (SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.mart_produto_performance)
      - (SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas)
    ) <= 0.01
    THEN 'PASSOU'
    ELSE raise_error('Teste 8 FALHOU: mart_produto_performance não conforma com fato_vendas')
  END AS resultado;

-- 9 · Todo CNPJ com exatamente 14 dígitos numéricos.
SELECT
  '9. CNPJ com 14 dígitos' AS teste,
  COUNT(*) FILTER (WHERE length(cnpj) <> 14 OR cnpj RLIKE '[^0-9]') AS valor_calculado,
  0 AS valor_esperado,
  CASE WHEN COUNT(*) FILTER (WHERE length(cnpj) <> 14 OR cnpj RLIKE '[^0-9]') = 0
    THEN 'PASSOU'
    ELSE raise_error('Teste 9 FALHOU: existe CNPJ sem 14 dígitos numéricos em silver.clientes')
  END AS resultado
FROM lakehouse_rotaperfume.silver.clientes;
