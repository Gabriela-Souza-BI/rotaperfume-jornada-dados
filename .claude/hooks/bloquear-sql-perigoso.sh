#!/usr/bin/env bash
# PreToolUse hook — bloqueia DROP, TRUNCATE e DELETE sem WHERE em qualquer
# comando Bash. É determinístico: skill e MCP dependem do modelo entender o
# contexto, o hook não depende de nada. Se bloqueia, bloqueia sempre.
#
# Recebe no stdin um JSON com o tool call. Ver:
# https://docs.claude.com/en/docs/claude-code/hooks
set -euo pipefail

entrada="$(cat)"
comando="$(echo "$entrada" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)"

bloquear() {
  echo "{\"decision\": \"block\", \"reason\": \"$1\"}"
  exit 0
}

if echo "$comando" | grep -qiE '\b(drop|truncate)\b'; then
  bloquear "Comando contém DROP ou TRUNCATE. Bloqueado pelo guard rail do projeto — peça confirmação explícita fora do agente antes de rodar isso."
fi

if echo "$comando" | grep -qiE '\bdelete\b' && ! echo "$comando" | grep -qiE '\bwhere\b'; then
  bloquear "Comando contém DELETE sem WHERE. Bloqueado pelo guard rail do projeto — um DELETE sem WHERE apaga a tabela inteira."
fi

exit 0
