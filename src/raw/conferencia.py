# Databricks notebook source
# MAGIC %md
# MAGIC # Conferência de chegada
# MAGIC
# MAGIC O erro mais caro de pipeline não é o que quebra — é o arquivo que não
# MAGIC chegou e ninguém viu. Ele não dá erro: dá número menor, e o dashboard
# MAGIC mostra metade da receita com cara de número certo.
# MAGIC
# MAGIC Esta tarefa confere que os 10 CSVs esperados chegaram ao Volume, com
# MAGIC linhas de dado de verdade (não só o arquivo existir vazio), e grava o
# MAGIC resultado em `bronze._raw_arquivos`. Se faltar algo, interrompe o job.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import datetime, timezone

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

RAW_ROOT = f"/Volumes/{catalog}/bronze/raw"

# COMMAND ----------

registros = []
faltando = []

for sistema, tabelas in ARQUIVOS_ESPERADOS.items():
    for tabela in tabelas:
        caminho = f"{RAW_ROOT}/{sistema}/{tabela}.csv"
        try:
            info = dbutils.fs.ls(caminho)[0]
        except Exception:
            faltando.append(caminho)
            continue

        # -1 para descontar o cabeçalho: queremos linhas de DADO, não de arquivo.
        linhas = spark.read.text(caminho).count() - 1

        if linhas <= 0:
            faltando.append(f"{caminho} (chegou vazio)")
            continue

        registros.append(
            {
                "sistema": sistema,
                "arquivo": f"{tabela}.csv",
                "bytes": info.size,
                "linhas": linhas,
                "conferido_em": datetime.now(timezone.utc),
            }
        )

if faltando:
    raise Exception(
        "Conferência de chegada FALHOU. Arquivo(s) ausente(s) ou vazio(s):\n"
        + "\n".join(f"  - {f}" for f in faltando)
    )

# COMMAND ----------

df = spark.createDataFrame(registros)

(
    df.write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(f"{catalog}.bronze._raw_arquivos")
)

spark.sql(f"""
    COMMENT ON TABLE {catalog}.bronze._raw_arquivos IS
    'Conferência de chegada: um registro por arquivo raw esperado, com
     tamanho, contagem de linhas e horário da conferência. Se um arquivo
     não aparece aqui, ele não chegou — e a tarefa já teria interrompido
     o job antes de gravar.'
""")

# COMMAND ----------

# MAGIC %md ## Resultado

# COMMAND ----------

resultado = spark.table(f"{catalog}.bronze._raw_arquivos").orderBy(
    "sistema", "arquivo"
)
resultado.show(n=20, truncate=False)

total_arquivos = resultado.count()
total_linhas = sum(r["linhas"] for r in registros)
print(f"{total_arquivos} arquivos conferidos, {total_linhas} linhas de dado no total.")
