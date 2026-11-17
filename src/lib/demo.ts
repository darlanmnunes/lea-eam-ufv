// Modo demonstração: mesmas regras do banco (db/002_regras.sql), dados só neste navegador.
import dados from '../dados/acervo.json'
import horario from '../dados/horarios.json'
import { reservaAulas } from './disponibilidade'
import { hoje, sobrepoe } from './datas'
import type {
  Acao, Acervo, Api, DadosAcao, Emprestimo, Evento, Horarios, Modelo, NovoPedido, Ocupacao, Papel, Perfil, Pessoa, Semestre, Status, TipoEvento, Uso,
} from './tipos'

const CHAVE = 'lea-demo-v2'

const PERSONAS: Pessoa[] = [
  { id: 'p-estudante', nome: 'Marina Duarte', email: 'marina.duarte@ufv.example', matricula: '108245', telefone: '(31) 90000-0001', vinculo: 'Discente', papeis: ['solicitante'] },
  { id: 'p-coordenacao', nome: 'Prof. Renato Sales', email: 'renato.sales@ufv.example', matricula: '9120', telefone: '(31) 90000-0002', vinculo: 'Docente', papeis: ['solicitante', 'coordenacao'] },
  { id: 'p-lea', nome: 'Profa. Helena Prado', email: 'helena.prado@ufv.example', matricula: '8754', telefone: '(31) 90000-0003', vinculo: 'Docente', papeis: ['solicitante', 'responsavel_lea'] },
  { id: 'p-tecnico', nome: 'Jonas Ferraz', email: 'jonas.ferraz@ufv.example', matricula: '7431', telefone: '(31) 90000-0004', vinculo: 'Técnico', papeis: ['solicitante', 'tecnico'] },
  { id: 'p-docente', nome: 'Prof. Otávio Lemos', email: 'otavio.lemos@ufv.example', matricula: '8011', telefone: '(31) 90000-0005', vinculo: 'Docente', papeis: ['solicitante', 'docente'] },
  { id: 'p-admin', nome: 'Secretaria da área', email: 'secretaria.eam@ufv.example', matricula: '6002', telefone: '(31) 90000-0006', vinculo: 'Técnico', papeis: ['solicitante', 'admin'] },
]

const acervoInicial = (): Acervo => ({
  categorias: dados.categorias,
  modelos: dados.modelos.map((m, i): Modelo => ({
    id: m.id,
    categoriaId: m.categoria,
    marca: m.marca,
    nome: m.nome,
    descricao: m.descricao,
    foto: m.foto,
    ordem: i,
    unidades: (m.unidades as { patrimonio?: string; serie?: string; obs?: string }[]).map((u, j) => ({
      id: `${m.id}#${j + 1}`,
      modeloId: m.id,
      patrimonio: u.patrimonio ?? null,
      serie: u.serie ?? null,
      situacao: 'disponivel',
      observacao: u.obs ?? null,
    })),
  })),
})

interface Estado {
  sessao: string | null; seq: number; emprestimos: Emprestimo[]
  acervo: Acervo; semestres: Semestre[]; usos: Uso[]; papeis: Record<string, Papel[]>
}

const ATIVOS: Status[] = ['aguardando_coordenacao', 'aguardando_lea', 'aguardando_retirada', 'aguardando_ciente_retirada', 'em_uso', 'aguardando_ciente_devolucao']

