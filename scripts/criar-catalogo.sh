#!/usr/bin/env bash
# Cria o catálogo com CREATE CATALOG IF NOT EXISTS, via SQL.
#
# POR QUE NÃO ESTÁ NO BUNDLE: no Free Edition o Default Storage está ligado,
# e nessa configuração a API do Unity Catalog RECUSA criar catálogo — ela
# exige um MANAGED LOCATION que a conta gratuita não tem:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL, via `databricks experimental aitools tools query`, funciona
# normalmente. Por isso o catálogo nasce aqui, fora do `databricks bundle
# deploy` — e precisa rodar ANTES dele, porque o deploy cria os schemas
# dentro deste catálogo.
#
# Uso: bash scripts/criar-catalogo.sh <profile>
set -euo pipefail

PROFILE="${1:?uso: bash scripts/criar-catalogo.sh <profile>}"

echo "CREATE CATALOG IF NOT EXISTS lakehouse_rotaperfume
  COMMENT 'Imersão Jornada de Dados — distribuidora Rota do Perfume';" \
  | databricks experimental aitools tools query --profile "$PROFILE"

echo "Catálogo lakehouse_rotaperfume pronto."
