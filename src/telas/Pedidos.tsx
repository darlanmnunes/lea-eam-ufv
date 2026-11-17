import { useEffect, useState } from 'react'
import { Cabecalho, Selo, Vazio } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { periodo } from '../lib/datas'
import { ETAPAS, aguardandoQuem, atrasado, ehEquipe, pendencia } from '../lib/fluxo'
import type { Emprestimo } from '../lib/tipos'

export function Trilho({ e }: { e: Emprestimo }) {
  const feitas = ETAPAS.filter((x) => e.eventos.some((v) => v.tipo === x.evento)).length
  return (
    <span className="trilho" role="img" aria-label={`${feitas} de ${ETAPAS.length} assinaturas`}>
      {ETAPAS.map((x, i) => <i key={x.id} className={i < feitas ? 'ok' : i === feitas && !['recusado', 'cancelado'].includes(e.status) ? 'agora' : ''} />)}
    </span>
  )
}

function Linha({ e, minha }: { e: Emprestimo; minha: boolean }) {
  const { unidade } = useLea()
  const nomes = e.itens.map((i) => { const u = unidade(i.unidadeId); return u ? `${u.modelo.marca} ${u.modelo.nome}` : 'Equipamento' })
  const resumo = [...new Set(nomes)].map((n) => { const k = nomes.filter((x) => x === n).length; return k > 1 ? `${k} × ${n}` : n }).join(', ')
  const quem = aguardandoQuem(e)
  return (
    <li>
      <a className="linha-pedido" href={`#/pedido/${e.id}`}>
        <span className="linha-codigo">{e.codigo}</span>
        <span className="linha-miolo">
          <b>{e.finalidade}</b>
          <small>{resumo} | {periodo(e.retiradaPrevista, e.devolucaoPrevista)}{minha ? '' : ` | ${e.respNome}`}</small>
        </span>
        <span className="linha-status">
          <Selo status={e.status} />
          {atrasado(e) ? <small className="alerta">Devolução vencida</small> : quem && <small>Com: {quem}</small>}
        </span>
        <Trilho e={e} />
      </a>
    </li>
  )
}

export function Pedidos() {
  const { eu } = useLea()
  const [lista, setLista] = useState<Emprestimo[] | null>(null)
  useEffect(() => { api.emprestimos().then(setLista).catch(() => setLista([])) }, [eu?.id])
  if (!lista) return <main className="pagina"><p className="carregando">Buscando pedidos…</p></main>

  const comigo = lista.filter((e) => pendencia(e, eu))
  const andamento = lista.filter((e) => !comigo.includes(e) && !['encerrado', 'recusado', 'cancelado'].includes(e.status))
  const fechados = lista.filter((e) => ['encerrado', 'recusado', 'cancelado'].includes(e.status))
  const equipe = ehEquipe(eu)

  return (
    <main className="pagina">
      <Cabecalho sobre={equipe ? 'Todos os pedidos do laboratório' : 'Seus pedidos'} titulo="Pedidos">
        <a className="btn" href="#/">Novo pedido</a>
      </Cabecalho>
      {lista.length === 0 && <Vazio titulo="Nenhum pedido por aqui ainda."><a className="btn" href="#/">Escolher equipamentos</a></Vazio>}
      {comigo.length > 0 && (
        <section className="grupo grupo-vez">
          <h2>Esperando você <span className="conta-grupo">{comigo.length}</span></h2>
          <ul className="lista-pedidos">{comigo.map((e) => <Linha key={e.id} e={e} minha={e.solicitanteId === eu?.id} />)}</ul>
        </section>
      )}
      {andamento.length > 0 && (
        <section className="grupo">
          <h2>Em andamento</h2>
          <ul className="lista-pedidos">{andamento.map((e) => <Linha key={e.id} e={e} minha={e.solicitanteId === eu?.id} />)}</ul>
        </section>
      )}
      {fechados.length > 0 && (
        <section className="grupo">
          <h2>Encerrados</h2>
          <ul className="lista-pedidos">{fechados.map((e) => <Linha key={e.id} e={e} minha={e.solicitanteId === eu?.id} />)}</ul>
        </section>
      )}
    </main>
  )
}
