import { useState } from 'react'
import { Campo } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { reiniciarDemo } from '../lib/demo'
import { NOME_PAPEL } from '../lib/fluxo'

export function Entrar({ motivo }: { motivo?: string }) {
  const { eu, recarregar, avisar } = useLea()
  const [erro, setErro] = useState<string | null>(null)
  const [perfil, setPerfil] = useState({ nome: eu?.nome ?? '', matricula: eu?.matricula ?? '', telefone: eu?.telefone ?? '', vinculo: eu?.vinculo ?? 'Discente' })

  const salvar = async () => {
    if (perfil.nome.trim().length < 5 || !perfil.matricula.trim() || !perfil.telefone.trim()) { setErro('Preencha nome completo, matrícula e telefone.'); return }
    setErro(null)
    try { await api.salvarPerfil(perfil); await recarregar(); avisar('Cadastro salvo.') } catch (e) { setErro((e as Error).message) }
  }

  if (eu && (eu.incompleto || api.modo === 'supabase')) {
    return (
      <main className="pagina estreita">
        <h1>{eu.incompleto ? 'Complete seu cadastro' : 'Seu cadastro'}</h1>
        <p className="dica">Estes dados entram na identificação do responsável em cada termo. Conta: {eu.email}</p>
        <div className="grade-campos">
          <Campo rotulo="Nome completo" largo><input type="text" autoComplete="name" value={perfil.nome} onChange={(e) => setPerfil({ ...perfil, nome: e.target.value })} /></Campo>
          <Campo rotulo="Matrícula"><input type="text" value={perfil.matricula} onChange={(e) => setPerfil({ ...perfil, matricula: e.target.value })} /></Campo>
          <Campo rotulo="Telefone"><input type="tel" autoComplete="tel" value={perfil.telefone} onChange={(e) => setPerfil({ ...perfil, telefone: e.target.value })} /></Campo>
          <Campo rotulo="Vínculo">
            <select value={perfil.vinculo} onChange={(e) => setPerfil({ ...perfil, vinculo: e.target.value })}>
              <option>Discente</option><option>Docente</option><option>Técnico</option>
            </select>
          </Campo>
        </div>
        {erro && <p className="campo-msg" role="alert">{erro}</p>}
        <div className="passos-pe">
          <button className="btn btn-claro" onClick={() => api.sair()}>Sair</button>
          <button className="btn" onClick={salvar}>Salvar cadastro</button>
        </div>
      </main>
    )
  }

  if (api.modo === 'demo') {
    return (
      <main className="pagina estreita">
        <h1>Entrar</h1>
        <p className="dica">{motivo ?? 'Nesta demonstração você escolhe um papel e percorre o fluxo do pedido de ponta a ponta. Troque de papel para assinar cada etapa.'}</p>
        <ul className="personas">
          {api.personas().map((p) => (
            <li key={p.id}>
              <button className={eu?.id === p.id ? 'ativa' : ''} onClick={async () => { await api.entrar(p.id); avisar(`Você entrou como ${p.nome}.`) }}>
                <span className="topo-inicial" aria-hidden="true">{p.nome.replace(/^Profa?\. /, '').charAt(0)}</span>
                <span><b>{p.nome}</b><small>{p.papeis.filter((x) => x !== 'solicitante').map((x) => NOME_PAPEL[x]).join(', ') || 'Discente que faz o pedido'}</small></span>
                {eu?.id === p.id && <em>Você</em>}
              </button>
            </li>
          ))}
        </ul>
        <div className="passos-pe">
          <button className="btn-texto" onClick={() => { reiniciarDemo(); void recarregar(); avisar('Demonstração reiniciada.') }}>Reiniciar os dados da demonstração</button>
          {eu && <button className="btn btn-claro" onClick={() => api.sair()}>Sair</button>}
        </div>
      </main>
    )
  }

  return (
    <main className="pagina estreita">
      <h1>Entrar</h1>
      <p className="dica">{motivo ?? 'Use a sua conta Google da UFV, a mesma do e-mail institucional.'}</p>
      <button className="btn btn-google" onClick={async () => {
        setErro(null)
        try { await api.entrar() } catch (e) { setErro((e as Error).message) }
      }}>
        <svg viewBox="0 0 18 18" width="18" height="18" aria-hidden="true"><path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"/><path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z"/><path fill="#FBBC05" d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33z"/><path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z"/></svg>
        Entrar com Google
      </button>
      {erro && <p className="campo-msg" role="alert">{erro}</p>}
      <p className="dica">No primeiro acesso, você informa matrícula e telefone, que entram no termo de responsabilidade.</p>
    </main>
  )
}
