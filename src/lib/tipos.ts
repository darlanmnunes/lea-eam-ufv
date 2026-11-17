export type Papel = 'solicitante' | 'docente' | 'coordenacao' | 'responsavel_lea' | 'tecnico' | 'admin'

export type Situacao = 'disponivel' | 'manutencao' | 'estoque' | 'baixado'

export type Status =
  | 'aguardando_coordenacao'
  | 'aguardando_lea'
  | 'aguardando_retirada'
  | 'aguardando_ciente_retirada'
  | 'em_uso'
  | 'aguardando_ciente_devolucao'
  | 'encerrado'
  | 'recusado'
  | 'cancelado'

export type TipoEvento =
  | 'pedido_assinado'
  | 'coordenacao_autorizou'
  | 'coordenacao_recusou'
  | 'lea_autorizou'
  | 'lea_recusou'
  | 'tecnico_entregou'
  | 'ciente_retirada'
  | 'tecnico_recebeu'
  | 'ciente_devolucao'
  | 'prorrogacao_pedida'
  | 'prorrogacao_autorizada'
  | 'ocorrencia'
  | 'cancelado'

export type Acao =
  | 'autorizar'
  | 'recusar'
  | 'entregar'
  | 'ciente_retirada'
  | 'receber'
  | 'ciente_devolucao'
  | 'cancelar'
  | 'ocorrencia'
  | 'pedir_prorrogacao'
  | 'autorizar_prorrogacao'

export type EstadoItem = 'conforme' | 'com_ressalva'

export interface Pessoa {
  id: string
  nome: string
  email: string
  matricula: string | null
  telefone: string | null
  vinculo: string | null
  papeis: Papel[]
  /** conta criada, mas sem cadastro preenchido */
  incompleto?: boolean
}

export interface Categoria { id: string; nome: string; sigla: string; ordem: number }

export interface Unidade {
  id: string
  modeloId: string
  patrimonio: string | null
  serie: string | null
  situacao: Situacao
  observacao: string | null
}

export interface Modelo {
  id: string
  categoriaId: string
  marca: string
  nome: string
  descricao: string | null
  foto: string | null
  ordem: number
  unidades: Unidade[]
}

export interface Acervo { categorias: Categoria[]; modelos: Modelo[] }

export interface Ocupacao { unidadeId: string; de: string; ate: string; status: Status }

export interface Item {
  id: string
  unidadeId: string
  observacao: string | null
  estadoRetirada: EstadoItem | null
  obsRetirada: string | null
  estadoDevolucao: EstadoItem | null
  obsDevolucao: string | null
}

export interface Evento {
  id: string
  tipo: TipoEvento
  autorId: string
  autorNome: string
  autorPapel: Papel
  observacao: string | null
  criadoEm: string
}

export interface Emprestimo {
  id: string
  codigo: string
  solicitanteId: string
  respNome: string
  respMatricula: string
  respTelefone: string
  respEmail: string
  finalidade: string
  projeto: string
  localUso: string
  retiradaPrevista: string
  devolucaoPrevista: string
  participantes: string[]
  observacao: string | null
  status: Status
  criadoEm: string
  itens: Item[]
  eventos: Evento[]
}

export interface NovoPedido {
  finalidade: string
  projeto: string
  localUso: string
  retirada: string
  devolucao: string
  participantes: string[]
  observacao: string
  itens: { unidadeId: string; observacao: string }[]
}

export interface Conferencia { itemId: string; estado: EstadoItem; obs: string }

export interface DadosAcao {
  observacao?: string
  itens?: Conferencia[]
  novaDevolucao?: string
}

export interface Semestre { id: string; ano: number; semestre: number; inicio: string | null; fim: string | null }
export interface Disciplina { codigo: string; nome: string }
export interface Aula { semestre: string; disciplina: string; tipo: string; turma: number; dia: number; inicio: number; fim: number; sala: string | null }
export interface Uso { disciplina: string; modeloId: string; quantidade: number }
export interface Horarios { semestres: Semestre[]; disciplinas: Disciplina[]; aulas: Aula[]; usos: Uso[] }

export interface DadosModelo { id?: string; categoriaId: string; marca: string; nome: string; descricao: string; foto: string | null }
export interface DadosUnidade { id?: string; modeloId: string; patrimonio: string; serie: string; situacao: Situacao; observacao: string }

export interface Perfil { nome: string; matricula: string; telefone: string; vinculo: string }

export interface Api {
  modo: 'demo' | 'supabase'
  sessao(): Promise<Pessoa | null>
  aoMudarSessao(fn: () => void): () => void
  /** demo: id da persona | supabase: e-mail para o link de acesso */
  entrar(chave: string): Promise<void>
  sair(): Promise<void>
  salvarPerfil(p: Perfil): Promise<void>
  personas(): Pessoa[]
  acervo(): Promise<Acervo>
  ocupacao(): Promise<Ocupacao[]>
  emprestimos(): Promise<Emprestimo[]>
  emprestimo(id: string): Promise<Emprestimo | null>
  criar(p: NovoPedido): Promise<string>
  avancar(id: string, acao: Acao, dados?: DadosAcao): Promise<void>
  horarios(): Promise<Horarios>
  definirUso(disciplina: string, modeloId: string, quantidade: number): Promise<void>
  salvarSemestre(s: Semestre): Promise<void>
  salvarModelo(m: DadosModelo): Promise<void>
  salvarUnidade(u: DadosUnidade): Promise<void>
  pessoas(): Promise<Pessoa[]>
  definirPapeis(id: string, papeis: Papel[]): Promise<void>
}
