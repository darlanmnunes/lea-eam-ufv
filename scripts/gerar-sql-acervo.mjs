// Gera o SQL do acervo:
//   db/003_acervo.sql               a partir de src/dados/acervo.json (identificações de exemplo, vai para o git)
//   db/privado/003_acervo_real.sql  a partir de dados-fonte/privado/acervo.json (patrimônio e série reais, fora do git),
//                                   quando esse arquivo existe; numa instalação nova, rode-o no lugar do 003
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const q = (v) => (v == null ? 'null' : `'${String(v).replaceAll("'", "''")}'`)
const url = (p) => new URL(`../${p}`, import.meta.url)

function gerar(origem, destino, cabecalho) {
  const a = JSON.parse(readFileSync(url(origem)))
  let sql = `-- ${cabecalho} Gerado por scripts/gerar-sql-acervo.mjs; não editar à mão.\n\n`
  sql += 'insert into categorias (id, nome, sigla, ordem) values\n'
  sql += a.categorias.map((c) => `  (${q(c.id)}, ${q(c.nome)}, ${q(c.sigla)}, ${c.ordem})`).join(',\n') + ';\n\n'
  sql += 'insert into modelos (id, categoria_id, marca, nome, descricao, foto, emprestavel, ordem) values\n'
  sql += a.modelos.map((m, i) => `  (${q(m.id)}, ${q(m.categoria)}, ${q(m.marca)}, ${q(m.nome)}, ${q(m.descricao)}, ${q(m.foto)}, ${m.emprestavel !== false}, ${i + 1})`).join(',\n') + ';\n\n'
  sql += 'insert into unidades (modelo_id, patrimonio, numero_serie, situacao, observacao) values\n'
  sql += a.modelos.flatMap((m) => m.unidades.map((u) => `  (${q(m.id)}, ${q(u.patrimonio)}, ${q(u.serie)}, ${q(u.situacao ?? 'disponivel')}, ${q(u.obs)})`)).join(',\n') + ';\n'
  writeFileSync(url(destino), sql)
  console.log(`${destino} gerado`)
}

gerar('src/dados/acervo.json', 'db/003_acervo.sql',
  'Acervo inicial do LEA com identificações de exemplo (EX-001...). O inventário real, com patrimônio e série, fica em db/privado/003_acervo_real.sql, fora do git.')
if (existsSync(url('dados-fonte/privado/acervo.json'))) {
  mkdirSync(url('db/privado/'), { recursive: true })
  gerar('dados-fonte/privado/acervo.json', 'db/privado/003_acervo_real.sql', 'Acervo do LEA com patrimônio e número de série reais. NÃO publicar.')
}
