import { useEffect, useState } from 'react'
import { Cabecalho } from '../componentes/pecas'
import { useLea } from '../contexto'
import { api } from '../lib/api'
import { NOME_PAPEL } from '../lib/fluxo'
import type { Papel, Pessoa } from '../lib/tipos'

const PAPEIS: Papel[] = ['docente', 'coordenacao', 'responsavel_lea', 'tecnico', 'admin']

export function Pessoas() {
  const { eu, avisar } = useLea()
  const [lista, setLista] = useState<Pessoa[] | null>(null)
  const buscar = () => api.pessoas().then(setLista).catch((e) => { setLista([]); avisar((e as Error).message, 'erro') })
  useEffect(() => { void buscar() }, [])  // eslint-disable-line react-hooks/exhaustive-deps

  const alternar = async (p: Pessoa, papel: Papel) => {
    const papeis = p.papeis.includes(papel) ? p.papeis.filter((x) => x !== papel) : [...p.papeis, papel]
    try { await api.definirPapeis(p.id, papeis); await buscar() } catch (e) { avisar((e as Error).message, 'erro') }
  }

  return (
    <main className="pagina">
      <Cabecalho sobre="Administração" titulo="Pessoas e papéis" />
      <p className="abre-texto">Quem entra com e-mail da UFV já pode pedir equipamento. Os papéis abaixo definem quem autoriza, quem entrega e quem recebe os avisos de cada etapa.</p>
      {!lista ? <p className="carregando">Buscando pessoas…</p> : (
        <div className="rolagem">
          <table className="tabela-pessoas">
            <thead><tr><th>Pessoa</th>{PAPEIS.map((x) => <th key={x}>{NOME_PAPEL[x]}</th>)}</tr></thead>
            <tbody>
              {lista.map((p) => (
                <tr key={p.id}>
                  <th scope="row"><b>{p.nome}</b>{p.id === eu?.id ? ' (você)' : ''}<small>{p.email}</small></th>
                  {PAPEIS.map((x) => (
                    <td key={x}>
                      <input type="checkbox" aria-label={`${NOME_PAPEL[x]}: ${p.nome}`} checked={p.papeis.includes(x)} onChange={() => alternar(p, x)} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  )
}
