import { type CSSProperties, type ReactNode } from 'react'
import { NOME_ESTADO, type EstadoUnidade, type Quadro } from '../lib/disponibilidade'
import { NOME_STATUS, TOM_STATUS } from '../lib/fluxo'
import type { Modelo, Status } from '../lib/tipos'

export function Selo({ status }: { status: Status }) {
  return <span className={`selo selo-${TOM_STATUS[status]}`}>{NOME_STATUS[status]}</span>
}

const MAX_MARCAS = 12

/** Uma marca por unidade do modelo: cheia = livre, hachurada = em aula, vazada = fora. */
export function Marcas({ q }: { q: Quadro }) {
  const conta: Partial<Record<EstadoUnidade, number>> = {}
  q.unidades.forEach((u) => { conta[u.estado] = (conta[u.estado] ?? 0) + 1 })
  const rotulo = (Object.keys(conta) as EstadoUnidade[]).map((e) => `${conta[e]} ${NOME_ESTADO[e].toLowerCase()}`).join(', ')
  return (
    <span className="marcas" role="img" aria-label={rotulo} title={rotulo}>
      {q.unidades.slice(0, MAX_MARCAS).map((u, i) => <i key={u.unidade.id} className={`marca marca-${u.estado}`} style={{ '--i': i } as CSSProperties} />)}
      {q.unidades.length > MAX_MARCAS && <span className="marcas-mais" aria-hidden="true">+{q.unidades.length - MAX_MARCAS}</span>}
    </span>
  )
}

export function Foto({ m, grande }: { m: Modelo; grande?: boolean }) {
  if (!m.foto) {
    return <div className={`foto foto-vazia${grande ? ' foto-grande' : ''}`} aria-hidden="true"><span>{m.marca}</span><b>{m.nome}</b></div>
  }
  const src = /^(https?:|data:)/.test(m.foto) ? m.foto : `./equip/${m.foto}`
  return <div className={`foto${grande ? ' foto-grande' : ''}`}><img src={src} alt={`${m.marca} ${m.nome}`} loading="lazy" /></div>
}

export function Campo({ rotulo, ajuda, erro, children, largo }: { rotulo: string; ajuda?: string; erro?: string | null; children: ReactNode; largo?: boolean }) {
  return (
    <label className={`campo${largo ? ' campo-largo' : ''}${erro ? ' campo-erro' : ''}`}>
      <span className="campo-rotulo">{rotulo}</span>
      {children}
      {erro ? <span className="campo-msg" role="alert">{erro}</span> : ajuda ? <span className="campo-ajuda">{ajuda}</span> : null}
    </label>
  )
}

export function Vazio({ titulo, children }: { titulo: string; children?: ReactNode }) {
  return <div className="vazio"><p className="vazio-titulo">{titulo}</p>{children}</div>
}

export function Cabecalho({ sobre, titulo, children }: { sobre?: string; titulo: string; children?: ReactNode }) {
  return (
    <header className="cab">
      <div>
        {sobre && <p className="cab-sobre">{sobre}</p>}
        <h1>{titulo}</h1>
      </div>
      {children && <div className="cab-acoes">{children}</div>}
    </header>
  )
}
