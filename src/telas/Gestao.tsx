import { useState } from 'react'
import { Cabecalho, Campo, Foto } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { hoje } from '../lib/datas'
import { NOME_ESTADO, quadro } from '../lib/disponibilidade'
import { cota } from '../lib/fluxo'
import type { DadosModelo, DadosUnidade, Situacao } from '../lib/tipos'

const SITUACOES: [Situacao, string][] = [
  ['disponivel', 'Em circulação'],
  ['manutencao', 'Em manutenção'],
  ['estoque', 'Em estoque'],
  ['baixado', 'Baixado do acervo'],
]

const unidadeNova = (modeloId: string): DadosUnidade => ({ modeloId, patrimonio: '', serie: '', situacao: 'disponivel', observacao: '' })

export function Gestao() {
  const { acervo, ocupacao, horarios, recarregar, avisar } = useLea()
  const [modelo, setModelo] = useState<DadosModelo | null>(null)
  const [un, setUn] = useState<DadosUnidade | null>(null)
  const [verBaixados, setVerBaixados] = useState(false)

  const todas = acervo.modelos.flatMap((m) => m.unidades)
  const conta = (s: Situacao) => todas.filter((u) => u.situacao === s).length
  const emprestadas = new Set(ocupacao.filter((o) => o.de <= hoje() && o.ate >= hoje()).map((o) => o.unidadeId)).size

  const salvarModelo = async () => {
    try { await api.salvarModelo(modelo!); await recarregar(); setModelo(null); avisar('Modelo salvo.') } catch (e) { avisar((e as Error).message, 'erro') }
  }
  const salvarUnidade = async () => {
    try { await api.salvarUnidade(un!); await recarregar(); setUn(null); avisar('Unidade salva.') } catch (e) { avisar((e as Error).message, 'erro') }
  }

  return (
    <main className="pagina">
      <Cabecalho sobre="Cadastro do laboratório" titulo="Equipamentos">
        <button className="btn" onClick={() => { setUn(null); setModelo({ categoriaId: acervo.categorias[0]?.id ?? '', marca: '', nome: '', descricao: '', foto: null }) }}>Cadastrar modelo</button>
      </Cabecalho>

      <dl className="placar">
        <div><dt>Em circulação</dt><dd>{conta('disponivel')}</dd></div>
        <div><dt>Emprestadas hoje</dt><dd>{emprestadas}</dd></div>
        <div><dt>Em manutenção</dt><dd>{conta('manutencao')}</dd></div>
        <div><dt>Em estoque</dt><dd>{conta('estoque')}</dd></div>
        <div><dt>Baixadas</dt><dd>{conta('baixado')}</dd></div>
      </dl>

      {modelo && (
        <section className="bloco editor" aria-label="Modelo">
          <h2>{modelo.id ? 'Editar modelo' : 'Novo modelo'}</h2>
          <div className="grade-campos">
            <Campo rotulo="Categoria">
              <select value={modelo.categoriaId} onChange={(e) => setModelo({ ...modelo, categoriaId: e.target.value })}>
                {acervo.categorias.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
              </select>
            </Campo>
            <Campo rotulo="Marca"><input type="text" value={modelo.marca} onChange={(e) => setModelo({ ...modelo, marca: e.target.value })} /></Campo>
            <Campo rotulo="Modelo"><input type="text" value={modelo.nome} onChange={(e) => setModelo({ ...modelo, nome: e.target.value })} /></Campo>
            <Campo rotulo="Endereço da foto" ajuda="Opcional. Link de uma imagem."><input type="url" value={modelo.foto ?? ''} onChange={(e) => setModelo({ ...modelo, foto: e.target.value || null })} /></Campo>
            <Campo rotulo="Descrição" largo><textarea rows={2} value={modelo.descricao} onChange={(e) => setModelo({ ...modelo, descricao: e.target.value })} /></Campo>
          </div>
          <div className="vez-botoes">
            <button className="btn" onClick={salvarModelo}>Salvar modelo</button>
            <button className="btn btn-claro" onClick={() => setModelo(null)}>Voltar</button>
          </div>
        </section>
      )}

      <label className="chave"><input type="checkbox" checked={verBaixados} onChange={(e) => setVerBaixados(e.target.checked)} /> Mostrar unidades baixadas</label>

      <ul className="gestao">
        {acervo.modelos.map((m) => {
          const c = acervo.categorias.find((x) => x.id === m.categoriaId)!
          const q = quadro(m, ocupacao, horarios, hoje(), hoje())
          const unidades = m.unidades.filter((u) => verBaixados || u.situacao !== 'baixado')
          return (
            <li key={m.id}>
              <div className="gestao-modelo">
                <Foto m={m} />
                <div>
                  <p className="cota">{c.sigla} | {c.nome}</p>
                  <h2>{m.marca} {m.nome}</h2>
                  <p className="gestao-botoes">
                    <button className="btn-texto" onClick={() => { setUn(null); setModelo({ id: m.id, categoriaId: m.categoriaId, marca: m.marca, nome: m.nome, descricao: m.descricao ?? '', foto: m.foto }); window.scrollTo(0, 0) }}>Editar modelo</button>
                    <button className="btn-texto" onClick={() => { setModelo(null); setUn(unidadeNova(m.id)) }}>Acrescentar unidade</button>
                  </p>
                </div>
              </div>
              <table className="tabela-unidades">
                <thead><tr><th>Cota</th><th>Hoje</th><th>Observação</th><th><span className="so-leitor">Ações</span></th></tr></thead>
                <tbody>
                  {unidades.map((u) => {
                    const estado = u.situacao === 'baixado' ? null : q.unidades.find((x) => x.unidade.id === u.id)?.estado
                    return (
                      <tr key={u.id}>
                        <td className="unidade-id">{cota(c.sigla, u)}</td>
                        <td>{estado ? <span className={`estado estado-${estado}`}><i className={`marca marca-${estado}`} aria-hidden="true" />{NOME_ESTADO[estado]}</span> : 'Baixada'}</td>
                        <td>{u.observacao ?? ''}</td>
                        <td><button className="btn-texto" onClick={() => { setModelo(null); setUn({ id: u.id, modeloId: m.id, patrimonio: u.patrimonio ?? '', serie: u.serie ?? '', situacao: u.situacao, observacao: u.observacao ?? '' }) }}>Editar</button></td>
                      </tr>
                    )
                  })}
                  {unidades.length === 0 && <tr><td colSpan={4}>Nenhuma unidade cadastrada.</td></tr>}
                </tbody>
              </table>
              {un && un.modeloId === m.id && (
                <section className="editor editor-unidade" aria-label="Unidade">
                  <h3>{un.id ? 'Editar unidade' : 'Nova unidade'}</h3>
                  <div className="grade-campos">
                    <Campo rotulo="Patrimônio UFV"><input type="text" inputMode="numeric" value={un.patrimonio} onChange={(e) => setUn({ ...un, patrimonio: e.target.value })} /></Campo>
                    <Campo rotulo="Número de série" ajuda="Quando não há patrimônio."><input type="text" value={un.serie} onChange={(e) => setUn({ ...un, serie: e.target.value })} /></Campo>
                    <Campo rotulo="Situação">
                      <select value={un.situacao} onChange={(e) => setUn({ ...un, situacao: e.target.value as Situacao })}>
                        {SITUACOES.map(([v, n]) => <option key={v} value={v}>{n}</option>)}
                      </select>
                    </Campo>
                    <Campo rotulo="Observação" ajuda="Ex.: aguardando calibração, fecho do estojo quebrado."><input type="text" value={un.observacao} onChange={(e) => setUn({ ...un, observacao: e.target.value })} /></Campo>
                  </div>
                  <div className="vez-botoes">
                    <button className="btn" onClick={salvarUnidade}>Salvar unidade</button>
                    <button className="btn btn-claro" onClick={() => setUn(null)}>Voltar</button>
                  </div>
                </section>
              )}
            </li>
          )
        })}
      </ul>
    </main>
  )
}
