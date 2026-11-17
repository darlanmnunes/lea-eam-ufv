import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { api } from './lib/api'
import { hoje } from './lib/datas'
import type { Acervo, Categoria, Horarios, Modelo, Ocupacao, Pessoa, Unidade } from './lib/tipos'

export interface Cesta { de: string; ate: string; itens: string[] }

interface Lea {
  pronto: boolean
  eu: Pessoa | null
  acervo: Acervo
  ocupacao: Ocupacao[]
  horarios: Horarios
  cesta: Cesta
  definirCesta(c: Cesta): void
  recarregar(): Promise<void>
  unidade(id: string): { unidade: Unidade; modelo: Modelo; categoria: Categoria } | null
  avisar(texto: string, tom?: 'ok' | 'erro'): void
}

const Ctx = createContext<Lea | null>(null)
export const useLea = () => useContext(Ctx)!

const CHAVE_CESTA = 'lea-ficha'
const cestaInicial = (): Cesta => {
  try {
    const c = JSON.parse(sessionStorage.getItem(CHAVE_CESTA) ?? 'null') as Cesta | null
    if (c && c.de >= hoje()) return c
  } catch { /* segue com a ficha vazia */ }
  return { de: hoje(1), ate: hoje(1), itens: [] }
}

export function Provedor({ children }: { children: ReactNode }) {
  const [pronto, setPronto] = useState(false)
  const [eu, setEu] = useState<Pessoa | null>(null)
  const [acervo, setAcervo] = useState<Acervo>({ categorias: [], modelos: [] })
  const [ocupacao, setOcupacao] = useState<Ocupacao[]>([])
  const [horarios, setHorarios] = useState<Horarios>({ semestres: [], disciplinas: [], aulas: [], usos: [] })
  const [cesta, setCesta] = useState<Cesta>(cestaInicial)
  const [aviso, setAviso] = useState<{ texto: string; tom: 'ok' | 'erro'; n: number } | null>(null)

  const recarregar = useCallback(async () => {
    const [p, a, o, h] = await Promise.all([api.sessao(), api.acervo(), api.ocupacao(), api.horarios()])
    setEu(p); setAcervo(a); setOcupacao(o); setHorarios(h); setPronto(true)
  }, [])

  useEffect(() => {
    recarregar().catch((e) => { setPronto(true); setAviso({ texto: String(e.message ?? e), tom: 'erro', n: Date.now() }) })
    return api.aoMudarSessao(() => { void recarregar() })
  }, [recarregar])

  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(() => setAviso(null), aviso.tom === 'erro' ? 7000 : 3500)
    return () => clearTimeout(t)
  }, [aviso])

  const definirCesta = useCallback((c: Cesta) => {
    setCesta(c)
    try { sessionStorage.setItem(CHAVE_CESTA, JSON.stringify(c)) } catch { /* sem armazenamento */ }
  }, [])

  const valor = useMemo<Lea>(() => ({
    pronto, eu, acervo, ocupacao, horarios, cesta, definirCesta, recarregar,
    unidade(id) {
      for (const modelo of acervo.modelos) {
        const unidade = modelo.unidades.find((u) => u.id === id)
        if (unidade) return { unidade, modelo, categoria: acervo.categorias.find((c) => c.id === modelo.categoriaId)! }
      }
      return null
    },
    avisar(texto, tom = 'ok') { setAviso({ texto, tom, n: Date.now() }) },
  }), [pronto, eu, acervo, ocupacao, horarios, cesta, definirCesta, recarregar])

  return (
    <Ctx.Provider value={valor}>
      {children}
      <div className="aviso-area" aria-live="polite">
        {aviso && <div key={aviso.n} className={`aviso aviso-${aviso.tom}`} role={aviso.tom === 'erro' ? 'alert' : 'status'}>{aviso.texto}</div>}
      </div>
    </Ctx.Provider>
  )
}

/** Rota atual a partir do hash: '#/pedido/abc' → ['pedido', 'abc'] */
export function useRota(): string[] {
  const ler = () => location.hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent)
  const [rota, setRota] = useState(ler)
  useEffect(() => {
    const f = () => { setRota(ler()); window.scrollTo(0, 0) }
    window.addEventListener('hashchange', f)
    return () => window.removeEventListener('hashchange', f)
  }, [])
  return rota
}

export const ir = (caminho: string) => { location.hash = caminho }
