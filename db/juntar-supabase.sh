#!/bin/sh
# Junta os scripts num arquivo só, para colar no SQL Editor do Supabase.
cd "$(dirname "$0")"
{ echo "-- Acervo do LEA | esquema completo para o Supabase (gerado por db/juntar-supabase.sh)"
  for f in 001_esquema.sql 002_regras.sql 003_acervo.sql 004_horarios.sql; do printf '\n-- ===== %s =====\n' "$f"; cat "$f"; done
} > supabase_completo.sql
echo "db/supabase_completo.sql gerado"
