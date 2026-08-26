-- Silver · vendedores, carteira, oportunidades, visitas, pagamentos, estoque

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  try_to_date(data_admissao, 'yyyy-MM-dd') AS data_admissao,
  try_to_date(data_desligamento, 'yyyy-MM-dd') AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18,2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Cadastro de vendedores tipado. data_desligamento nula = vendedor ativo.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
SELECT
  c.carteira_id,
  c.cliente_id,
  c.vendedor_id,
  try_to_date(c.data_inicio, 'yyyy-MM-dd') AS data_inicio,
  try_to_date(c.data_fim, 'yyyy-MM-dd') AS data_fim,
  -- vigente respeita as DUAS pontas: o vínculo não pode ter sido encerrado
  -- (data_fim NULL = nunca fechado) E o vendedor não pode ter sido
  -- desligado.
  try_to_date(c.data_fim, 'yyyy-MM-dd') IS NULL
    AND v.data_desligamento IS NULL AS vigente,
  -- NÃO consertamos o dado: existe vendedor desligado cuja carteira nunca
  -- foi fechada (data_fim NULL). Esta coluna EXPÕE o problema para o
  -- gestor, em vez de escondê-lo silenciosamente numa regra de negócio.
  try_to_date(c.data_fim, 'yyyy-MM-dd') IS NULL
    AND v.data_desligamento IS NOT NULL
    AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.carteira) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.carteira c
LEFT JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = c.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Vínculo cliente-vendedor com vigência calculada. orfao_vendedor_desligado
   expõe vínculos ainda vigentes de vendedores já desligados — não corrige,
   só sinaliza para o gestor decidir.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.orfao_vendedor_desligado IS
  'true quando a carteira segue vigente por data_fim, mas o vendedor já
   foi desligado. Problema real do dado de origem, mantido visível.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
SELECT
  oportunidade_id,
  cliente_id,
  vendedor_id,
  origem,
  try_to_date(data_abertura, 'yyyy-MM-dd') AS data_abertura,
  etapa,
  -- as etapas na origem são 'Fechado ganho' / 'Fechado perdido' — não
  -- 'Ganha' / 'Perdida'. Conferido com SELECT DISTINCT etapa antes de
  -- escrever este CASE.
  etapa = 'Fechado ganho' AS ganha,
  etapa = 'Fechado perdido' AS perdida,
  CAST(probabilidade_pct AS DECIMAL(9,4)) AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18,2)) AS valor_estimado,
  try_to_date(data_fechamento, 'yyyy-MM-dd') AS data_fechamento,
  CAST(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.oportunidades) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Funil comercial tipado. ganha/perdida derivados de etapa = Fechado
   ganho / Fechado perdido — os nomes exatos usados na origem.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
SELECT
  visita_id,
  cliente_id,
  vendedor_id,
  try_to_date(data_visita, 'yyyy-MM-dd') AS data_visita,
  resultado,
  CAST(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.visitas) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Registro de visitas comerciais, tipado.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
SELECT
  pagamento_id,
  pedido_id,
  forma_pagamento,
  CAST(parcelas AS INT) AS parcelas,
  CAST(valor AS DECIMAL(18,2)) AS valor,
  CAST(taxa_pct AS DECIMAL(9,4)) AS taxa_pct,
  CAST(valor_liquido AS DECIMAL(18,2)) AS valor_liquido,
  try_to_date(data_vencimento, 'yyyy-MM-dd') AS data_vencimento,
  try_to_date(data_pagamento, 'yyyy-MM-dd') AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pagamentos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Pagamentos por pedido, tipado.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
SELECT
  try_to_date(data_snapshot, 'yyyy-MM-dd') AS data_snapshot,
  sku,
  CAST(saldo AS INT) AS saldo,
  ruptura = 'S' AS ruptura,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.estoque) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque;

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Snapshot semanal de estoque por SKU, com ruptura em boolean.';
