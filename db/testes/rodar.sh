#!/bin/sh
# Aplica o esquema num banco descartável e percorre o fluxo inteiro.
set -e
cd "$(dirname "$0")/.."
LEA_BANCO=lea_teste sh aplicar-local.sh >/dev/null
psql -q -v ON_ERROR_STOP=1 -d lea_teste -f testes/fluxo.sql
dropdb lea_teste
