# rotaperfume-jornada-dados

📚 **About this project:** This is a course-guided project ([Imersão Jornada de Dados](https://github.com/lvgalvao/projeto-dados-ia-databricks)), built to apply Databricks concepts in practice — medallion architecture, data quality contracts, business views, metadata auditing, and Genie Space — while also exploring Claude Code as a daily development tool. It's my first hands-on project in this area; the content follows course instructions and is not fully solo-authored. Future projects will be developed independently.

## What this project does

This is a data pipeline built on Databricks that simulates the data journey of **Rota do Perfume**, a fictional B2B distributor of Arabic perfumery selling to perfume shops, pharmacies, resellers, and e-commerces. It ingests raw ERP and CRM data (~313k rows across 10 source files), transforms it into clean, reliable tables, and models it into business-facing views. Along the way it also covers metadata auditing (making sure every table and column is documented well enough for a person — or an AI agent — to use it correctly) and a Genie Space setup for natural-language querying over the data.

The goal wasn't just to move data from point A to B, but to go through the full journey a real analytics engineering project involves: raw ingestion, transformation, validation, documentation, and finally making the data usable for business questions — in SQL, in a dashboard, and in plain language.

## Architecture

The pipeline follows the **medallion architecture**, all inside one Unity Catalog catalog (`lakehouse_rotaperfume`), built and deployed as a single [Databricks Asset Bundle](https://docs.databricks.com/dev-tools/bundles/index.html):

```
raw (Volume)         10 CSVs, exactly as they left the source systems
   ↓
bronze (10 tables)   Delta, everything read as text — no cleaning, no type
                      inference. The bronze layer keeps the mess on purpose:
                      it's proof of what the source system actually sent.
   ↓
silver (10 tables)   Cleaned, deduplicated, typed. 5 CHECK constraints
                      declared on the tables themselves (not just in a
                      script). CNPJ normalized to 14 digits, 40 duplicate
                      customer records merged (3,040 → 3,000), returns
                      flagged instead of discarded, cancelled orders
                      made explicit.
   ↓
gold                 4 conformed dimensions, one fact table
                      (fato_vendas — 191,080 rows, one per order line),
                      3 department-specific marts, and 6 views named the
                      way a business person would ask for them
                      (ranking_marcas, clientes_em_risco, ...).
```

Everything is orchestrated by a single Databricks Job (`rotaperfume_pipeline`), 12 tasks, scheduled daily:

```
raw_conferencia → bronze_ingestao → silver ×4 (parallel)
  → gold_dimensoes → gold_fato_vendas → gold_marts
      → testes (9 data-quality checks)
      → metricas_de_negocio → auditoria_de_metadado (2 metadata checks)
```

11 checks run inside the pipeline and **break the job on failure** — a check that doesn't stop the pipeline is a report, not a test. The one that matters most: cleaning is not allowed to change total revenue. Every layer, from silver through the two independent marts, reconciles to the same **R$ 102,303,828.05**.

On top of the gold layer:
- An **AI/BI dashboard**, defined as JSON and versioned inside the bundle (not built by clicking in the UI) — deploys and rolls back with `git`.
- A **Genie Space** for natural-language Q&A, also versioned as code, with written business instructions (e.g., the distributor's seasonality is inverted — retailers restock the month *before* a holiday, so December and January are an expected low, not a bad month).

## Tech stack

- **Databricks Free Edition** (serverless) — no managed cluster, everything runs on-demand
- **Databricks Asset Bundles (DABs)** — the whole project (catalog, schemas, jobs, dashboard, Genie Space) is defined as YAML/JSON and deployed with `databricks bundle deploy`
- **Delta Lake + Unity Catalog** — storage and governance, including declared CHECK constraints
- **SQL** for transformation (`sql_task`), **PySpark notebooks** for file-handling steps (raw arrival check, bronze ingestion)
- **Claude Code** as the development tool for the whole build
- **uv** for Python dependency management
- **Git + GitHub** for version control

## Project structure

```
databricks.yml               Bundle definition — targets (dev/prod), variables (catalog, warehouse_id)
scripts/
  criar-catalogo.sh          Creates the catalog via SQL (the Unity Catalog API can't, on Free Edition)
  subir-raw.sh               Uploads the source CSVs to the Volume
resources/
  catalogo.yml                Schemas (bronze/silver/gold) and the raw Volume, as code
  pipeline.job.yml            The 12-task job definition
  dashboard.dashboard.yml + dashboard-comercial.lvdash.json   The AI/BI dashboard
  genie.genie_space.yml + comercial.geniespace.json           The Genie Space
src/
  raw/conferencia.py          Notebook: did all 10 files arrive, with real rows?
  bronze/ingestao.py          Notebook: CSV → Delta, nothing cleaned
  silver/01..04*.sql          sql_task: the actual cleaning, with CHECK constraints
  gold/05..10*.sql            sql_task: dimensions, fact, marts, quality tests, business views, metadata audit
docs/
  genie-instrucoes.md         The business rules given to the Genie Space, in plain text
.claude/
  settings.json + hooks/      Guard rails: deny destructive commands, block DROP/TRUNCATE/unfiltered DELETE
tests/                        Unit tests for the shared Python code
fixtures/                     Fixtures for data sets (primarily used for testing)
```

## How to run

```bash
databricks auth login --host <your-workspace-url> --profile <your-profile>

bash scripts/criar-catalogo.sh <profile>                                  # catalog first — the deploy needs it to exist
databricks bundle validate --target dev --profile <profile>
databricks bundle deploy   --target dev --profile <profile>
bash scripts/subir-raw.sh  <profile>                                      # after deploy — needs the Volume to exist
databricks bundle run rotaperfume_pipeline --target dev --profile <profile>
databricks bundle summary  --target dev --profile <profile>               # prints the dashboard and Genie Space URLs
```

## Results

| Metric | Value |
|---|---|
| Total revenue (24 months), reconciled across every layer | R$ 102,303,828.05 |
| Rows in `gold.fato_vendas` | 191,080 |
| Unique customers after deduplication | 3,000 (from 3,040 raw records) |
| Returns kept and flagged (never discarded) | 2,327 line items |
| At-risk customers (90+ days without an order) | 503 · ~R$ 836k/month of stalled revenue |
| Data-quality + metadata checks enforced in the pipeline | 11, all breaking the job on failure |

## Problems solved along the way

A few real bugs came up while building this — worth listing, because finding and fixing them was most of the actual learning:

- **Orphaned foreign keys after deduplication.** Merging 40 duplicate customer records meant some `cliente_id` values stopped existing — but older orders still pointed at the discarded ID. A direct `JOIN` to the cleaned customer table silently dropped those orders (191,080 rows became 190,927, revenue was short by ~R$71k). Fixed by keeping a `cliente_ids_duplicados` map and resolving every order's customer ID through it before joining.
- **A `current_date()` bug in a static dataset.** A vigency rule compared against the live current date instead of the dataset's fixed reference date, so the answer changed depending on which day you ran the pipeline. Silent and easy to miss — caught because a count was off by one.
- **Lakeview "circular reference" error.** A dashboard dataset selected a raw column (`receita`) and also declared a calculated metric with the same display name (`Receita`) — since SQL is case-insensitive, the metric's `SUM()` ended up referencing itself. Fixed by aliasing the raw columns.
- **Genie Space bootstrap ordering.** The Genie Space definition references business views that don't exist until the pipeline has run once — so on a brand-new project, deploying everything in one shot fails. Solved by deploying without the Genie Space first, running the pipeline once, then deploying the Genie Space.
- **Free Edition can't create a catalog through the Bundle API.** Unity Catalog's `CREATE CATALOG` endpoint requires a managed storage location the free tier doesn't have — so the catalog is created via a plain SQL script, before the bundle deploy.

## Acknowledgments

Built as part of [Imersão Jornada de Dados](https://github.com/lvgalvao/projeto-dados-ia-databricks) — full credit to the course material, dataset design, and the six-prompt structure this project follows. This repository is my own build-along, with the bugs above being the parts I ran into and solved myself.
