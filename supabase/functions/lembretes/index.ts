// Lembretes por e-mail: avisa quem precisa autorizar, entregar ou dar ciente,
// e repete a cada intervalo até a etapa andar.
//
// Roda no Supabase (Edge Function) chamada por agendamento; veja o README.
// Segredos esperados: RESEND_API_KEY, LEMBRETE_REMETENTE, SITE_URL.
// Opcional: LEMBRETE_INTERVALO_HORAS (padrão 24).
import { createClient } from 'npm:@supabase/supabase-js@2'

interface Pendente {
  emprestimo_id: string
  codigo: string
  etapa: string
  nome: string
  email: string
  solicitante: string
  retirada: string
  devolucao: string
}

const O_QUE_FAZER: Record<string, string> = {
  aguardando_coordenacao: 'aguarda a sua autorização como coordenação da área acadêmica',
  aguardando_lea: 'aguarda a sua autorização como responsável pelo LEA',
  aguardando_retirada: 'está autorizado e tem retirada marcada: confira os itens e registre a entrega',
  aguardando_ciente_retirada: 'aguarda o seu ciente de retirada',
  aguardando_ciente_devolucao: 'aguarda o seu ciente de devolução',
  em_uso: 'está com a devolução vencida',
}

const data = (iso: string) => iso.split('-').reverse().join('/')

Deno.serve(async () => {
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const horas = Number(Deno.env.get('LEMBRETE_INTERVALO_HORAS') ?? '24')
  const { data: pendentes, error } = await sb.rpc('lembretes_a_enviar', { p_intervalo: `${horas} hours` })
  if (error) return new Response(error.message, { status: 500 })

  const site = Deno.env.get('SITE_URL')!
  const falhas: string[] = []
  for (const p of (pendentes ?? []) as Pendente[]) {
    const link = `${site}/acervo.html#/pedido/${p.emprestimo_id}`
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${Deno.env.get('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: Deno.env.get('LEMBRETE_REMETENTE'),
        to: p.email,
        subject: `LEA | pedido ${p.codigo} ${p.etapa === 'em_uso' ? 'com devolução vencida' : 'aguarda você'}`,
        text: [
          `Olá, ${p.nome}.`,
          '',
          `O pedido ${p.codigo}, de ${p.solicitante}, ${O_QUE_FAZER[p.etapa] ?? 'aguarda uma ação sua'}.`,
          `Retirada: ${data(p.retirada)} | Devolução prevista: ${data(p.devolucao)}`,
          '',
          `Abrir o pedido: ${link}`,
          '',
          'Este aviso se repete até a etapa ser registrada no sistema.',
          'Laboratório de Engenharia de Agrimensura e Cartográfica | UFV',
        ].join('\n'),
      }),
    })
    if (!r.ok) falhas.push(`${p.email}: ${r.status}`)
  }
  return Response.json({ enviados: (pendentes ?? []).length - falhas.length, falhas })
})
