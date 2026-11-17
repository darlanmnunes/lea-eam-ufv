import type { Acao, Emprestimo, Papel, Pessoa, Status, TipoEvento, Unidade } from './tipos'
import { hoje } from './datas'

export const NOME_PAPEL: Record<Papel, string> = {
  solicitante: 'Responsável pelo pedido',
  docente: 'Docente',
  admin: 'Administração',
  coordenacao: 'Coordenação da área acadêmica',
  responsavel_lea: 'Responsável pelo LEA',
  tecnico: 'Técnico do LEA',
}

/** nome do papel no meio de uma frase */
export const papelNaFrase = (p: Papel) => NOME_PAPEL[p].toLowerCase().replace('lea', 'LEA')

export const NOME_STATUS: Record<Status, string> = {
  aguardando_coordenacao: 'Na coordenação',
  aguardando_lea: 'No responsável pelo LEA',
  aguardando_retirada: 'Pronto para retirar',
  aguardando_ciente_retirada: 'Falta o ciente de retirada',
  em_uso: 'Em uso',
  aguardando_ciente_devolucao: 'Falta o ciente de devolução',
  encerrado: 'Encerrado',
  recusado: 'Recusado',
  cancelado: 'Cancelado',
}

export const TOM_STATUS: Record<Status, 'espera' | 'ativo' | 'feito' | 'parado'> = {
  aguardando_coordenacao: 'espera',
  aguardando_lea: 'espera',
  aguardando_retirada: 'espera',
  aguardando_ciente_retirada: 'espera',
  em_uso: 'ativo',
  aguardando_ciente_devolucao: 'espera',
  encerrado: 'feito',
  recusado: 'parado',
  cancelado: 'parado',
}

export const TEXTO_EVENTO: Record<TipoEvento, string> = {
  pedido_assinado: 'Assinou o termo e enviou o pedido',
  coordenacao_autorizou: 'Autorizou',
  coordenacao_recusou: 'Recusou',
  lea_autorizou: 'Autorizou',
  lea_recusou: 'Recusou',
  tecnico_entregou: 'Conferiu e entregou',
  ciente_retirada: 'Ciente da retirada',
  tecnico_recebeu: 'Conferiu e recebeu',
  ciente_devolucao: 'Ciente da devolução',
  prorrogacao_pedida: 'Pediu prorrogação',
  prorrogacao_autorizada: 'Autorizou a prorrogação',
  ocorrencia: 'Registrou ocorrência',
  cancelado: 'Cancelou o pedido',
}

/** As seis casas da ficha, na ordem do termo. */
export interface Etapa {
  id: string
  titulo: string
  quem: Papel
  evento: TipoEvento
  /** status em que esta casa é a da vez */
  vez: Status
  verbo: string
}

export const ETAPAS: Etapa[] = [
  { id: 'pedido', titulo: 'Pedido', quem: 'solicitante', evento: 'pedido_assinado', vez: 'aguardando_coordenacao', verbo: 'Assinado' },
  { id: 'coordenacao', titulo: 'Coordenação', quem: 'coordenacao', evento: 'coordenacao_autorizou', vez: 'aguardando_coordenacao', verbo: 'Autorizado' },
  { id: 'lea', titulo: 'LEA', quem: 'responsavel_lea', evento: 'lea_autorizou', vez: 'aguardando_lea', verbo: 'Autorizado' },
  { id: 'entrega', titulo: 'Entrega', quem: 'tecnico', evento: 'tecnico_entregou', vez: 'aguardando_retirada', verbo: 'Entregue' },
  { id: 'retirada', titulo: 'Retirada', quem: 'solicitante', evento: 'ciente_retirada', vez: 'aguardando_ciente_retirada', verbo: 'Ciente' },
  { id: 'recebimento', titulo: 'Recebimento', quem: 'tecnico', evento: 'tecnico_recebeu', vez: 'em_uso', verbo: 'Recebido' },
  { id: 'devolucao', titulo: 'Devolução', quem: 'solicitante', evento: 'ciente_devolucao', vez: 'aguardando_ciente_devolucao', verbo: 'Ciente' },
]

