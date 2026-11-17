#!/bin/sh
# Recria o banco local "lea" e aplica o esquema. Uso: npm run db:local
set -e
cd "$(dirname "$0")"
BANCO="${LEA_BANCO:-lea}"
dropdb --if-exists "$BANCO"
createdb "$BANCO"
for f in 000_local_auth.sql 001_esquema.sql 002_regras.sql 003_acervo.sql 004_horarios.sql; do
  psql -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$f"
done
echo "Banco $BANCO pronto."
