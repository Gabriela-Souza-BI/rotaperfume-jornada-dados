#!/usr/bin/env bash
# Sobe os CSVs de dados/erp e dados/crm (na raiz do repositório) para o
# Volume do Unity Catalog. Rode DEPOIS do `databricks bundle deploy` — o
# Volume só existe a partir daí.
#
# Uso: bash scripts/subir-raw.sh <profile>
set -euo pipefail

PROFILE="${1:?uso: bash scripts/subir-raw.sh <profile>}"
CATALOG="lakehouse_rotaperfume"

# .../rotaperfume -> .../ClaudeAnalises, onde vive a pasta dados/
RAIZ_DO_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DADOS="$RAIZ_DO_REPO/dados"

if [ ! -d "$DADOS" ]; then
  echo "dados/ não encontrado em $DADOS — gere antes com:"
  echo "  python material/gerar_dataset.py --saida ./dados --seed 42"
  exit 1
fi

# databricks fs cp exige o esquema dbfs:, mesmo para Volume do Unity Catalog.
databricks fs cp --recursive --overwrite "$DADOS/erp" \
  "dbfs:/Volumes/$CATALOG/bronze/raw/erp" --profile "$PROFILE"
databricks fs cp --recursive --overwrite "$DADOS/crm" \
  "dbfs:/Volumes/$CATALOG/bronze/raw/crm" --profile "$PROFILE"

echo "CSVs no Volume: /Volumes/$CATALOG/bronze/raw/{erp,crm}"
