// Lê o horário de aulas EAM publicado pela DTI/UFV e gera
// src/dados/horarios.json e db/004_horarios.sql.
// Uso: node scripts/importar-horarios.mjs 2026 1 2026 2
import { writeFileSync, readFileSync, existsSync } from 'node:fs'

const args = process.argv.slice(2)
const pares = []
for (let i = 0; i < args.length; i += 2) pares.push([Number(args[i]), Number(args[i + 1])])
if (!pares.length) pares.push([2026, 1], [2026, 2])

const limpa = (s) => s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim()

async function baixar(ano, semestre) {
  const local = process.env.DTI_DIR && `${process.env.DTI_DIR}/h${semestre}.html`
  if (local && existsSync(local)) return new TextDecoder('latin1').decode(readFileSync(local))
  const r = await fetch(`https://www.dti.ufv.br/horario/horario.asp?ano=${ano}&semestre=${semestre}&depto=EAM`)
  if (!r.ok) throw new Error(`DTI respondeu ${r.status}`)
  return new TextDecoder('latin1').decode(await r.arrayBuffer())
}

const disciplinas = new Map()
const aulas = []
const semestres = []

for (const [ano, semestre] of pares) {
  const html = await baixar(ano, semestre)
  const id = `${ano}-${semestre}`
  semestres.push({ id, ano, semestre })
  for (const tr of html.split(/<tr[^>]*>/i).slice(1)) {
    const tds = tr.split(/<td[^>]*>/i).slice(1).map((td) => td.split(/<\/td>/i)[0])
    if (tds.length < 6) continue
    const codigo = limpa(tds[0])
    if (!/^EAM \d{3}$/.test(codigo)) continue
    const nome = limpa(tds[1])
    const tipo = limpa(tds[2])
    const turma = Number(limpa(tds[3])) || 1
    const horarios = [...tds[4].matchAll(/(\d)=(\d{1,2})-(\d{1,2})/g)]
    const salas = tds[5].split(/<br\s*\/?>/i).map(limpa).filter(Boolean)
    disciplinas.set(codigo, nome)
    horarios.forEach((h, k) => {
      aulas.push({
        semestre: id, disciplina: codigo, tipo, turma,
        dia: Number(h[1]), inicio: Number(h[2]), fim: Number(h[3]),
        sala: salas[k] ?? salas[0] ?? null,
      })
    })
  }
}

const saida = {
  fonte: 'https://www.dti.ufv.br/horario/',
  semestres,
  disciplinas: [...disciplinas].sort().map(([codigo, nome]) => ({ codigo, nome })),
  aulas,
}
writeFileSync(new URL('../src/dados/horarios.json', import.meta.url), JSON.stringify(saida, null, 1))

const q = (v) => (v == null ? 'null' : `'${String(v).replaceAll("'", "''")}'`)
let sql = '-- Horário de aulas EAM (fonte: DTI/UFV). Gerado por scripts/importar-horarios.mjs.\n\n'
sql += 'insert into semestres (id, ano, semestre) values\n' + semestres.map((s) => `  (${q(s.id)}, ${s.ano}, ${s.semestre})`).join(',\n') + '\non conflict (id) do nothing;\n\n'
sql += 'insert into disciplinas (codigo, nome) values\n' + saida.disciplinas.map((d) => `  (${q(d.codigo)}, ${q(d.nome)})`).join(',\n') + '\non conflict (codigo) do update set nome = excluded.nome;\n\n'
sql += `delete from aulas where semestre_id in (${semestres.map((s) => q(s.id)).join(', ')});\n`
sql += 'insert into aulas (semestre_id, disciplina_codigo, tipo, turma, dia_semana, hora_inicio, hora_fim, sala) values\n'
sql += aulas.map((a) => `  (${q(a.semestre)}, ${q(a.disciplina)}, ${q(a.tipo)}, ${a.turma}, ${a.dia}, ${a.inicio}, ${a.fim}, ${q(a.sala)})`).join(',\n') + ';\n'
writeFileSync(new URL('../db/004_horarios.sql', import.meta.url), sql)
console.log(`${saida.disciplinas.length} disciplinas, ${aulas.length} horários (${aulas.filter((a) => a.tipo === 'P').length} de aula prática)`)
