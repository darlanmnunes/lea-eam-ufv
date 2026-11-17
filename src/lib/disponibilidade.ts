// Quantas unidades de cada modelo sobram num período, descontando
// empréstimos e as aulas práticas do semestre. Espelha reserva_aulas() do banco.
import { sobrepoe } from './datas'
import type { Aula, Horarios, Modelo, Ocupacao, Unidade } from './tipos'

const DIAS = ['', '', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb']

function dias(de: string, ate: string): string[] {
  const out: string[] = []
  const d = new Date(`${de}T12:00:00`)
  const fim = new Date(`${ate}T12:00:00`)
  for (let n = 0; d <= fim && n < 200; n++) {
    out.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`)
    d.setDate(d.getDate() + 1)
  }
  return out
}

/** dia da semana no padrão da DTI: 2 = segunda … 7 = sábado, 1 = domingo */
const diaDti = (iso: string) => new Date(`${iso}T12:00:00`).getDay() + 1

export interface AulaComUso extends Aula { quantidade: number; nome: string }

/** Aulas práticas que usam o modelo e caem dentro do período. */
export function aulasDoModelo(h: Horarios, modeloId: string, de: string, ate: string): AulaComUso[] {
  const usos = h.usos.filter((u) => u.modeloId === modeloId)
  if (!usos.length) return []
  const ds = dias(de, ate)
  const out = new Map<string, AulaComUso>()
  for (const s of h.semestres) {
    if (!s.inicio || !s.fim) continue
    const noSemestre = new Set(ds.filter((d) => d >= s.inicio! && d <= s.fim!).map(diaDti))
    if (!noSemestre.size) continue
    for (const a of h.aulas) {
      if (a.semestre !== s.id || a.tipo !== 'P' || !noSemestre.has(a.dia)) continue
      const uso = usos.find((u) => u.disciplina === a.disciplina)
      if (!uso) continue
      out.set(`${a.disciplina}/${a.turma}/${a.dia}/${a.inicio}`, {
        ...a, quantidade: uso.quantidade, nome: h.disciplinas.find((d) => d.codigo === a.disciplina)?.nome ?? '',
      })
    }
  }
  return [...out.values()].sort((a, b) => a.dia - b.dia || a.inicio - b.inicio)
}

/** Unidades do modelo tomadas por aula no pior horário do período. */
export function reservaAulas(h: Horarios, modeloId: string, de: string, ate: string): number {
  const porHora = new Map<string, number>()
  for (const a of aulasDoModelo(h, modeloId, de, ate)) {
    for (let hora = a.inicio; hora < a.fim; hora++) {
      const k = `${a.dia}-${hora}`
      porHora.set(k, (porHora.get(k) ?? 0) + a.quantidade)
    }
  }
  return Math.max(0, ...porHora.values())
}

export function textoAula(a: AulaComUso): string {
  return `${a.disciplina} · ${DIAS[a.dia]} ${a.inicio}h–${a.fim}h`
}

export type EstadoUnidade = 'livre' | 'aula' | 'emprestado' | 'manutencao' | 'estoque'

export const NOME_ESTADO: Record<EstadoUnidade, string> = {
  livre: 'Disponível',
  aula: 'Em aula',
  emprestado: 'Emprestado',
  manutencao: 'Em manutenção',
  estoque: 'Em estoque',
}

export interface Quadro {
  /** estado de cada unidade no período, na ordem do acervo */
  unidades: { unidade: Unidade; estado: EstadoUnidade; ate?: string }[]
  livres: Unidade[]
  aulas: AulaComUso[]
}

export function quadro(m: Modelo, oc: Ocupacao[], h: Horarios, de: string, ate: string): Quadro {
  const aulas = aulasDoModelo(h, m.id, de, ate)
  let emAula = reservaAulas(h, m.id, de, ate)
  const unidades = m.unidades.filter((u) => u.situacao !== 'baixado').map((unidade) => {
    if (unidade.situacao === 'manutencao') return { unidade, estado: 'manutencao' as const }
    if (unidade.situacao === 'estoque') return { unidade, estado: 'estoque' as const }
    const o = oc.find((x) => x.unidadeId === unidade.id && sobrepoe(x.de, x.ate, de, ate))
    if (o) return { unidade, estado: 'emprestado' as const, ate: o.ate }
    return { unidade, estado: 'livre' as EstadoUnidade }
  })
  // as aulas tomam as últimas unidades livres; as primeiras ficam para empréstimo
  for (let i = unidades.length - 1; i >= 0 && emAula > 0; i--) {
    if (unidades[i].estado === 'livre') { unidades[i].estado = 'aula'; emAula-- }
  }
  return { unidades, livres: unidades.filter((u) => u.estado === 'livre').map((u) => u.unidade), aulas }
}
