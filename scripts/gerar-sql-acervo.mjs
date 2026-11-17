// Gera db/003_acervo.sql a partir de src/dados/acervo.json.
import { readFileSync, writeFileSync } from 'node:fs'
const a = JSON.parse(readFileSync(new URL('../src/dados/acervo.json', import.meta.url)))
const q = (v) => (v == null ? 'null' : `'${String(v).replaceAll("'", "''")}'`)
let sql = '-- Acervo inicial do LEA. Gerado por scripts/gerar-sql-acervo.mjs; não editar à mão.\n\n'
sql += 'insert into categorias (id, nome, sigla, ordem) values\n'
sql += a.categorias.map((c) => `  (${q(c.id)}, ${q(c.nome)}, ${q(c.sigla)}, ${c.ordem})`).join(',\n') + ';\n\n'
sql += 'insert into modelos (id, categoria_id, marca, nome, descricao, foto, ordem) values\n'
sql += a.modelos.map((m, i) => `  (${q(m.id)}, ${q(m.categoria)}, ${q(m.marca)}, ${q(m.nome)}, ${q(m.descricao)}, ${q(m.foto)}, ${i + 1})`).join(',\n') + ';\n\n'
sql += 'insert into unidades (modelo_id, patrimonio, numero_serie, observacao) values\n'
sql += a.modelos.flatMap((m) => m.unidades.map((u) => `  (${q(m.id)}, ${q(u.patrimonio)}, ${q(u.serie)}, ${q(u.obs)})`)).join(',\n') + ';\n'
writeFileSync(new URL('../db/003_acervo.sql', import.meta.url), sql)
console.log('db/003_acervo.sql gerado')
