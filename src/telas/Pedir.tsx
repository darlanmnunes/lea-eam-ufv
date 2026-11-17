import { useState } from 'react'
import { Periodo } from './Acervo'
import { Campo, Foto, Vazio } from '../componentes/pecas'
import { ir, useLea } from '../contexto'
import { api } from '../lib/api'
import { diaLongo, diasEntre, hoje } from '../lib/datas'
import { quadro } from '../lib/disponibilidade'
import { DECLARACOES, PREAMBULO, cota } from '../lib/fluxo'

const PASSOS = ['Equipamentos', 'Atividade', 'Equipe', 'Termo']

export function Pedir() {
  const { eu, cesta, definirCesta, unidade, ocupacao, horarios, recarregar, avisar } = useLea()
  const [passo, setPasso] = useState(0)
  const [obsItem, setObsItem] = useState<Record<string, string>>({})
  const [f, setF] = useState({ finalidade: '', projeto: '', localUso: '', observacao: '' })
  const [participantes, setParticipantes] = useState<string[]>([''])
  const [aceites, setAceites] = useState(DECLARACOES.map(() => false))
  const [assinatura, setAssinatura] = useState('')
  const [tentou, setTentou] = useState(false)
  const [enviando, setEnviando] = useState(false)

  const itens = cesta.itens.map((id) => unidade(id)).filter((x) => x !== null)
  // unidades que deixaram de estar livres depois de entrar no pedido
  const conflitos = itens.filter(({ unidade: u, modelo }) => !quadro(modelo, ocupacao, horarios, cesta.de, cesta.ate).unidades.some((x) => x.unidade.id === u.id && x.estado === 'livre'))

  if (!itens.length) {
    return (
      <main className="pagina estreita">
        <h1>Novo pedido</h1>
        <Vazio titulo="Seu pedido ainda não tem equipamentos."><a className="btn" href="#/">Escolher no acervo</a></Vazio>
      </main>
    )
  }

  const erros = {
    finalidade: f.finalidade.trim().length < 5 ? 'Diga em poucas palavras para que os equipamentos serão usados.' : null,
    projeto: f.projeto.trim().length < 3 ? 'Informe o projeto, a disciplina ou o grupo.' : null,
    localUso: f.localUso.trim().length < 3 ? 'Informe onde os equipamentos serão usados.' : null,
  }
  const nomeConfere = !!eu && assinatura.trim().toLowerCase() === eu.nome.trim().toLowerCase()
  const podeAvancar = [
    conflitos.length === 0 && cesta.de >= hoje(),
    !erros.finalidade && !erros.projeto && !erros.localUso,
    true,
    aceites.every(Boolean) && nomeConfere,
  ]

  const avancar = () => {
    if (!podeAvancar[passo]) { setTentou(true); return }
    setTentou(false)
    setPasso(passo + 1)
    window.scrollTo(0, 0)
  }

  const enviar = async () => {
    if (!podeAvancar[3]) { setTentou(true); return }
    setEnviando(true)
    try {
      const id = await api.criar({
        ...f, retirada: cesta.de, devolucao: cesta.ate,
        participantes: participantes.map((p) => p.trim()).filter(Boolean),
        itens: cesta.itens.map((unidadeId) => ({ unidadeId, observacao: obsItem[unidadeId] ?? '' })),
      })
      definirCesta({ ...cesta, itens: [] })
      await recarregar()
      avisar('Pedido enviado. A coordenação da área foi avisada.')
      ir(`/pedido/${id}`)
    } catch (e) {
      avisar((e as Error).message, 'erro')
    } finally {
      setEnviando(false)
    }
  }

  const dias = diasEntre(cesta.de, cesta.ate) + 1

  return (
    <main className="pagina estreita">
      <p className="trilha"><a href="#/">Acervo</a> / Novo pedido</p>
      <h1>Novo pedido</h1>
      <ol className="passos" aria-label="Etapas do pedido">
        {PASSOS.map((p, i) => (
          <li key={p} aria-current={i === passo ? 'step' : undefined} className={i < passo ? 'feito' : ''}>
            {i < passo ? <button onClick={() => setPasso(i)}>{p}</button> : <span>{p}</span>}
          </li>
        ))}
      </ol>

      {passo === 0 && (
        <section className="bloco">
          <h2>O que sai do laboratório, e quando</h2>
          <Periodo />
          <p className="dica">{dias === 1 ? 'Retirada e devolução no mesmo dia.' : `${dias} dias com os equipamentos.`}</p>
          <ul className="itens-pedido">
            {itens.map(({ unidade: u, modelo, categoria }) => {
              const conflito = conflitos.some((c) => c.unidade.id === u.id)
              return (
                <li key={u.id} className={conflito ? 'conflito' : ''}>
                  <Foto m={modelo} />
                  <div>
                    <p className="unidade-id">{cota(categoria.sigla, u)}</p>
                    <p className="item-nome">{modelo.marca} {modelo.nome}</p>
                    {conflito && <p className="campo-msg" role="alert">Não está livre nessas datas. Mude o período ou tire do pedido.</p>}
                    <input type="text" placeholder="Observação: acessórios, tripé, bastão…" aria-label={`Observação para ${modelo.nome}`}
                      value={obsItem[u.id] ?? ''} onChange={(e) => setObsItem({ ...obsItem, [u.id]: e.target.value })} />
                  </div>
                  <button className="btn-texto" onClick={() => definirCesta({ ...cesta, itens: cesta.itens.filter((x) => x !== u.id) })}>Tirar</button>
                </li>
              )
            })}
          </ul>
          <p><a href="#/">Acrescentar outro equipamento</a></p>
        </section>
      )}

      {passo === 1 && (
        <section className="bloco">
          <h2>Para que os equipamentos serão usados</h2>
          <div className="grade-campos">
            <Campo rotulo="Finalidade da utilização" erro={tentou ? erros.finalidade : null} largo>
              <input type="text" value={f.finalidade} onChange={(e) => setF({ ...f, finalidade: e.target.value })} placeholder="Levantamento planialtimétrico para TCC" />
            </Campo>
            <Campo rotulo="Projeto, disciplina ou grupo" erro={tentou ? erros.projeto : null}>
              <input type="text" value={f.projeto} onChange={(e) => setF({ ...f, projeto: e.target.value })} placeholder="EAM 311 | Topografia II" />
            </Campo>
            <Campo rotulo="Local de utilização" erro={tentou ? erros.localUso : null}>
              <input type="text" value={f.localUso} onChange={(e) => setF({ ...f, localUso: e.target.value })} placeholder="Ponte Nova, MG" />
            </Campo>
            <Campo rotulo="Observações para quem autoriza" ajuda="Opcional." largo>
              <textarea rows={3} value={f.observacao} onChange={(e) => setF({ ...f, observacao: e.target.value })} />
            </Campo>
          </div>
        </section>
      )}

      {passo === 2 && (
        <section className="bloco">
          <h2>Quem vai a campo com você</h2>
          <p className="dica">Liste os participantes envolvidos. Você continua sendo a pessoa responsável pelos equipamentos.</p>
          <ul className="participantes">
            {participantes.map((p, i) => (
              <li key={i}>
                <input type="text" value={p} placeholder="Nome completo" aria-label={`Participante ${i + 1}`}
                  onChange={(e) => setParticipantes(participantes.map((x, k) => (k === i ? e.target.value : x)))} />
                {participantes.length > 1 && <button className="btn-texto" onClick={() => setParticipantes(participantes.filter((_, k) => k !== i))}>Tirar</button>}
              </li>
            ))}
          </ul>
          <button className="btn btn-claro btn-pequeno" onClick={() => setParticipantes([...participantes, ''])}>Acrescentar participante</button>
        </section>
      )}

      {passo === 3 && (
        <section className="bloco">
          <h2>Termo de responsabilidade</h2>
          {!eu ? (
            <Vazio titulo="Entre para assinar o termo."><a className="btn" href="#/entrar">Entrar</a></Vazio>
          ) : (
            <>
              <p className="termo-texto">{PREAMBULO}</p>
              <dl className="resumo">
                <div><dt>Responsável</dt><dd>{eu.nome} | {eu.matricula ?? 'sem matrícula'}</dd></div>
                <div><dt>Retirada</dt><dd>{diaLongo(cesta.de)}</dd></div>
                <div><dt>Devolução</dt><dd>{diaLongo(cesta.ate)}</dd></div>
                <div><dt>Equipamentos</dt><dd>{itens.map(({ unidade: u, modelo, categoria }) => `${modelo.marca} ${modelo.nome} (${cota(categoria.sigla, u)})`).join('; ')}</dd></div>
                <div><dt>Finalidade</dt><dd>{f.finalidade} | {f.projeto} | {f.localUso}</dd></div>
              </dl>
              <fieldset className="declaracoes">
                <legend>Declaro que</legend>
                {DECLARACOES.map((d, i) => (
                  <label key={d} className="chave">
                    <input type="checkbox" checked={aceites[i]} onChange={(e) => setAceites(aceites.map((x, k) => (k === i ? e.target.checked : x)))} />
                    {d}
                  </label>
                ))}
                {tentou && !aceites.every(Boolean) && <p className="campo-msg" role="alert">Marque as três declarações para assinar.</p>}
              </fieldset>
              <Campo rotulo="Assine digitando seu nome completo" ajuda={`Como no cadastro: ${eu.nome}`} erro={tentou && !nomeConfere ? 'O nome precisa ser igual ao do cadastro.' : null}>
                <input className="assinatura" type="text" autoComplete="off" value={assinatura} onChange={(e) => setAssinatura(e.target.value)} />
              </Campo>
            </>
          )}
        </section>
      )}

      <div className="passos-pe">
        {passo > 0 ? <button className="btn btn-claro" onClick={() => setPasso(passo - 1)}>Voltar</button> : <span />}
        {passo < 3 ? <button className="btn" onClick={avancar}>Continuar</button>
          : eu && <button className="btn btn-bordo" disabled={enviando} onClick={enviar}>{enviando ? 'Enviando…' : 'Assinar e enviar pedido'}</button>}
      </div>
    </main>
  )
}
