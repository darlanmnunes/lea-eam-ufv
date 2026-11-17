import { useCallback, useEffect, useState } from 'react'
import { Campo, Selo } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { dia, diaHora, diaLongo, hoje } from '../lib/datas'
import { ETAPAS, NOME_PAPEL, TEXTO_EVENTO, aguardandoQuem, atrasado, cota, papelNaFrase, pendencia, tem } from '../lib/fluxo'
import type { Acao, Conferencia, Emprestimo, EstadoItem } from '../lib/tipos'

function Carimbos({ e }: { e: Emprestimo }) {
  const parado = ['recusado', 'cancelado'].includes(e.status)
  const feitas = ETAPAS.filter((x) => e.eventos.some((v) => v.tipo === x.evento)).length
  return (
    <ol className="carimbos" aria-label="Assinaturas do termo">
      {ETAPAS.map((x, i) => {
        const ev = e.eventos.find((v) => v.tipo === x.evento)
        const vez = !ev && i === feitas && !parado
        return (
          <li key={x.id} className={ev ? 'carimbado' : vez ? 'da-vez' : ''}>
            <span className="carimbo-n">{i + 1}</span>
            <span className="carimbo-titulo">{x.titulo}</span>
            {ev ? (
              <span className="carimbo">
                <b>{x.verbo}</b>
                <span>{ev.autorNome}</span>
                <time dateTime={ev.criadoEm}>{diaHora(ev.criadoEm)}</time>
              </span>
            ) : (
              <span className="carimbo-espera">{vez ? `Aguarda ${papelNaFrase(x.quem)}` : NOME_PAPEL[x.quem]}</span>
            )}
          </li>
        )
      })}
    </ol>
  )
}