function semente(): Estado {
  const quando = (dias: number, hora = 10) => {
    const d = new Date()
    d.setDate(d.getDate() + dias)
    d.setHours(hora, 12, 0, 0)
    return d.toISOString()
  }
  const [est, coord, lea, tec] = PERSONAS
  // Semestre em curso: seis semanas para trás, dez para a frente. Na versão ligada
  // ao banco, a administração informa as datas do calendário escolar.
  const emCurso = new Date().getMonth() < 6 ? 1 : 2
  let n = 0
  const ev = (tipo: TipoEvento, p: Pessoa, papel: Papel, dias: number, hora: number, observacao: string | null = null): Evento => ({
    id: `ev-${++n}`, tipo, autorId: p.id, autorNome: p.nome, autorPapel: papel, observacao, criadoEm: quando(dias, hora),
  })
  const base = (e: Partial<Emprestimo> & Pick<Emprestimo, 'id' | 'codigo' | 'status' | 'itens' | 'eventos' | 'retiradaPrevista' | 'devolucaoPrevista' | 'finalidade' | 'projeto' | 'localUso'>): Emprestimo => ({
    solicitanteId: est.id, respNome: est.nome, respMatricula: est.matricula!, respTelefone: est.telefone!, respEmail: est.email,
    participantes: [], observacao: null, criadoEm: e.eventos[0].criadoEm, ...e,
  })
  const item = (id: string, unidadeId: string, extra: Partial<Emprestimo['itens'][number]> = {}) => ({
    id, unidadeId, observacao: null, estadoRetirada: null, obsRetirada: null, estadoDevolucao: null, obsDevolucao: null, ...extra,
  })
  const ano = new Date().getFullYear()
  return {
    sessao: null,
    seq: 4,
    acervo: acervoInicial(),
    semestres: horario.semestres.map((s) => ({ ...s, inicio: s.semestre === emCurso ? hoje(-42) : null, fim: s.semestre === emCurso ? hoje(70) : null })),
    usos: [
      { disciplina: 'EAM 300', modeloId: 'geodetic-gd2i', quantidade: 4 },
      { disciplina: 'EAM 301', modeloId: 'geodetic-gd2i', quantidade: 4 },
      { disciplina: 'EAM 311', modeloId: 'geodetic-gd8i', quantidade: 2 },
    ],
    papeis: {},
    emprestimos: [
      base({
        id: 'e-1', codigo: `LEA-${ano}-0001`, status: 'encerrado',
        finalidade: 'Aula prática de poligonação', projeto: 'EAM 301 · Topografia II', localUso: 'Campus Viçosa, Recanto das Cigarras',
        retiradaPrevista: hoje(-16), devolucaoPrevista: hoje(-15), participantes: ['Turma prática T2'],
        itens: [item('i-1', 'geodetic-gd2i#1', { estadoRetirada: 'conforme', estadoDevolucao: 'conforme' }), item('i-2', 'geodetic-gd2i#2', { estadoRetirada: 'conforme', estadoDevolucao: 'com_ressalva', obsDevolucao: 'Bateria reserva voltou descarregada.' })],
        eventos: [
          ev('pedido_assinado', est, 'solicitante', -20, 9), ev('coordenacao_autorizou', coord, 'coordenacao', -20, 14),
          ev('lea_autorizou', lea, 'responsavel_lea', -19, 8), ev('tecnico_entregou', tec, 'tecnico', -16, 7, 'Dois tripés e dois prismas com bastão.'),
          ev('ciente_retirada', est, 'solicitante', -16, 7), ev('tecnico_recebeu', tec, 'tecnico', -15, 17), ev('ciente_devolucao', est, 'solicitante', -15, 17),
        ],
      }),
      base({
        id: 'e-2', codigo: `LEA-${ano}-0002`, status: 'em_uso',
        finalidade: 'Levantamento cadastral para TCC', projeto: 'TCC · Cadastro territorial em Ponte Nova', localUso: 'Ponte Nova, MG',
        retiradaPrevista: hoje(-2), devolucaoPrevista: hoje(3), participantes: ['Caio Brandão', 'Lívia Torres'],
        itens: [item('i-3', 'chc-i50#1', { estadoRetirada: 'conforme' }), item('i-4', 'topcon-es-65#1', { estadoRetirada: 'com_ressalva', obsRetirada: 'Estojo com um fecho quebrado.' })],
        eventos: [
          ev('pedido_assinado', est, 'solicitante', -6, 11), ev('coordenacao_autorizou', coord, 'coordenacao', -5, 9, 'De acordo. Atividade prevista no plano do TCC.'),
          ev('lea_autorizou', lea, 'responsavel_lea', -5, 15), ev('tecnico_entregou', tec, 'tecnico', -2, 7, 'Coletora com duas baterias carregadas.'),
          ev('ciente_retirada', est, 'solicitante', -2, 8),
        ],
      }),
      base({
        id: 'e-3', codigo: `LEA-${ano}-0003`, status: 'aguardando_coordenacao',
        finalidade: 'Varredura da fachada do prédio', projeto: 'Iniciação científica · Documentação de patrimônio edificado', localUso: 'Campus Viçosa, Edifício Arthur Bernardes',
        retiradaPrevista: hoje(6), devolucaoPrevista: hoje(7), participantes: ['Lívia Torres'],
        itens: [item('i-5', 'riegl-vz-400#1', { observacao: 'Com tripé e notebook de controle.' })],
        eventos: [ev('pedido_assinado', est, 'solicitante', 0, 8)],
      }),
    ],
  }
}

