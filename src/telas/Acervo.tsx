import { useMemo, useState } from 'react'
import { Foto, Marcas, Vazio } from '../componentes/pecas'
import { useLea } from '../contexto'
import { hoje, periodo } from '../lib/datas'
import { quadro, textoAula } from '../lib/disponibilidade'

export function Periodo() {
  const { cesta, definirCesta } = useLea()
  return (
    <fieldset className="periodo">
      <legend>Quando você precisa?</legend>
      <label>
        <span>Retirada</span>
        <input type="date" value={cesta.de} min={hoje()} onChange={(e) => {
          const de = e.target.value || hoje()
          definirCesta({ ...cesta, de, ate: cesta.ate < de ? de : cesta.ate })
        }} />
      </label>
      <label>
        <span>Devolução</span>
        <input type="date" value={cesta.ate} min={cesta.de} onChange={(e) => definirCesta({ ...cesta, ate: e.target.value || cesta.de })} />
      </label>
    </fieldset>
  )
}

export function Acervo() {
  const { acervo, ocupacao, horarios, cesta, definirCesta, avisar } = useLea()
  const [cat, setCat] = useState('todas')
  const [busca, setBusca] = useState('')
  const [soLivres, setSoLivres] = useState(false)

  const lista = useMemo(() => {
    const t = busca.trim().toLowerCase()
    return acervo.modelos
      .filter((m) => m.unidades.some((u) => u.situacao !== 'baixado'))
      .map((m) => ({ m, q: quadro(m, ocupacao, horarios, cesta.de, cesta.ate), cat: acervo.categorias.find((c) => c.id === m.categoriaId)! }))
      .filter(({ m, q, cat: c }) =>
        (cat === 'todas' || m.categoriaId === cat) &&
        (!soLivres || (m.emprestavel && q.livres.length > 0)) &&
        (!t || `${m.marca} ${m.nome} ${c.nome} ${m.unidades.map((u) => `${u.patrimonio ?? ''} ${u.serie ?? ''}`).join(' ')}`.toLowerCase().includes(t)))
  }, [acervo, ocupacao, horarios, cesta.de, cesta.ate, cat, busca, soLivres])

  const naFicha = (modeloId: string) => cesta.itens.filter((id) => id.startsWith(`${modeloId}#`) || acervo.modelos.find((m) => m.id === modeloId)?.unidades.some((u) => u.id === id)).length

  return (
    <main className="pagina">
      <section className="abre">
        <div>
          <p className="cab-sobre">Acervo do LEA</p>
          <h1>Equipamentos</h1>
          <p className="abre-texto">Escolha as datas, veja o que está livre e monte seu pedido. A autorização e os cientes de retirada e devolução acontecem aqui, sem papel.</p>
        </div>
        <Periodo />
      </section>

      <div className="filtros">
        <div className="abas" role="tablist" aria-label="Categorias">
          <button role="tab" aria-selected={cat === 'todas'} onClick={() => setCat('todas')}>Tudo</button>
          {acervo.categorias.map((c) => (
            <button key={c.id} role="tab" aria-selected={cat === c.id} onClick={() => setCat(c.id)}>{c.nome}</button>
          ))}
        </div>
        <div className="filtros-lado">
          <label className="chave">
            <input type="checkbox" checked={soLivres} onChange={(e) => setSoLivres(e.target.checked)} />
            Só o que está livre
          </label>
          <input className="busca" type="search" placeholder="Buscar modelo ou patrimônio" aria-label="Buscar modelo ou patrimônio" value={busca} onChange={(e) => setBusca(e.target.value)} />
        </div>
      </div>

      <p className="legenda" aria-hidden="true">
        <span><i className="marca marca-livre" /> disponível</span>
        <span><i className="marca marca-aula" /> em aula</span>
        <span><i className="marca marca-emprestado" /> emprestado</span>
        <span><i className="marca marca-manutencao" /> manutenção ou estoque</span>
        <span className="legenda-periodo">Situação em {periodo(cesta.de, cesta.ate)}</span>
      </p>

      {lista.length === 0 ? (
        <Vazio titulo="Nada no acervo com esse filtro.">
          <button className="btn btn-claro" onClick={() => { setCat('todas'); setBusca(''); setSoLivres(false) }}>Limpar filtros</button>
        </Vazio>
      ) : (
        <ul className="estante">
          {lista.map(({ m, q, cat: c }) => {
            const meus = naFicha(m.id)
            const sobra = q.livres.filter((u) => !cesta.itens.includes(u.id))
            return (
              <li key={m.id} className="ficha-acervo">
                <a href={`#/equipamento/${m.id}`} className="ficha-acervo-foto" tabIndex={-1} aria-hidden="true"><Foto m={m} /><span className="ficha-acervo-ver">Ver as unidades <span aria-hidden="true">→</span></span></a>
                <div className="ficha-acervo-corpo">
                  <p className="cota">{c.sigla} | {c.nome}</p>
                  <h2><a href={`#/equipamento/${m.id}`}>{m.marca} {m.nome}</a></h2>
                  <div className="ficha-acervo-linha">
                    <Marcas q={q} />
                    <span className="conta">{m.emprestavel ? `${q.livres.length} de ${q.unidades.length} ${q.livres.length === 1 ? 'livre' : 'livres'}` : `${q.unidades.length} ${q.unidades.length === 1 ? 'unidade' : 'unidades'}`}</span>
                  </div>
                  {q.aulas.length > 0 && <p className="nota-aula">Em aula: {q.aulas.slice(0, 2).map(textoAula).join(' | ')}{q.aulas.length > 2 ? ` e mais ${q.aulas.length - 2}` : ''}</p>}
                </div>
                <div className="ficha-acervo-pe">
                  {meus > 0 && (
                    <button className="btn btn-claro btn-pequeno" onClick={() => {
                      const ids = m.unidades.map((u) => u.id)
                      const ultimo = [...cesta.itens].reverse().find((id) => ids.includes(id))
                      definirCesta({ ...cesta, itens: cesta.itens.filter((id) => id !== ultimo) })
                    }} aria-label={`Tirar um ${m.nome} do pedido`}>Tirar</button>
                  )}
                  {meus > 0 && <span className="na-ficha">{meus} no pedido</span>}
                  {!m.emprestavel ? <span className="so-consulta">Só consulta</span> : <button className="btn btn-pequeno" disabled={sobra.length === 0} onClick={() => {
                    definirCesta({ ...cesta, itens: [...cesta.itens, sobra[0].id] })
                    avisar(`${m.marca} ${m.nome} entrou no pedido.`)
                  }}>
                    {q.livres.length === 0 ? 'Indisponível' : sobra.length === 0 ? 'Todos no pedido' : meus ? 'Mais um' : 'Pedir'}
                  </button>}
                </div>
              </li>
            )
          })}
        </ul>
      )}
      <BarraFicha />
    </main>
  )
}

export function BarraFicha() {
  const { cesta } = useLea()
  if (!cesta.itens.length) return null
  return (
    <div className="barra-ficha" role="region" aria-label="Pedido em montagem">
      <p><b>{cesta.itens.length} {cesta.itens.length === 1 ? 'equipamento' : 'equipamentos'}</b> | {periodo(cesta.de, cesta.ate)}</p>
      <a className="btn btn-ouro" href="#/pedir">Continuar o pedido</a>
    </div>
  )
}
