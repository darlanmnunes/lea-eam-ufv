import { useState } from 'react'
import { Campo } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { reiniciarDemo } from '../lib/demo'
import { NOME_PAPEL } from '../lib/fluxo'

export function Entrar({ motivo }: { motivo?: string }) {
  const { eu, recarregar, avisar } = useLea()
  const [email, setEmail] = useState('')
  const [enviado, setEnviado] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [perfil, setPerfil] = useState({ nome: eu?.nome ?? '', matricula: eu?.matricula ?? '', telefone: eu?.telefone ?? '', vinculo: eu?.vinculo ?? 'Discente' })

  const pedirLink = async () => {
    if (!/^[^@\s]+@(ufv\.br|[a-z0-9-]+\.ufv\.br)$/i.test(email.trim())) { setErro('Use seu e-mail institucional, terminado em ufv.br.'); return }
    setErro(null)
    try { await api.entrar(email.trim().toLowerCase()); setEnviado(true) } catch (e) { setErro((e as Error).message) }
  }

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
      <p className="dica">{motivo ?? 'Enviamos um link de acesso para o seu e-mail da UFV. Não há senha para guardar.'}</p>
      {enviado ? (
        <p className="confirma" role="status">Link enviado para {email}. Abra o e-mail neste aparelho para entrar.</p>
      ) : (
        <form className="entrar" onSubmit={(e) => { e.preventDefault(); void pedirLink() }}>
          <Campo rotulo="E-mail institucional" erro={erro}>
            <input type="email" autoComplete="email" placeholder="nome@ufv.br" value={email} onChange={(e) => setEmail(e.target.value)} />
          </Campo>
          <button className="btn" type="submit">Enviar link de acesso</button>
        </form>
      )}
    </main>
  )
}