function ler(): Estado {
  try {
    const bruto = localStorage.getItem(CHAVE)
    if (bruto) return JSON.parse(bruto) as Estado
  } catch { /* armazenamento indisponível: segue em memória */ }
  return semente()
}

let estado = ler()
const ouvintes = new Set<() => void>()

function gravar() {
  try { localStorage.setItem(CHAVE, JSON.stringify(estado)) } catch { /* idem */ }
}

const comPapeis = (p: Pessoa): Pessoa => ({ ...p, papeis: estado.papeis[p.id] ?? p.papeis })

function eu(): Pessoa | null {
  const p = PERSONAS.find((x) => x.id === estado.sessao)
  return p ? comPapeis(p) : null
}

function horarios(): Horarios {
  return { semestres: estado.semestres, disciplinas: horario.disciplinas, aulas: horario.aulas, usos: estado.usos }
}

const exige = (ok: boolean, msg: string) => { if (!ok) throw new Error(msg) }
const papelDe = (...ps: Papel[]) => { const p = eu(); return !!p && ps.some((x) => p.papeis.includes(x)) }

function visiveis(p: Pessoa | null): Emprestimo[] {
  if (!p) return []
  const equipe = p.papeis.some((x) => x !== 'solicitante' && x !== 'docente')
  return estado.emprestimos.filter((e) => equipe || e.solicitanteId === p.id)
}

function ocupacoes(): Ocupacao[] {
  return estado.emprestimos
    .filter((e) => ATIVOS.includes(e.status))
    .flatMap((e) => e.itens.map((i) => ({ unidadeId: i.unidadeId, de: e.retiradaPrevista, ate: e.devolucaoPrevista, status: e.status })))
}

const limpa = (s?: string | null) => (s && s.trim() ? s.trim() : null)