export function Pedido({ id }: { id: string }) {
  const { eu, unidade, recarregar, avisar } = useLea()
  const [e, setE] = useState<Emprestimo | null | undefined>(undefined)
  const [obs, setObs] = useState('')
  const [conf, setConf] = useState<Record<string, { estado: EstadoItem; obs: string }>>({})
  const [modo, setModo] = useState<'assinar' | 'recusar' | 'ocorrencia' | 'prorrogar' | 'cancelar'>('assinar')
  const [novaData, setNovaData] = useState('')
  const [ocupado, setOcupado] = useState(false)

  const buscar = useCallback(() => api.emprestimo(id).then(setE).catch(() => setE(null)), [id])
  useEffect(() => { void buscar() }, [buscar, eu?.id])

  if (e === undefined) return <main className="pagina"><p className="carregando">Abrindo o pedido…</p></main>
  if (!e) return <main className="pagina"><h1>Pedido não encontrado</h1><p><a href="#/pedidos">Ver pedidos</a></p></main>

  const p = pendencia(e, eu)
  const dono = e.solicitanteId === eu?.id
  const quem = aguardandoQuem(e)
  const pedeProrrogacao = e.eventos.filter((v) => v.tipo === 'prorrogacao_pedida').length > e.eventos.filter((v) => v.tipo === 'prorrogacao_autorizada').length
  const fase = p?.confere

  const fazer = async (acao: Acao, extra: { itens?: Conferencia[]; novaDevolucao?: string } = {}) => {
    setOcupado(true)
    try {
      await api.avancar(e.id, acao, { observacao: obs, ...extra })
      setObs(''); setConf({}); setModo('assinar'); setNovaData('')
      await Promise.all([buscar(), recarregar()])
      avisar('Registrado.')
    } catch (err) {
      avisar((err as Error).message, 'erro')
    } finally {
      setOcupado(false)
    }
  }

  const conferencias = (): Conferencia[] => e.itens.map((i) => ({ itemId: i.id, estado: conf[i.id]?.estado ?? 'conforme', obs: conf[i.id]?.obs ?? '' }))

  return (
    <main className="pagina">
      <p className="trilha"><a href="#/pedidos">Pedidos</a> / {e.codigo}</p>
      <header className="cab cab-pedido">
        <div>
          <p className="cab-sobre">{e.codigo} | pedido em {dia(e.criadoEm)}</p>
          <h1>{e.finalidade}</h1>
          <p className="cab-linha">
            <Selo status={e.status} />
            {atrasado(e) && <span className="alerta">Devolução vencida em {dia(e.devolucaoPrevista)}</span>}
            {quem && !p && <span>Com: {quem}</span>}
          </p>
        </div>
        <div className="cab-acoes"><a className="btn btn-claro" href={`#/pedido/${e.id}/termo`}>Abrir o termo</a></div>
      </header>

      <Carimbos e={e} />

      <div className="duas">
        <div>
          {p && (
            <section className="vez" aria-labelledby="vez-t">
              <h2 id="vez-t">{modo === 'recusar' ? 'Recusar o pedido' : p.rotulo}</h2>
              <p>{modo === 'recusar' ? 'Explique o motivo. Quem pediu recebe a resposta e pode fazer um novo pedido.' : p.explica}</p>
              {fase && (
                <ul className="conferencia">
                  {e.itens.map((i) => {
                    const u = unidade(i.unidadeId)
                    const c = conf[i.id] ?? { estado: 'conforme' as EstadoItem, obs: '' }
                    return (
                      <li key={i.id}>
                        <p><b>{u ? `${u.modelo.marca} ${u.modelo.nome}` : 'Equipamento'}</b> <span className="unidade-id">{u ? cota(u.categoria.sigla, u.unidade) : ''}</span></p>
                        {fase === 'devolucao' && i.obsRetirada && <p className="dica">Na retirada: {i.obsRetirada}</p>}
                        <div className="conferencia-linha">
                          <div className="alterna" role="radiogroup" aria-label="Estado do item">
                            <button role="radio" aria-checked={c.estado === 'conforme'} onClick={() => setConf({ ...conf, [i.id]: { ...c, estado: 'conforme' } })}>Conforme</button>
                            <button role="radio" aria-checked={c.estado === 'com_ressalva'} onClick={() => setConf({ ...conf, [i.id]: { ...c, estado: 'com_ressalva' } })}>Com ressalva</button>
                          </div>
                          <input type="text" aria-label="Observação do item" placeholder={c.estado === 'com_ressalva' ? 'Descreva a ressalva' : 'Acessórios, baterias, estado do estojo…'}
                            value={c.obs} onChange={(ev) => setConf({ ...conf, [i.id]: { ...c, obs: ev.target.value } })} />
                        </div>
                      </li>
                    )
                  })}
                </ul>
              )}
              <Campo rotulo={modo === 'recusar' ? 'Motivo da recusa' : 'Observação'} ajuda={modo === 'recusar' ? undefined : 'Opcional. Fica registrada no termo.'}>
                <textarea rows={2} value={obs} onChange={(ev) => setObs(ev.target.value)} />
              </Campo>
              <div className="vez-botoes">
                {modo === 'recusar' ? (
                  <>
                    <button className="btn btn-bordo" disabled={ocupado || !obs.trim()} onClick={() => fazer('recusar')}>Confirmar recusa</button>
                    <button className="btn btn-claro" onClick={() => setModo('assinar')}>Voltar</button>
                  </>
                ) : (
                  <>
                    <button className="btn btn-bordo" disabled={ocupado} onClick={() => fazer(p.acao, fase ? { itens: conferencias() } : {})}>{p.rotulo}</button>
                    {p.recusa && <button className="btn btn-claro" onClick={() => setModo('recusar')}>Recusar</button>}
                  </>
                )}
              </div>
              <p className="assina-como">Assinando como {eu!.nome}</p>
            </section>
          )}

          <section className="bloco">
            <h2>Equipamentos</h2>
            <ul className="itens-ficha">
              {e.itens.map((i) => {
                const u = unidade(i.unidadeId)
                return (
                  <li key={i.id}>
                    <p className="unidade-id">{u ? cota(u.categoria.sigla, u.unidade) : 'Unidade retirada do acervo'}</p>
                    <p className="item-nome">{u ? `${u.modelo.marca} ${u.modelo.nome}` : ''}</p>
                    {i.observacao && <p className="nota">Pedido: {i.observacao}</p>}
                    {i.estadoRetirada && <p className={`nota${i.estadoRetirada === 'com_ressalva' ? ' nota-ressalva' : ''}`}>Retirada: {i.estadoRetirada === 'conforme' ? 'conforme' : 'com ressalva'}{i.obsRetirada ? `. ${i.obsRetirada}` : ''}</p>}
                    {i.estadoDevolucao && <p className={`nota${i.estadoDevolucao === 'com_ressalva' ? ' nota-ressalva' : ''}`}>Devolução: {i.estadoDevolucao === 'conforme' ? 'conforme' : 'com ressalva'}{i.obsDevolucao ? `. ${i.obsDevolucao}` : ''}</p>}
                  </li>
                )
              })}
            </ul>
          </section>

          <section className="bloco">
            <h2>Registro</h2>
            <ol className="registro">
              {e.eventos.map((v) => (
                <li key={v.id}>
                  <time dateTime={v.criadoEm}>{diaHora(v.criadoEm)}</time>
                  <p><b>{v.autorNome}</b> | {papelNaFrase(v.autorPapel)}</p>
                  <p>{TEXTO_EVENTO[v.tipo]}{v.observacao ? `: “${v.observacao}”` : '.'}</p>
                </li>
              ))}
            </ol>
          </section>
        </div>

        <aside>
          <section className="bloco">
            <h2>Atividade</h2>
            <dl className="resumo resumo-coluna">
              <div><dt>Responsável</dt><dd>{e.respNome}<br />{e.respMatricula} | {e.respTelefone}<br />{e.respEmail}</dd></div>
              <div><dt>Projeto, disciplina ou grupo</dt><dd>{e.projeto}</dd></div>
              <div><dt>Local</dt><dd>{e.localUso}</dd></div>
              <div><dt>Retirada</dt><dd>{diaLongo(e.retiradaPrevista)}</dd></div>
              <div><dt>Devolução prevista</dt><dd>{diaLongo(e.devolucaoPrevista)}</dd></div>
              {e.participantes.length > 0 && <div><dt>Participantes</dt><dd>{e.participantes.join(', ')}</dd></div>}
              {e.observacao && <div><dt>Observações</dt><dd>{e.observacao}</dd></div>}
            </dl>
          </section>

          {(e.status === 'em_uso' || e.status === 'aguardando_ciente_devolucao') && (dono || tem(eu, 'tecnico', 'responsavel_lea')) && (
            <section className="bloco">
              <h2>Durante o uso</h2>
              {modo === 'ocorrencia' || modo === 'prorrogar' ? (
                <>
                  <Campo rotulo={modo === 'ocorrencia' ? 'O que aconteceu' : dono ? 'Por que precisa de mais prazo' : 'Observação'}>
                    <textarea rows={3} value={obs} onChange={(ev) => setObs(ev.target.value)} />
                  </Campo>
                  {modo === 'prorrogar' && !dono && (
                    <Campo rotulo="Nova data de devolução">
                      <input type="date" min={e.devolucaoPrevista > hoje() ? e.devolucaoPrevista : hoje()} value={novaData} onChange={(ev) => setNovaData(ev.target.value)} />
                    </Campo>
                  )}
                  <div className="vez-botoes">
                    <button className="btn" disabled={ocupado || (modo === 'ocorrencia' || dono ? !obs.trim() : !novaData)}
                      onClick={() => fazer(modo === 'ocorrencia' ? 'ocorrencia' : dono ? 'pedir_prorrogacao' : 'autorizar_prorrogacao', { novaDevolucao: novaData })}>Registrar</button>
                    <button className="btn btn-claro" onClick={() => { setModo('assinar'); setObs('') }}>Voltar</button>
                  </div>
                </>
              ) : (
                <div className="pilha">
                  {(dono || tem(eu, 'tecnico')) && <button className="btn btn-claro" onClick={() => setModo('ocorrencia')}>Registrar ocorrência</button>}
                  {dono && e.status === 'em_uso' && <button className="btn btn-claro" onClick={() => setModo('prorrogar')}>Pedir prorrogação</button>}
                  {tem(eu, 'responsavel_lea') && e.status === 'em_uso' && (
                    <button className="btn btn-claro" onClick={() => setModo('prorrogar')}>{pedeProrrogacao ? 'Responder pedido de prorrogação' : 'Prorrogar devolução'}</button>
                  )}
                </div>
              )}
            </section>
          )}

          {dono && ['aguardando_coordenacao', 'aguardando_lea', 'aguardando_retirada'].includes(e.status) && (
            <section className="bloco">
              {modo === 'cancelar' ? (
                <>
                  <p>Cancelar libera os equipamentos para outros pedidos. O registro continua no histórico.</p>
                  <div className="vez-botoes">
                    <button className="btn btn-bordo" disabled={ocupado} onClick={() => fazer('cancelar')}>Cancelar o pedido</button>
                    <button className="btn btn-claro" onClick={() => setModo('assinar')}>Manter</button>
                  </div>
                </>
              ) : <button className="btn-texto" onClick={() => setModo('cancelar')}>Cancelar este pedido</button>}
            </section>
          )}
        </aside>
      </div>
    </main>
  )
}
