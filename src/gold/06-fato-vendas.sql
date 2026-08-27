-- Gold · fato_vendas
--
-- CONTRATO (escrito antes do SQL, porque a granularidade se decide primeiro):
--   Granularidade : uma linha por ITEM de pedido
--   Filtro        : exclui pedido cancelado. NÃO exclui devolução.
--   Dimensões     : data_pedido, ano, mes, canal, cliente_id, razao_social,
--                    segmento, cidade, vendedor_id, sku, categoria, marca,
--                    nota_olfativa
--   Métricas      : quantidade, preco_praticado, receita, custo, margem,
--                    devolucao
--
-- POR QUE A DEVOLUÇÃO FICA DENTRO DO FATO: se ficasse de fora, este fato
-- somaria R$ 103,6 mi (o bruto vendido) enquanto a silver soma R$ 102,3 mi
-- (o líquido) — R$ 1,26 milhão de diferença entre duas camadas do MESMO
-- pipeline, o tipo de coisa que vira discussão de "qual sistema está
-- certo" numa reunião. A devolução entra com quantidade e receita
-- NEGATIVAS, marcada com devolucao = true. Quem quiser o bruto (sem
-- devolução) pede SUM(receita) FILTER (WHERE NOT devolucao).

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas (
  pedido_id       STRING,
  item_id         STRING,
  data_pedido     DATE,
  ano             INT,
  mes             INT,
  canal           STRING,
  cliente_id      STRING,
  razao_social    STRING,
  segmento        STRING,
  cidade          STRING,
  vendedor_id     STRING,
  sku             STRING,
  categoria       STRING,
  marca           STRING,
  nota_olfativa   STRING,
  quantidade      INT,
  preco_praticado DECIMAL(18,2),
  receita         DECIMAL(18,2),
  custo           DECIMAL(18,2),
  margem          DECIMAL(18,2),
  devolucao       BOOLEAN
)
PARTITIONED BY (ano, mes);

-- A deduplicação de clientes (silver/01-clientes.sql) manteve o cadastro
-- mais antigo e DESCARTOU até 40 cliente_id — mas pedidos antigos ainda
-- referenciam o id descartado. Um JOIN direto com silver.clientes perderia
-- essas linhas em silêncio. cliente_ids_duplicados existe exatamente para
-- isso: este mapa resolve qualquer cliente_id (sobrevivente ou descartado)
-- para o cadastro atual.
WITH mapa_cliente AS (
  SELECT cliente_id AS cliente_id_original, cliente_id AS cliente_id_resolvido
  FROM lakehouse_rotaperfume.silver.clientes
  UNION ALL
  SELECT explode(cliente_ids_duplicados) AS cliente_id_original, cliente_id AS cliente_id_resolvido
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
)
INSERT OVERWRITE lakehouse_rotaperfume.gold.fato_vendas
SELECT
  p.pedido_id,
  i.item_id,
  p.data_pedido,
  p.ano,
  p.mes,
  p.canal,
  c.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  p.vendedor_id,
  pr.sku,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  -- valor_bruto já é quantidade * preco_praticado, calculado uma vez na
  -- origem: reaproveitar em vez de recalcular garante que este número
  -- bate, centavo a centavo, com o valor_total que compõe silver.pedidos.
  i.valor_bruto                      AS receita,
  i.quantidade * pr.custo_unitario   AS custo,
  i.valor_bruto - (i.quantidade * pr.custo_unitario) AS margem,
  i.devolucao
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos  p  ON p.pedido_id = i.pedido_id
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
JOIN mapa_cliente m                           ON m.cliente_id_original = p.cliente_id
JOIN lakehouse_rotaperfume.silver.clientes c  ON c.cliente_id = m.cliente_id_resolvido
WHERE NOT p.cancelado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Uma linha por item de pedido, excluindo pedidos cancelados. A devolução
   fica DENTRO, com quantidade e receita negativas — é o que faz este fato
   conformar com silver.pedidos (R$ 102.303.828,05 nas duas camadas).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.pedido_id IS
  'Identificador do pedido. Um pedido tem várias linhas neste fato, uma
   por item.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.item_id IS
  'Identificador do item de pedido — a chave de linha deste fato.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.data_pedido IS
  'Data em que o pedido foi feito, já corrigida (dois formatos na
   origem).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.ano IS
  'Ano do pedido. Coluna de partição.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.mes IS
  'Mês do pedido, de 1 a 12. Coluna de partição. Lembre da sazonalidade
   invertida: o pico da distribuidora é o mês ANTERIOR à data
   comemorativa (abril, junho, outubro).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.canal IS
  'Canal pelo qual o pedido chegou: Visita, Telefone, App ou WhatsApp.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cliente_id IS
  'Cliente que comprou, já resolvido para o cadastro sobrevivente da
   deduplicação (não aponta para cliente_id descartado).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.razao_social IS
  'Nome do cliente.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.segmento IS
  'Tipo de varejo do cliente (perfumaria, farmácia, revendedora etc.).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cidade IS
  'Cidade do cliente.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.vendedor_id IS
  'Vendedor responsável pelo pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.sku IS
  'Produto vendido nesta linha.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.categoria IS
  'Categoria do produto (Eau de Parfum, Óleo Concentrado, Kit Presente
   etc.).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.marca IS
  'Marca do produto.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.nota_olfativa IS
  'Família olfativa do produto (Âmbar, Sândalo, Almíscar etc.).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.preco_praticado IS
  'Preço unitário efetivamente cobrado, já com desconto comercial
   aplicado.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.quantidade IS
  'Sinal preservado: negativa quando o item é devolução. Nunca use
   quantidade_abs aqui — é isso que mantém receita e quantidade
   consistentes na mesma linha.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.receita IS
  'quantidade * preco_praticado. Negativa nas linhas de devolução. Para o
   bruto vendido (sem devolução), filtre WHERE NOT devolucao.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.custo IS
  'quantidade * custo_unitario do produto (custo de reposição, não o
   contábil). Não considera frete nem imposto.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.margem IS
  'Receita menos custo do produto. Não considera desconto comercial nem
   frete — é margem de contribuição do item, não margem líquida.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.devolucao IS
  'true quando esta linha é uma devolução (quantidade negativa na
   origem). A linha fica no fato de propósito — ver comentário da tabela.';