function avancar(id: string, acao: Acao, d: DadosAcao = {}) {
  const p = eu()
  if (!p) throw new Error('Entre para continuar')
  const e = estado.emprestimos.find((x) => x.id === id)
  if (!e) throw new Error('Empréstimo não encontrado')
  const dono = e.solicitanteId === p.id
  const tem = (x: Papel) => p.papeis.includes(x)
  const obs = limpa(d.observacao)
  let tipo: TipoEvento
  let papel: Papel
  let novo: Status = e.status

  if ((acao === 'autorizar' || acao === 'recusar') && e.status === 'aguardando_coordenacao') {
    if (!tem('coordenacao')) throw new Error('Esta etapa é da coordenação da área')
    papel = 'coordenacao'
    tipo = acao === 'autorizar' ? 'coordenacao_autorizou' : 'coordenacao_recusou'
    novo = acao === 'autorizar' ? 'aguardando_lea' : 'recusado'
  } else if ((acao === 'autorizar' || acao === 'recusar') && e.status === 'aguardando_lea') {
    if (!tem('responsavel_lea')) throw new Error('Esta etapa é do responsável pelo LEA')
    papel = 'responsavel_lea'
    tipo = acao === 'autorizar' ? 'lea_autorizou' : 'lea_recusou'
    novo = acao === 'autorizar' ? 'aguardando_retirada' : 'recusado'
  } else if (acao === 'entregar' && e.status === 'aguardando_retirada') {
    if (!tem('tecnico')) throw new Error('A entrega é registrada pelo técnico do LEA')
    if (e.itens.some((i) => !d.itens?.find((c) => c.itemId === i.id))) throw new Error('Confira todos os itens antes de entregar')
    for (const c of d.itens!) {
      const i = e.itens.find((x) => x.id === c.itemId)!
      i.estadoRetirada = c.estado
      i.obsRetirada = limpa(c.obs)
    }
    papel = 'tecnico'; tipo = 'tecnico_entregou'; novo = 'aguardando_ciente_retirada'
  } else if (acao === 'ciente_retirada' && e.status === 'aguardando_ciente_retirada') {
    if (!dono) throw new Error('O ciente de retirada é de quem fez o pedido')
    papel = 'solicitante'; tipo = 'ciente_retirada'; novo = 'em_uso'
  } else if (acao === 'receber' && e.status === 'em_uso') {
    if (!tem('tecnico')) throw new Error('A devolução é conferida pelo técnico do LEA')
    if (e.itens.some((i) => !d.itens?.find((c) => c.itemId === i.id))) throw new Error('Confira todos os itens antes de receber')
    if (d.itens!.some((c) => c.estado === 'com_ressalva' && !limpa(c.obs))) throw new Error('Descreva a ressalva de cada item devolvido com problema')
    for (const c of d.itens!) {
      const i = e.itens.find((x) => x.id === c.itemId)!
      i.estadoDevolucao = c.estado
      i.obsDevolucao = limpa(c.obs)
    }
    papel = 'tecnico'; tipo = 'tecnico_recebeu'; novo = 'aguardando_ciente_devolucao'
  } else if (acao === 'ciente_devolucao' && e.status === 'aguardando_ciente_devolucao') {
    if (!dono) throw new Error('O ciente de devolução é de quem fez o pedido')
    papel = 'solicitante'; tipo = 'ciente_devolucao'; novo = 'encerrado'
  } else if (acao === 'cancelar' && ['aguardando_coordenacao', 'aguardando_lea', 'aguardando_retirada'].includes(e.status)) {
    if (!dono) throw new Error('Só quem pediu pode cancelar')
    papel = 'solicitante'; tipo = 'cancelado'; novo = 'cancelado'
  } else if (acao === 'ocorrencia' && ['em_uso', 'aguardando_ciente_devolucao'].includes(e.status)) {
    if (!dono && !tem('tecnico')) throw new Error('Sem permissão')
    if (!obs) throw new Error('Descreva a ocorrência')
    papel = dono ? 'solicitante' : 'tecnico'; tipo = 'ocorrencia'
  } else if (acao === 'pedir_prorrogacao' && e.status === 'em_uso') {
    if (!dono) throw new Error('Só quem pediu pode solicitar prorrogação')
    if (!obs) throw new Error('Justifique a prorrogação')
    papel = 'solicitante'; tipo = 'prorrogacao_pedida'
  } else if (acao === 'autorizar_prorrogacao' && e.status === 'em_uso') {
    if (!tem('responsavel_lea')) throw new Error('A prorrogação é autorizada pelo responsável pelo LEA')
    const nova = d.novaDevolucao
    if (!nova || nova <= e.devolucaoPrevista) throw new Error('Informe a nova data de devolução')
    const meus = new Set(e.itens.map((i) => i.unidadeId))
    const choque = estado.emprestimos.some((o) => o.id !== e.id && ATIVOS.includes(o.status) &&
      o.itens.some((i) => meus.has(i.unidadeId)) && sobrepoe(o.retiradaPrevista, o.devolucaoPrevista, e.devolucaoPrevista, nova))
    if (choque) throw new Error('Há outro pedido para esse equipamento no período da prorrogação')
    e.devolucaoPrevista = nova
    papel = 'responsavel_lea'; tipo = 'prorrogacao_autorizada'
  } else {
    throw new Error('Essa ação não cabe na etapa atual do pedido')
  }
  if ((tipo === 'coordenacao_recusou' || tipo === 'lea_recusou') && !obs) throw new Error('Explique o motivo da recusa')

  e.status = novo
  e.eventos.push({ id: `ev-${Date.now()}`, tipo, autorId: p.id, autorNome: p.nome, autorPapel: papel, observacao: obs, criadoEm: new Date().toISOString() })
}

