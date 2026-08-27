-- Gold · auditoria de metadado
--
-- Metadado faltando é BUG, não pendência de documentação.
--
-- O agente de IA não lê o nome da coluna e adivinha o que ela significa. Ele
-- lê a DESCRIÇÃO e decide qual usar. Uma coluna `margem` sem comentário é
-- uma coluna que o Genie vai somar com frete, ou sem, e ninguém vai saber
-- qual dos dois ele fez.
--
-- Por isso este teste roda no pipeline, junto com os outros, e quebra igual.

-- ── Toda tabela e toda view da gold precisa de COMMENT ────────────────
SELECT 'metadado · tabelas e views da gold' AS teste,
       CAST(sem_comment AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment, ' objetos da gold estão sem COMMENT. O Genie vai errar neles.'))
       END AS resultado
FROM (SELECT count(*) AS sem_comment
      FROM lakehouse_rotaperfume.information_schema.tables
      WHERE table_schema = 'gold' AND (comment IS NULL OR trim(comment) = ''));

-- ── Toda coluna do fato e das views de negócio precisa de COMMENT ─────
-- As dimensões podem ter coluna autoexplicativa (cidade, uf). O fato e as
-- views são o que o agente lê primeiro, então neles a cobertura é total.
SELECT 'metadado · colunas do fato e das views' AS teste,
       CAST(sem_comment AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment, ' colunas sem COMMENT em fato_vendas ou nas views de negócio'))
       END AS resultado
FROM (SELECT count(*) AS sem_comment
      FROM lakehouse_rotaperfume.information_schema.columns
      WHERE table_schema = 'gold'
        AND table_name IN ('fato_vendas', 'receita_mensal', 'ranking_marcas',
                           'margem_por_categoria', 'clientes_em_risco',
                           'efeito_lancamento', 'ruptura_por_marca')
        AND (comment IS NULL OR trim(comment) = ''));

-- ── O relatório: quanto da gold está documentada ──────────────────────
-- Não quebra nada. Serve para a conversa com quem vai consumir.
SELECT table_name AS objeto,
       count(*) AS colunas,
       sum(CASE WHEN comment IS NOT NULL AND trim(comment) <> '' THEN 1 ELSE 0 END) AS documentadas,
       round(avg(CASE WHEN comment IS NOT NULL AND trim(comment) <> '' THEN 1.0 ELSE 0.0 END), 2) AS cobertura
FROM lakehouse_rotaperfume.information_schema.columns
WHERE table_schema = 'gold'
GROUP BY table_name
ORDER BY cobertura, table_name;
