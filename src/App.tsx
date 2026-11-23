import { useState } from 'react'
import { Provedor, ir, useLea, useRota } from './contexto'
import { api } from './lib/api'
import { cuidaDoAcervo, informaAulas, tem } from './lib/fluxo'
import { Acervo } from './telas/Acervo'
import { Equipamento } from './telas/Equipamento'
import { Pedir } from './telas/Pedir'
import { Pedidos } from './telas/Pedidos'
import { Pedido } from './telas/Pedido'
import { Termo } from './telas/Termo'
import { Entrar } from './telas/Entrar'
import { Aulas } from './telas/Aulas'
import { Gestao } from './telas/Gestao'
import { Pessoas } from './telas/Pessoas'
import { VoltarTopo } from './componentes/VoltarTopo'

function Topo({ secao }: { secao: string }) {
  const { eu } = useLea()
  const [aberto, setAberto] = useState(false)
  const links: [string, string, boolean][] = [
    ['', 'Acervo', true],
    ['pedidos', 'Pedidos', !!eu],
    ['aulas', 'Aulas', true],
    ['gestao', 'Cadastro', cuidaDoAcervo(eu)],
    ['pessoas', 'Pessoas', tem(eu, 'admin')],
  ]
  const ativo = (r: string) => (r === '' ? ['', 'equipamento', 'pedir'].includes(secao) : r === 'pedidos' ? ['pedidos', 'pedido'].includes(secao) : secao === r)
  return (
    <header className="topo">
      <div className="topo-dentro">
        <a className="topo-marca" href="./index.html" aria-label="LEA, página inicial">
          <img src="./marca/selo.png" alt="" width="40" height="40" />
          <span><b>LEA</b><small>Acervo do laboratório</small></span>
        </a>
        <button className="topo-menu" aria-expanded={aberto} aria-controls="nav" onClick={() => setAberto(!aberto)}>Menu</button>
        <nav id="nav" className={aberto ? 'aberto' : ''} aria-label="Seções" onClick={() => setAberto(false)}>
          {links.filter((l) => l[2]).map(([r, nome]) => (
            <a key={r} href={`#/${r}`} aria-current={ativo(r) ? 'page' : undefined}>{nome}</a>
          ))}
          {eu ? (
            <a className="topo-pessoa" href="#/entrar" aria-current={secao === 'entrar' ? 'page' : undefined}>
              <span className="topo-inicial" aria-hidden="true">{eu.nome.replace(/^Profa?\. /, '').charAt(0)}</span>
              {eu.nome.split(' ').slice(0, 2).join(' ')}
            </a>
          ) : (
            <a className="btn btn-pequeno" href="#/entrar">Entrar</a>
          )}
        </nav>
      </div>
      {api.modo === 'demo' && (
        <p className="topo-demo">Demonstração: os dados ficam só neste navegador e as pessoas são fictícias.</p>
      )}
    </header>
  )
}

function Rodape() {
  return (
    <footer className="rodape">
      <div className="rodape-dentro">
        <img src="./marca/ufv.png" alt="Universidade Federal de Viçosa" height="44" />
        <p>
          Laboratório de Engenharia de Agrimensura e Cartográfica (LEA)<br />
          Departamento de Engenharia Civil | Universidade Federal de Viçosa<br />
          <span className="rodape-autor">Desenvolvido por Prof. Dr. Darlan Miranda Nunes</span><br />
          <a className="rodape-doi" href="https://doi.org/10.5281/zenodo.24478306">DOI 10.5281/zenodo.24478306</a>
        </p>
        <img src="./marca/assinatura.png" alt="EAM | Engenharia de Agrimensura e Cartográfica" height="44" />
      </div>
    </footer>
  )
}

function Telas() {
  const rota = useRota()
  const { pronto, eu } = useLea()
  const [secao = '', a, b] = rota
  if (!pronto) return <main className="pagina"><p className="carregando">Abrindo o acervo…</p></main>
  if (secao === 'pedido' && b === 'termo') return <Termo id={a} />

  const privada = ['pedidos', 'pedido', 'gestao', 'pessoas'].includes(secao)
  let tela
  if (privada && !eu) tela = <Entrar motivo="Entre para ver esta página." />
  else if (eu?.incompleto && secao !== 'entrar') tela = <Entrar motivo="Complete seu cadastro para continuar." />
  else if (secao === '') tela = <Acervo />
  else if (secao === 'equipamento') tela = <Equipamento id={a} />
  else if (secao === 'pedir') tela = <Pedir />
  else if (secao === 'pedidos') tela = <Pedidos />
  else if (secao === 'pedido') tela = <Pedido id={a} />
  else if (secao === 'entrar') tela = <Entrar />
  else if (secao === 'aulas') tela = <Aulas podeEditar={informaAulas(eu)} />
  else if (secao === 'gestao' && cuidaDoAcervo(eu)) tela = <Gestao />
  else if (secao === 'pessoas' && tem(eu, 'admin')) tela = <Pessoas />
  else tela = (
    <main className="pagina">
      <h1>Página não encontrada</h1>
      <p><button className="btn" onClick={() => ir('/')}>Voltar ao acervo</button></p>
    </main>
  )
  return (
    <>
      <a className="pular" href="#conteudo">Ir para o conteúdo</a>
      <Topo secao={secao} />
      <div id="conteudo">{tela}</div>
      <Rodape />
      <VoltarTopo />
    </>
  )
}

export function App() {
  return <Provedor><Telas /></Provedor>
}
