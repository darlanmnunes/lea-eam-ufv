import { useState } from 'react'
import { Cabecalho, Campo, Vazio } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { dia } from '../lib/datas'
import { tem } from '../lib/fluxo'
import type { Semestre } from '../lib/tipos'

/** 'TOPOGRAFIA II' → 'Topografia II' */
const titulo = (s: string) => s.toLowerCase().replace(/^./, (c) => c.toUpperCase()).replace(/\b(i{1,3}|iv|v|vi)\b/g, (r) => r.toUpperCase()).replace(/ À /g, ' à ')

const DIAS = ['', '', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb']

export function Aulas({ podeEditar }: { podeEditar: boolean }) {
  const { horarios, acervo, eu, recarregar, avisar } = useLea()
  const atual = horarios.semestres.find((s) => s.inicio && s.fim) ?? horarios.semestres[horarios.semestres.length - 1]
  const [semId, setSemId] = useState(atual?.id ?? '')
  const [soComUso, setSoComUso] = useState(false)
  const [novo, setNovo] = useState<Record<string, string>>({})
  const sem = horarios.semestres.find((s) => s.id === semId)
  const [datas, setDatas] = useState<Semestre | null>(null)

  if (!sem) return <main className="pagina"><Vazio titulo="Nenhum semestre importado ainda." /></main>

  const praticas = horarios.aulas.filter((a) => a.semestre === sem.id && a.tipo === 'P')
  const codigos = [...new Set(praticas.map((a) => a.disciplina))].sort()
  const linhas = codigos
    .map((codigo) => ({
      codigo,
      nome: horarios.disciplinas.find((d) => d.codigo === codigo)?.nome ?? '',
      aulas: praticas.filter((a) => a.disciplina === codigo).sort((a, b) => a.dia - b.dia || a.inicio - b.inicio),
      usos: horarios.usos.filter((u) => u.disciplina === codigo),
    }))
    .filter((l) => !soComUso || l.usos.length > 0)

  const mudar = async (disciplina: string, modeloId: string, quantidade: number) => {
    try { await api.definirUso(disciplina, modeloId, quantidade); await recarregar() } catch (e) { avisar((e as Error).message, 'erro') }
  }

  const salvarDatas = async () => {
    if (!datas) return
    try { await api.salvarSemestre(datas); await recarregar(); setDatas(null); avisar('Calendário do semestre salvo.') } catch (e) { avisar((e as Error).message, 'erro') }
  }

  return (
    <main className="pagina">
      <Cabecalho sobre="Horário das disciplinas EAM, publicado pela DTI" titulo="Aulas práticas e equipamentos">
        <div className="abas" role="tablist" aria-label="Semestre">
          {horarios.semestres.map((s) => (
            <button key={s.id} role="tab" aria-selected={s.id === sem.id} onClick={() => { setSemId(s.id); setDatas(null) }}>{s.ano}/{s.semestre}</button>
          ))}
        </div>
      </Cabecalho>

      <p className="abre-texto">
        Nem toda disciplina usa equipamento do LEA. O docente informa aqui o que cada aula prática leva a campo; nesses horários,
        as unidades ficam reservadas e saem da disponibilidade para empréstimo.
      </p>

      <div className="semestre">
        {datas ? (
          <>
            <Campo rotulo="Início das aulas"><input type="date" value={datas.inicio ?? ''} onChange={(e) => setDatas({ ...datas, inicio: e.target.value || null })} /></Campo>
            <Campo rotulo="Fim das aulas"><input type="date" value={datas.fim ?? ''} min={datas.inicio ?? undefined} onChange={(e) => setDatas({ ...datas, fim: e.target.value || null })} /></Campo>
            <button className="btn btn-pequeno" onClick={salvarDatas}>Salvar</button>
            <button className="btn btn-claro btn-pequeno" onClick={() => setDatas(null)}>Voltar</button>
          </>
        ) : (
          <>
            <p>{sem.inicio && sem.fim ? <>Aulas de <b>{dia(sem.inicio)}</b> a <b>{dia(sem.fim)}</b>. Fora desse intervalo nada fica reservado.</> : 'Semestre sem datas: as aulas dele não reservam equipamento.'}</p>
            {tem(eu, 'admin') && <button className="btn btn-claro btn-pequeno" onClick={() => setDatas(sem)}>Definir datas</button>}
          </>
        )}
        <label className="chave"><input type="checkbox" checked={soComUso} onChange={(e) => setSoComUso(e.target.checked)} /> Só as que usam equipamento</label>
      </div>

      {!podeEditar && <p className="dica">Para informar os equipamentos de uma disciplina, entre com uma conta de docente.</p>}

      <ul className="disciplinas">
        {linhas.map((l) => {
          const livres = acervo.modelos.filter((m) => !l.usos.some((u) => u.modeloId === m.id) && m.unidades.some((u) => u.situacao !== 'baixado'))
          return (
            <li key={l.codigo} className={l.usos.length ? 'usa' : ''}>
              <div className="disc-nome">
                <p className="cota">{l.codigo}</p>
                <h2>{titulo(l.nome)}</h2>
                <p className="disc-horas">{l.aulas.map((a) => `${DIAS[a.dia]} ${a.inicio}–${a.fim}h`).join(' · ')}</p>
              </div>
              <div className="disc-usos">
                {l.usos.length === 0 && <p className="sem-uso">Não usa equipamento do LEA</p>}
                {l.usos.map((u) => {
                  const m = acervo.modelos.find((x) => x.id === u.modeloId)
                  const max = m?.unidades.filter((x) => x.situacao !== 'baixado').length ?? 0
                  return (
                    <div key={u.modeloId} className="uso">
                      <span>{m ? `${m.marca} ${m.nome}` : u.modeloId}</span>
                      {podeEditar ? (
                        <span className="passo-qtd">
                          <button aria-label="Uma a menos" onClick={() => mudar(l.codigo, u.modeloId, u.quantidade - 1)}>−</button>
                          <b aria-live="polite">{u.quantidade}</b>
                          <button aria-label="Uma a mais" disabled={u.quantidade >= max} onClick={() => mudar(l.codigo, u.modeloId, u.quantidade + 1)}>+</button>
                        </span>
                      ) : <b>{u.quantidade}</b>}
                    </div>
                  )
                })}
                {podeEditar && livres.length > 0 && (
                  <div className="uso-novo">
                    <select aria-label={`Acrescentar equipamento a ${l.codigo}`} value={novo[l.codigo] ?? ''} onChange={(e) => setNovo({ ...novo, [l.codigo]: e.target.value })}>
                      <option value="">Acrescentar equipamento…</option>
                      {livres.map((m) => <option key={m.id} value={m.id}>{m.marca} {m.nome}</option>)}
                    </select>
                    <button className="btn btn-claro btn-pequeno" disabled={!novo[l.codigo]} onClick={() => { void mudar(l.codigo, novo[l.codigo], 1); setNovo({ ...novo, [l.codigo]: '' }) }}>Incluir</button>
                  </div>
                )}
              </div>
            </li>
          )
        })}
      </ul>
      {linhas.length === 0 && <Vazio titulo="Nenhuma disciplina informou equipamentos neste semestre." />}
    </main>
  )
}
