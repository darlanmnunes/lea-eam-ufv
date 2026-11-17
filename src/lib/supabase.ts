// Ligação com o Postgres do Supabase. As regras ficam no banco (db/002_regras.sql).
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Acervo, Api, Emprestimo, Horarios, Modelo, Pessoa, Unidade } from './tipos'

/* eslint-disable @typescript-eslint/no-explicit-any */
type Linha = Record<string, any>

const pessoa = (l: Linha): Pessoa => ({
  id: l.id, nome: l.nome, email: l.email, matricula: l.matricula, telefone: l.telefone, vinculo: l.vinculo, papeis: l.papeis,
})

const unidade = (l: Linha): Unidade => ({
  id: l.id, modeloId: l.modelo_id, patrimonio: l.patrimonio, serie: l.numero_serie, situacao: l.situacao, observacao: l.observacao,
})

const emprestimo = (l: Linha): Emprestimo => ({
  id: l.id, codigo: l.codigo, solicitanteId: l.solicitante_id,
  respNome: l.resp_nome, respMatricula: l.resp_matricula, respTelefone: l.resp_telefone, respEmail: l.resp_email,
  finalidade: l.finalidade, projeto: l.projeto, localUso: l.local_uso,
  retiradaPrevista: l.retirada_prevista, devolucaoPrevista: l.devolucao_prevista,
  participantes: l.participantes ?? [], observacao: l.observacao, status: l.status, criadoEm: l.criado_em,
  itens: (l.emprestimo_itens ?? []).map((i: Linha) => ({
    id: i.id, unidadeId: i.unidade_id, observacao: i.observacao,
    estadoRetirada: i.estado_retirada, obsRetirada: i.obs_retirada, estadoDevolucao: i.estado_devolucao, obsDevolucao: i.obs_devolucao,
  })),
  eventos: (l.emprestimo_eventos ?? [])
    .map((v: Linha) => ({ id: String(v.id), tipo: v.tipo, autorId: v.autor_id, autorNome: v.autor_nome, autorPapel: v.autor_papel, observacao: v.observacao, criadoEm: v.criado_em }))
    .sort((a: { criadoEm: string }, b: { criadoEm: string }) => a.criadoEm.localeCompare(b.criadoEm)),
})

const COLUNAS = '*, emprestimo_itens(*), emprestimo_eventos(*)'

function ok<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message)
  return r.data as T
}