export function ehEquipe(p: Pessoa | null): boolean {
  return !!p && p.papeis.some((x) => x !== 'solicitante' && x !== 'docente')
}

export const tem = (p: Pessoa | null, ...papeis: Papel[]) => !!p && papeis.some((x) => p.papeis.includes(x))
export const cuidaDoAcervo = (p: Pessoa | null) => tem(p, 'tecnico', 'responsavel_lea', 'admin')
export const informaAulas = (p: Pessoa | null) => tem(p, 'docente', 'coordenacao', 'admin')

export interface Pendencia { acao: Acao; rotulo: string; explica: string; recusa?: boolean; confere?: 'retirada' | 'devolucao' }

/** O que esta pessoa pode assinar agora neste pedido. */
export function pendencia(e: Emprestimo, p: Pessoa | null): Pendencia | null {
  if (!p) return null
  const dono = e.solicitanteId === p.id
  const tem = (x: Papel) => p.papeis.includes(x)
  switch (e.status) {
    case 'aguardando_coordenacao':
      return tem('coordenacao') ? { acao: 'autorizar', rotulo: 'Autorizar pedido', explica: 'Você assina como coordenação da área acadêmica.', recusa: true } : null
    case 'aguardando_lea':
      return tem('responsavel_lea') ? { acao: 'autorizar', rotulo: 'Autorizar retirada', explica: 'Você assina como responsável pelo LEA.', recusa: true } : null
    case 'aguardando_retirada':
      return tem('tecnico') ? { acao: 'entregar', rotulo: 'Registrar entrega', explica: 'Confira cada item no balcão antes de entregar.', confere: 'retirada' } : null
    case 'aguardando_ciente_retirada':
      return dono ? { acao: 'ciente_retirada', rotulo: 'Dar ciente da retirada', explica: 'Confirme que recebeu os equipamentos como o técnico descreveu.' } : null
    case 'em_uso':
      return tem('tecnico') ? { acao: 'receber', rotulo: 'Registrar devolução', explica: 'Confira cada item devolvido e anote ressalvas.', confere: 'devolucao' } : null
    case 'aguardando_ciente_devolucao':
      return dono ? { acao: 'ciente_devolucao', rotulo: 'Dar ciente da devolução', explica: 'Confirme a devolução e as observações do técnico.' } : null
    default:
      return null
  }
}

export function aguardandoQuem(e: Emprestimo): string | null {
  const etapa = ETAPAS.find((x, i) => i > 0 && x.vez === e.status)
  return etapa ? papelNaFrase(etapa.quem) : null
}

export function atrasado(e: Emprestimo): boolean {
  return e.status === 'em_uso' && e.devolucaoPrevista < hoje()
}

export function cota(sigla: string, u: Unidade): string {
  if (u.patrimonio) return `${sigla} ${u.patrimonio}`
  if (u.serie) return `${sigla} s/n ${u.serie}`
  return `${sigla} sem registro`
}

export function identificacao(u: Unidade): string {
  if (u.patrimonio) return `Patrimônio ${u.patrimonio}`
  if (u.serie) return `Nº de série ${u.serie}`
  return 'Sem patrimônio'
}

export const DECLARACOES = [
  'Os equipamentos são patrimônio da UFV e serão usados só para a finalidade informada neste termo.',
  'Comunico de imediato qualquer dano, extravio, furto ou ocorrência que afete os equipamentos.',
  'Devolvo os equipamentos na data prevista ou justifico formalmente a necessidade de prorrogação.',
]

export const PREAMBULO =
  'Pelo presente termo, o(a) servidor(a)/discente abaixo identificado(a) declara receber os equipamentos relacionados neste documento para utilização em atividade institucional de ensino, pesquisa, extensão ou prestação de serviços vinculada à Universidade Federal de Viçosa (UFV), comprometendo-se a zelar pela guarda, conservação e utilização adequada dos bens patrimoniais, bem como a devolvê-los nas mesmas condições em que foram recebidos, ressalvado o desgaste natural decorrente do uso.'
