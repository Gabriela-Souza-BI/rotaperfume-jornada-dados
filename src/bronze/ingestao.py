# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão bronze
# MAGIC
# MAGIC Lê os 10 CSVs do Volume e grava cada um como tabela Delta. **Nenhuma
# MAGIC limpeza, nenhuma conversão de tipo.** Tudo entra como texto, de
# MAGIC propósito: se o Spark adivinhasse o tipo, `15/10/2025` viraria nulo e os
# MAGIC 309 CNPJs com zero à esquerda perderiam o zero — a sujeira sumiria antes
# MAGIC de alguém ver que ela existiu. Converter é trabalho da silver, feito
# MAGIC sabendo o que se faz.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import datetime, timezone
from pyspark.sql import functions as F

TABELAS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

RAW_ROOT = f"/Volumes/{catalog}/bronze/raw"

COMENTARIO = {
    "produtos": "ERP · catálogo de produtos, categoria, marca e custo.",
    "pedidos": "ERP · a tabela fato: cliente, vendedor, data, canal, status e valor.",
    "itens_pedido": "ERP · uma linha por produto vendido dentro de um pedido.",
    "pagamentos": "ERP · forma de pagamento, parcelas e status por pedido.",
    "estoque": "ERP · snapshot semanal de saldo por SKU.",
    "clientes": "CRM · cadastro de clientes: CNPJ, razão social, segmento e cidade.",
    "vendedores": "CRM · cadastro de vendedores: região, admissão e desligamento.",
    "carteira": "CRM · vínculo entre vendedor e cliente, com vigência.",
    "oportunidades": "CRM · funil de vendas: origem, etapa, valor e motivo de perda.",
    "visitas": "CRM · registro de visitas: data, resultado e duração.",
}

# COMMAND ----------

def ingerir(sistema: str, tabela: str) -> int:
    """Lê um CSV do Volume raw e grava como Delta na bronze, tudo texto.

    Retorna o número de linhas gravadas.
    """
    caminho = f"{RAW_ROOT}/{sistema}/{tabela}.csv"

    # inferSchema desligado de propósito: CNPJ e data têm que chegar como
    # texto, senão a sujeira (zero à esquerda, data em dois formatos) some
    # antes da silver poder tratar. Os CSVs são CRLF com header — sem
    # multiLine, que juntaria linhas de arquivos que não têm campo multilinha.
    df = (
        spark.read.format("csv")
        .option("header", "true")
        .option("inferSchema", "false")
        .option("multiLine", "false")
        .load(caminho)
    )

    # o leitor de arquivo do Databricks injeta _rescued_data sozinho;
    # descartamos em vez de desligar (rescuedDataColumn => '' cria uma
    # coluna de nome vazio e o CREATE TABLE quebra).
    if "_rescued_data" in df.columns:
        df = df.drop("_rescued_data")

    df = df.withColumn("_ingerido_em", F.current_timestamp()).withColumn(
        "_arquivo_origem", F.lit(f"{tabela}.csv")
    )

    destino = f"{catalog}.bronze.{tabela}"
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(destino)
    spark.sql(f"COMMENT ON TABLE {destino} IS '{COMENTARIO[tabela]}'")

    return df.count()

# COMMAND ----------

resultados = []
for sistema, tabelas in TABELAS.items():
    for tabela in tabelas:
        linhas = ingerir(sistema, tabela)
        resultados.append({"tabela": tabela, "linhas_bronze": linhas})

# COMMAND ----------

# MAGIC %md ## Conferência: linhas da bronze vs. linhas do arquivo (prompt 1)

# COMMAND ----------

raw_arquivos = spark.table(f"{catalog}.bronze._raw_arquivos").select(
    F.regexp_replace("arquivo", r"\.csv$", "").alias("tabela"),
    F.col("linhas").alias("linhas_arquivo"),
)

conferencia = spark.createDataFrame(resultados).join(raw_arquivos, "tabela")
conferencia = conferencia.withColumn(
    "bate", F.col("linhas_bronze") == F.col("linhas_arquivo")
)

conferencia.orderBy(F.desc("linhas_bronze")).show(n=20, truncate=False)

divergentes = conferencia.filter(~F.col("bate")).collect()
if divergentes:
    raise Exception(
        "Contagem divergente entre bronze e raw:\n"
        + "\n".join(f"  - {r['tabela']}: bronze={r['linhas_bronze']} arquivo={r['linhas_arquivo']}" for r in divergentes)
    )

total = sum(r["linhas_bronze"] for r in resultados)
print(f"10 tabelas ingeridas, {total} linhas no total — todas batendo com o raw.")