function criar(n: NovoPedido): string {
  const p = eu()
  if (!p) throw new Error('Entre para continuar')
  if (n.retirada < hoje()) throw new Error('A retirada não pode ser no passado')
  if (n.devolucao < n.retirada) throw new Error('A devolução vem depois da retirada')
  if (!n.itens.length) throw new Error('Escolha ao menos um equipamento')
  const oc = ocupacoes()
  for (const i of n.itens) {
    if (oc.some((o) => o.unidadeId === i.unidadeId && sobrepoe(o.de, o.ate, n.retirada, n.devolucao))) {
      throw new Error('Uma das unidades escolhidas já está comprometida nesse período')
    }
  }
  const todas = estado.acervo.modelos.flatMap((m) => m.unidades)
  for (const m of estado.acervo.modelos) {
    const pedidas = n.itens.filter((i) => todas.find((u) => u.id === i.unidadeId)?.modeloId === m.id).length
    if (!pedidas) continue
    const total = m.unidades.filter((u) => u.situacao === 'disponivel').length
    const ocupadas = new Set(oc.filter((o) => m.unidades.some((u) => u.id === o.unidadeId) && sobrepoe(o.de, o.ate, n.retirada, n.devolucao)).map((o) => o.unidadeId)).size
    if (ocupadas + pedidas + reservaAulas(horarios(), m.id, n.retirada, n.devolucao) > total) {
      throw new Error(`Não há unidades livres de ${m.marca} ${m.nome} nesse período: parte delas está reservada para aulas práticas`)
    }
  }
  const id = `e-${Date.now()}`
  const agora = new Date().toISOString()
  estado.emprestimos.push({
    id,
    codigo: `LEA-${new Date().getFullYear()}-${String(estado.seq++).padStart(4, '0')}`,
    solicitanteId: p.id, respNome: p.nome, respMatricula: p.matricula ?? '', respTelefone: p.telefone ?? '', respEmail: p.email,
    finalidade: n.finalidade.trim(), projeto: n.projeto.trim(), localUso: n.localUso.trim(),
    retiradaPrevista: n.retirada, devolucaoPrevista: n.devolucao,
    participantes: n.participantes, observacao: limpa(n.observacao), status: 'aguardando_coordenacao', criadoEm: agora,
    itens: n.itens.map((i, k) => ({ id: `${id}-i${k}`, unidadeId: i.unidadeId, observacao: limpa(i.observacao), estadoRetirada: null, obsRetirada: null, estadoDevolucao: null, obsDevolucao: null })),
    eventos: [{ id: `ev-${Date.now()}`, tipo: 'pedido_assinado', autorId: p.id, autorNome: p.nome, autorPapel: 'solicitante', observacao: limpa(n.observacao), criadoEm: agora }],
  })
  return id
}

const copia = <T,>(v: T): T => JSON.parse(JSON.stringify(v))
const avisar = () => ouvintes.forEach((f) => f())