export function criarApiSupabase(url: string, chave: string): Api {
  const sb: SupabaseClient = createClient(url, chave, { auth: { flowType: 'pkce' } })
  return {
    modo: 'supabase',
    async sessao() {
      const { data } = await sb.auth.getSession()
      const u = data.session?.user
      if (!u) return null
      const { data: l } = await sb.from('pessoas').select('*').eq('id', u.id).maybeSingle()
      if (l) return pessoa(l)
      const nome = String(u.user_metadata?.full_name ?? u.user_metadata?.name ?? '')
      return { id: u.id, nome, email: u.email ?? '', matricula: null, telefone: null, vinculo: null, papeis: ['solicitante'], incompleto: true }
    },
    aoMudarSessao(fn) {
      const { data } = sb.auth.onAuthStateChange(() => fn())
      return () => data.subscription.unsubscribe()
    },
    async entrar() {
      // volta para a mesma página, sem o # da rota (o retorno usa ?code=)
      const destino = location.href.split('#')[0].split('?')[0]
      const { error } = await sb.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: destino, queryParams: { hd: 'ufv.br', prompt: 'select_account' } },
      })
      if (error) throw new Error(error.message)
    },
    async sair() { await sb.auth.signOut() },
    async salvarPerfil(p) {
      ok(await sb.rpc('salvar_perfil', { p_nome: p.nome, p_matricula: p.matricula, p_telefone: p.telefone, p_vinculo: p.vinculo }))
    },
    personas: () => [],
    async acervo(): Promise<Acervo> {
      const [c, m, u] = await Promise.all([
        sb.from('categorias').select('*').order('ordem'),
        sb.from('modelos').select('*').order('ordem'),
        sb.from('unidades').select('*').neq('situacao', 'baixado'),
      ])
      const unidades = ok<Linha[]>(u).map(unidade)
      return {
        categorias: ok<Linha[]>(c) as Acervo['categorias'],
        modelos: ok<Linha[]>(m).map((l): Modelo => ({
          id: l.id, categoriaId: l.categoria_id, marca: l.marca, nome: l.nome, descricao: l.descricao, foto: l.foto, emprestavel: l.emprestavel !== false, ordem: l.ordem,
          unidades: unidades.filter((x) => x.modeloId === l.id),
        })),
      }
    },
    async ocupacao() {
      return ok<Linha[]>(await sb.from('ocupacao').select('*')).map((l) => ({ unidadeId: l.unidade_id, de: l.de, ate: l.ate, status: l.status }))
    },
    async emprestimos() {
      return ok<Linha[]>(await sb.from('emprestimos').select(COLUNAS).order('criado_em', { ascending: false })).map(emprestimo)
    },
    async emprestimo(id) {
      const l = ok<Linha | null>(await sb.from('emprestimos').select(COLUNAS).eq('id', id).maybeSingle())
      return l ? emprestimo(l) : null
    },
    async criar(n) {
      return ok<string>(await sb.rpc('criar_emprestimo', {
        p_finalidade: n.finalidade, p_projeto: n.projeto, p_local: n.localUso,
        p_retirada: n.retirada, p_devolucao: n.devolucao,
        p_participantes: n.participantes, p_observacao: n.observacao,
        p_itens: n.itens.map((i) => ({ unidade_id: i.unidadeId, observacao: i.observacao })),
      }))
    },
    async avancar(id, acao, d = {}) {
      ok(await sb.rpc('avancar_emprestimo', {
        p_id: id, p_acao: acao, p_observacao: d.observacao ?? null,
        p_itens: d.itens ? d.itens.map((c) => ({ item_id: c.itemId, estado: c.estado, obs: c.obs })) : null,
        p_nova_devolucao: d.novaDevolucao ?? null,
      }))
    },
    async horarios(): Promise<Horarios> {
      const [s, d, a, u] = await Promise.all([
        sb.from('semestres').select('*').order('id'),
        sb.from('disciplinas').select('*').order('codigo'),
        sb.from('aulas').select('*'),
        sb.from('disciplina_equipamentos').select('*'),
      ])
      return {
        semestres: ok<Linha[]>(s) as Horarios['semestres'],
        disciplinas: ok<Linha[]>(d) as Horarios['disciplinas'],
        aulas: ok<Linha[]>(a).map((l) => ({ semestre: l.semestre_id, disciplina: l.disciplina_codigo, tipo: l.tipo, turma: l.turma, dia: l.dia_semana, inicio: l.hora_inicio, fim: l.hora_fim, sala: l.sala })),
        usos: ok<Linha[]>(u).map((l) => ({ disciplina: l.disciplina_codigo, modeloId: l.modelo_id, quantidade: l.quantidade })),
      }
    },
    async definirUso(disciplina, modeloId, quantidade) {
      ok(await sb.rpc('definir_uso_disciplina', { p_disciplina: disciplina, p_modelo: modeloId, p_quantidade: quantidade }))
    },
    async salvarSemestre(s) {
      ok(await sb.from('semestres').update({ inicio: s.inicio, fim: s.fim }).eq('id', s.id))
    },
    async salvarModelo(d) {
      const campos = { categoria_id: d.categoriaId, marca: d.marca.trim(), nome: d.nome.trim(), descricao: d.descricao.trim() || null, foto: d.foto, emprestavel: d.emprestavel }
      if (d.id) ok(await sb.from('modelos').update(campos).eq('id', d.id))
      else {
        const id = `${d.marca} ${d.nome}`.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
        ok(await sb.from('modelos').insert({ id, ...campos, ordem: 999 }))
      }
    },
    async salvarUnidade(d) {
      const campos = { modelo_id: d.modeloId, patrimonio: d.patrimonio.trim() || null, numero_serie: d.serie.trim() || null, situacao: d.situacao, observacao: d.observacao.trim() || null }
      if (d.id) ok(await sb.from('unidades').update(campos).eq('id', d.id))
      else ok(await sb.from('unidades').insert(campos))
    },
    async pessoas() {
      return ok<Linha[]>(await sb.from('pessoas').select('*').order('nome')).map(pessoa)
    },
    async definirPapeis(id, papeis) {
      ok(await sb.rpc('definir_papeis', { p_pessoa: id, p_papeis: papeis }))
    },
  }
}
