import { BarraFicha, Periodo } from './Acervo'
import { Foto } from '../componentes/pecas'
import { useLea } from '../contexto'
import { dia, periodo } from '../lib/datas'
import { NOME_ESTADO, quadro, textoAula } from '../lib/disponibilidade'
import { cota, identificacao } from '../lib/fluxo'

export function Equipamento({ id }: { id: string }) {
  const { acervo, ocupacao, horarios, cesta, definirCesta } = useLea()
  const m = acervo.modelos.find((x) => x.id === id)
  if (!m) return <main className="pagina"><h1>Equipamento não encontrado</h1><p><a href="#/">Voltar ao acervo</a></p></main>
  const c = acervo.categorias.find((x) => x.id === m.categoriaId)!
  const q = quadro(m, ocupacao, horarios, cesta.de, cesta.ate)

  return (
    <main className="pagina">
      <p className="trilha"><a href="#/">Acervo</a> / {c.nome}</p>
      <div className="equip">
        <Foto m={m} grande />
        <div className="equip-dados">
          <p className="cota">{c.sigla} | {c.nome}</p>
          <h1>{m.marca} {m.nome}</h1>
          {m.descricao && <p className="equip-desc">{m.descricao}</p>}
          <Periodo />

          <h2>Unidades em {periodo(cesta.de, cesta.ate)}</h2>
          <ul className="unidades">
            {q.unidades.map(({ unidade: u, estado, ate }) => {
              const dentro = cesta.itens.includes(u.id)
              return (
                <li key={u.id}>
                  <i className={`marca marca-${estado}`} aria-hidden="true" />
                  <div>
                    <p className="unidade-id">{cota(c.sigla, u)}</p>
                    <p className="unidade-nota">
                      {NOME_ESTADO[estado]}{estado === 'emprestado' && ate ? ` até ${dia(ate)}` : ''}
                      {u.observacao ? ` | ${u.observacao}` : ` | ${identificacao(u)}`}
                    </p>
                  </div>
                  {estado === 'livre' && (
                    <button className={`btn btn-pequeno${dentro ? ' btn-claro' : ''}`} onClick={() =>
                      definirCesta({ ...cesta, itens: dentro ? cesta.itens.filter((x) => x !== u.id) : [...cesta.itens, u.id] })}>
                      {dentro ? 'Tirar do pedido' : 'Pedir esta'}
                    </button>
                  )}
                </li>
              )
            })}
          </ul>

          {q.aulas.length > 0 && (
            <>
              <h2>Aulas práticas que usam este modelo</h2>
              <ul className="lista-aulas">
                {q.aulas.map((a) => (
                  <li key={`${a.disciplina}${a.turma}${a.dia}${a.inicio}`}>
                    <b>{textoAula(a)}</b> {a.nome.toLowerCase().replace(/\b(i{1,3}|iv)\b/g, (r) => r.toUpperCase())} | {a.quantidade} {a.quantidade === 1 ? 'unidade' : 'unidades'}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      </div>
      <BarraFicha />
    </main>
  )
}