export const demo: Api = {
  modo: 'demo',
  async sessao() { return eu() },
  aoMudarSessao(fn) { ouvintes.add(fn); return () => ouvintes.delete(fn) },
  async entrar(id) { estado.sessao = id; gravar(); avisar() },
  async sair() { estado.sessao = null; gravar(); avisar() },
  async salvarPerfil(_p: Perfil) { /* personas da demonstração já vêm completas */ },
  personas: () => PERSONAS.map(comPapeis),
  async acervo() { return copia(estado.acervo) },
  async ocupacao() { return ocupacoes() },
  async emprestimos() { return copia(visiveis(eu())).sort((a, b) => b.criadoEm.localeCompare(a.criadoEm)) },
  async emprestimo(id) { return copia(visiveis(eu()).find((e) => e.id === id) ?? null) },
  async criar(n) { const id = criar(n); gravar(); return id },
  async avancar(id, acao, d) { avancar(id, acao, d); gravar() },
  async horarios() { return copia(horarios()) },
  async definirUso(disciplina, modeloId, quantidade) {
    exige(papelDe('docente', 'coordenacao', 'admin'), 'O uso em aula é informado pelos docentes')
    const m = estado.acervo.modelos.find((x) => x.id === modeloId)
    exige(!!m && quantidade <= m.unidades.filter((u) => u.situacao !== 'baixado').length, 'O laboratório não tem tantas unidades desse modelo')
    estado.usos = estado.usos.filter((u) => !(u.disciplina === disciplina && u.modeloId === modeloId))
    if (quantidade > 0) estado.usos.push({ disciplina, modeloId, quantidade })
    gravar()
  },
  async salvarSemestre(s) {
    exige(papelDe('admin'), 'Só a administração define o calendário')
    exige(!s.inicio || !s.fim || s.fim >= s.inicio, 'O fim do semestre vem depois do início')
    estado.semestres = estado.semestres.map((x) => (x.id === s.id ? s : x))
    gravar()
  },
  async salvarModelo(d) {
    exige(papelDe('tecnico', 'responsavel_lea', 'admin'), 'O acervo é cadastrado pelo técnico do LEA')
    exige(d.marca.trim().length > 0 && d.nome.trim().length > 0, 'Informe marca e modelo')
    const atual = estado.acervo.modelos.find((m) => m.id === d.id)
    if (atual) Object.assign(atual, { categoriaId: d.categoriaId, marca: d.marca.trim(), nome: d.nome.trim(), descricao: limpa(d.descricao), foto: d.foto })
    else estado.acervo.modelos.push({ id: `m-${Date.now()}`, categoriaId: d.categoriaId, marca: d.marca.trim(), nome: d.nome.trim(), descricao: limpa(d.descricao), foto: d.foto, ordem: estado.acervo.modelos.length, unidades: [] })
    gravar()
  },
  async salvarUnidade(d) {
    exige(papelDe('tecnico', 'responsavel_lea', 'admin'), 'O acervo é cadastrado pelo técnico do LEA')
    const m = estado.acervo.modelos.find((x) => x.id === d.modeloId)
    exige(!!m, 'Modelo não encontrado')
    const pat = limpa(d.patrimonio)
    exige(!pat || !estado.acervo.modelos.some((x) => x.unidades.some((u) => u.patrimonio === pat && u.id !== d.id)), 'Já existe uma unidade com esse patrimônio')
    const emUso = ocupacoes().some((o) => o.unidadeId === d.id)
    exige(d.situacao === 'disponivel' || !emUso, 'Essa unidade está num pedido em andamento; encerre o pedido antes de tirá-la de circulação')
    const campos = { patrimonio: pat, serie: limpa(d.serie), situacao: d.situacao, observacao: limpa(d.observacao) }
    const atual = m!.unidades.find((u) => u.id === d.id)
    if (atual) Object.assign(atual, campos)
    else m!.unidades.push({ id: `${m!.id}#${Date.now()}`, modeloId: m!.id, ...campos })
    gravar()
  },
  async pessoas() {
    exige(papelDe('admin'), 'Só a administração vê o cadastro de pessoas')
    return PERSONAS.map(comPapeis)
  },
  async definirPapeis(id, papeis) {
    exige(papelDe('admin'), 'Só a administração define papéis')
    exige(id !== estado.sessao || papeis.includes('admin'), 'Você não pode retirar o próprio acesso de administração')
    estado.papeis[id] = [...new Set<Papel>(['solicitante', ...papeis])]
    gravar(); avisar()
  },
}

export function reiniciarDemo() {
  const sessao = estado.sessao
  estado = { ...semente(), sessao }
  gravar()
  avisar()
}
