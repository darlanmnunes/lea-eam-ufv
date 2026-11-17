import { useEffect, useState } from 'react'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { diaHora, diaLongo } from '../lib/datas'
import { DECLARACOES, ETAPAS, NOME_PAPEL, PREAMBULO, TEXTO_EVENTO, identificacao } from '../lib/fluxo'
import type { Emprestimo } from '../lib/tipos'

/** O termo de responsabilidade como documento, pronto para imprimir ou salvar em PDF. */
export function Termo({ id }: { id: string }) {
  const { unidade, eu } = useLea()
  const [e, setE] = useState<Emprestimo | null | undefined>(undefined)
  useEffect(() => { api.emprestimo(id).then(setE).catch(() => setE(null)) }, [id, eu?.id])
  if (e === undefined) return <main className="pagina"><p className="carregando">Abrindo o termo…</p></main>
  if (!e) return <main className="pagina"><h1>Termo não encontrado</h1><p><a href="#/pedidos">Ver pedidos</a></p></main>
  const extras = e.eventos.filter((v) => !ETAPAS.some((x) => x.evento === v.tipo))

  return (
    <div className="termo-fundo">
      <div className="termo-barra">
        <a href={`#/pedido/${e.id}`}>Voltar ao pedido</a>
        <button className="btn" onClick={() => window.print()}>Imprimir ou salvar em PDF</button>
      </div>
      <article className="termo">
        <header className="termo-cab">
          <img src="./marca/ufv.png" alt="Universidade Federal de Viçosa" />
          <div>
            <p>Universidade Federal de Viçosa</p>
            <p>Departamento de Engenharia Civil</p>
            <p>Laboratório de Engenharia de Agrimensura e Cartográfica</p>
          </div>
          <img src="./marca/selo.png" alt="Engenharia de Agrimensura e Cartográfica" />
        </header>
        <h1>Termo de responsabilidade para retirada e utilização de equipamentos do LEA</h1>
        <p className="termo-codigo">{e.codigo}</p>
        <p className="termo-texto">{PREAMBULO}</p>

        <h2>1. Identificação do responsável</h2>
        <dl className="termo-dl">
          <div><dt>Nome</dt><dd>{e.respNome}</dd></div>
          <div><dt>Matrícula</dt><dd>{e.respMatricula}</dd></div>
          <div><dt>Telefone</dt><dd>{e.respTelefone}</dd></div>
          <div><dt>E-mail</dt><dd>{e.respEmail}</dd></div>
        </dl>

        <h2>2. Atividade</h2>
        <dl className="termo-dl">
          <div><dt>Finalidade da utilização</dt><dd>{e.finalidade}</dd></div>
          <div><dt>Projeto, disciplina ou grupo</dt><dd>{e.projeto}</dd></div>
          <div><dt>Local de utilização</dt><dd>{e.localUso}</dd></div>
          <div><dt>Data de retirada</dt><dd>{diaLongo(e.retiradaPrevista)}</dd></div>
          <div><dt>Data prevista de devolução</dt><dd>{diaLongo(e.devolucaoPrevista)}</dd></div>
        </dl>

        <h2>3. Participantes envolvidos</h2>
        <p>{e.participantes.length ? e.participantes.join('; ') : 'Nenhum além do responsável.'}</p>

        <h2>4. Equipamentos retirados</h2>
        <table>
          <thead><tr><th>Patrimônio</th><th>Equipamento</th><th>Observações</th></tr></thead>
          <tbody>
            {e.itens.map((i) => {
              const u = unidade(i.unidadeId)
              const notas = [i.observacao, i.estadoRetirada && `Retirada: ${i.estadoRetirada === 'conforme' ? 'conforme' : 'com ressalva'}${i.obsRetirada ? ` (${i.obsRetirada})` : ''}`,
                i.estadoDevolucao && `Devolução: ${i.estadoDevolucao === 'conforme' ? 'conforme' : 'com ressalva'}${i.obsDevolucao ? ` (${i.obsDevolucao})` : ''}`].filter(Boolean)
              return (
                <tr key={i.id}>
                  <td>{u ? identificacao(u.unidade).replace('Patrimônio ', '') : ''}</td>
                  <td>{u ? `${u.modelo.marca} ${u.modelo.nome}` : ''}</td>
                  <td>{notas.join('. ')}</td>
                </tr>
              )
            })}
          </tbody>
        </table>

        <h2>5. Declarações e responsabilidades</h2>
        <ul className="termo-decl">{DECLARACOES.map((d) => <li key={d}>{d}</li>)}</ul>

        <h2>6. Autorizações e cientes</h2>
        <table className="termo-assin">
          <thead><tr><th>Etapa</th><th>Assinado por</th><th>Data e hora</th><th>Observação</th></tr></thead>
          <tbody>
            {ETAPAS.map((x) => {
              const v = e.eventos.find((ev) => ev.tipo === x.evento)
              return (
                <tr key={x.id}>
                  <td>{NOME_PAPEL[x.quem]}<br /><small>{x.titulo}</small></td>
                  <td>{v ? v.autorNome : <span className="pendente">pendente</span>}</td>
                  <td>{v ? diaHora(v.criadoEm) : ''}</td>
                  <td>{v?.observacao ?? ''}</td>
                </tr>
              )
            })}
            {extras.map((v) => (
              <tr key={v.id}>
                <td>{TEXTO_EVENTO[v.tipo]}</td><td>{v.autorNome}</td><td>{diaHora(v.criadoEm)}</td><td>{v.observacao ?? ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="termo-nota">Assinaturas registradas eletronicamente no sistema de acervo do LEA, com identificação de quem assinou, data e hora.</p>
      </article>
    </div>
  )
}
