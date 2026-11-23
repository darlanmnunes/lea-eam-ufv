-- Regras do fluxo. Toda mudança de etapa passa por estas funções,
-- que conferem o papel de quem assina e gravam o evento.

create function eu() returns uuid language sql stable as $$
  select auth.uid()
$$;

create function tenho_papel(p papel) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from pessoas where id = auth.uid() and p = any(papeis))
$$;

create function sou_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from pessoas
     where id = auth.uid()
       and papeis && array['coordenacao','responsavel_lea','tecnico','admin']::papel[])
$$;

-- ---------------------------------------------------------------------------
-- Cadastro do próprio perfil no primeiro acesso
-- ---------------------------------------------------------------------------
create function salvar_perfil(p_nome text, p_matricula text, p_telefone text, p_vinculo text)
returns pessoas language plpgsql security definer set search_path = public as $$
declare
  v pessoas;
  v_email text := lower(auth.jwt() ->> 'email');
begin
  if auth.uid() is null then raise exception 'Entre para continuar'; end if;
  if v_email is null or not (v_email like '%@ufv.br' or v_email like '%.ufv.br') then
    raise exception 'Use a sua conta institucional da UFV (@ufv.br)';
  end if;
  insert into pessoas (id, nome, email, matricula, telefone, vinculo)
  values (auth.uid(), trim(p_nome), v_email, nullif(trim(p_matricula), ''),
          nullif(trim(p_telefone), ''), nullif(trim(p_vinculo), ''))
  on conflict (id) do update
     set nome = excluded.nome, matricula = excluded.matricula,
         telefone = excluded.telefone, vinculo = excluded.vinculo
  returning * into v;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Quantas unidades de um modelo as aulas práticas ocupam, no pior horário do período
-- ---------------------------------------------------------------------------
create function reserva_aulas(p_modelo text, p_de date, p_ate date) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(max(q), 0)::int from (
    select sum(de.quantidade) as q
      from generate_series(p_de::timestamp, p_ate::timestamp, interval '1 day') d(dia)
      join semestres s on d.dia::date between s.inicio and s.fim
      join aulas a on a.semestre_id = s.id and a.tipo = 'P'
                  and a.dia_semana = extract(isodow from d.dia)::int + 1
      join disciplina_equipamentos de
        on de.disciplina_codigo = a.disciplina_codigo and de.modelo_id = p_modelo
      join generate_series(6, 22) h(hora) on h.hora >= a.hora_inicio and h.hora < a.hora_fim
     group by d.dia, h.hora) x
$$;

-- ---------------------------------------------------------------------------
-- Novo pedido: grava o termo, os itens e a assinatura do solicitante
-- ---------------------------------------------------------------------------
create function criar_emprestimo(
  p_finalidade text, p_projeto text, p_local text,
  p_retirada date, p_devolucao date,
  p_participantes text[], p_observacao text,
  p_itens jsonb            -- [{"unidade_id": "...", "observacao": "..."}]
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_eu pessoas;
  v_id uuid;
  v_item jsonb;
  v_unidade unidades;
  v_modelo text;
  v_total int;
  v_ocupadas int;
begin
  select * into v_eu from pessoas where id = auth.uid();
  if v_eu.id is null then raise exception 'Complete seu cadastro antes de pedir'; end if;
  if v_eu.matricula is null or v_eu.telefone is null then
    raise exception 'Informe matrícula e telefone no seu cadastro';
  end if;
  if p_retirada < current_date then raise exception 'A retirada não pode ser no passado'; end if;
  if p_devolucao < p_retirada then raise exception 'A devolução vem depois da retirada'; end if;
  if jsonb_array_length(coalesce(p_itens, '[]')) = 0 then
    raise exception 'Escolha ao menos um equipamento';
  end if;

  insert into emprestimos (codigo, solicitante_id, resp_nome, resp_matricula, resp_telefone,
                           resp_email, finalidade, projeto, local_uso, retirada_prevista,
                           devolucao_prevista, participantes, observacao)
  values ('LEA-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('emprestimo_seq')::text, 4, '0'),
          v_eu.id, v_eu.nome, v_eu.matricula, v_eu.telefone, v_eu.email,
          trim(p_finalidade), trim(p_projeto), trim(p_local), p_retirada, p_devolucao,
          coalesce(p_participantes, '{}'), nullif(trim(p_observacao), ''))
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    -- trava a unidade para dois pedidos simultâneos não levarem o mesmo aparelho
    select * into v_unidade from unidades
     where id = (v_item ->> 'unidade_id')::uuid for update;
    if v_unidade.id is null then raise exception 'Equipamento não encontrado'; end if;
    if not (select emprestavel from modelos where id = v_unidade.modelo_id) then
      raise exception 'Este equipamento não está disponível para empréstimo';
    end if;
    if v_unidade.situacao <> 'disponivel' then
      raise exception 'Unidade % fora de circulação', coalesce(v_unidade.patrimonio, v_unidade.numero_serie);
    end if;
    if exists (select 1 from ocupacao o
                where o.unidade_id = v_unidade.id
                  and o.de <= p_devolucao and o.ate >= p_retirada) then
      raise exception 'Unidade % já está comprometida nesse período',
        coalesce(v_unidade.patrimonio, v_unidade.numero_serie);
    end if;
    insert into emprestimo_itens (emprestimo_id, unidade_id, observacao)
    values (v_id, v_unidade.id, nullif(trim(v_item ->> 'observacao'), ''));
  end loop;

  -- as aulas práticas do semestre têm prioridade sobre o empréstimo
  for v_modelo in select distinct u.modelo_id from emprestimo_itens i
                    join unidades u on u.id = i.unidade_id where i.emprestimo_id = v_id loop
    select count(*) into v_total from unidades where modelo_id = v_modelo and situacao = 'disponivel';
    select count(distinct o.unidade_id) into v_ocupadas
      from ocupacao o join unidades u on u.id = o.unidade_id
     where u.modelo_id = v_modelo and o.de <= p_devolucao and o.ate >= p_retirada;
    if v_ocupadas + reserva_aulas(v_modelo, p_retirada, p_devolucao) > v_total then
      raise exception 'Não há unidades livres de % nesse período: parte delas está reservada para aulas práticas',
        (select marca || ' ' || nome from modelos where id = v_modelo);
    end if;
  end loop;

  insert into emprestimo_eventos (emprestimo_id, tipo, autor_id, autor_nome, autor_papel, observacao)
  values (v_id, 'pedido_assinado', v_eu.id, v_eu.nome, 'solicitante', nullif(trim(p_observacao), ''));

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Avançar uma etapa
--   p_acao: autorizar | recusar | entregar | ciente_retirada | receber |
--           ciente_devolucao | cancelar | ocorrencia | pedir_prorrogacao |
--           autorizar_prorrogacao
--   p_itens (entregar/receber): [{"item_id": "...", "estado": "conforme", "obs": "..."}]
-- ---------------------------------------------------------------------------
create function avancar_emprestimo(
  p_id uuid, p_acao text, p_observacao text default null,
  p_itens jsonb default null, p_nova_devolucao date default null
) returns status_emprestimo language plpgsql security definer set search_path = public as $$
declare
  v_eu pessoas;
  e emprestimos;
  v_obs text := nullif(trim(coalesce(p_observacao, '')), '');
  v_tipo tipo_evento;
  v_papel papel;
  v_novo status_emprestimo;
  v_item jsonb;
  v_dono boolean;
begin
  select * into v_eu from pessoas where id = auth.uid();
  if v_eu.id is null then raise exception 'Entre para continuar'; end if;
  select * into e from emprestimos where id = p_id for update;
  if e.id is null then raise exception 'Empréstimo não encontrado'; end if;
  v_dono := e.solicitante_id = v_eu.id;
  v_novo := e.status;

  if p_acao in ('autorizar', 'recusar') and e.status = 'aguardando_coordenacao' then
    if not 'coordenacao' = any(v_eu.papeis) then raise exception 'Esta etapa é da coordenação da área'; end if;
    v_papel := 'coordenacao';
    if p_acao = 'autorizar' then v_tipo := 'coordenacao_autorizou'; v_novo := 'aguardando_lea';
    else v_tipo := 'coordenacao_recusou'; v_novo := 'recusado'; end if;

  elsif p_acao in ('autorizar', 'recusar') and e.status = 'aguardando_lea' then
    if not 'responsavel_lea' = any(v_eu.papeis) then raise exception 'Esta etapa é do responsável pelo LEA'; end if;
    v_papel := 'responsavel_lea';
    if p_acao = 'autorizar' then v_tipo := 'lea_autorizou'; v_novo := 'aguardando_retirada';
    else v_tipo := 'lea_recusou'; v_novo := 'recusado'; end if;

  elsif p_acao = 'entregar' and e.status = 'aguardando_retirada' then
    if not 'tecnico' = any(v_eu.papeis) then raise exception 'A entrega é registrada pelo técnico do LEA'; end if;
    v_papel := 'tecnico'; v_tipo := 'tecnico_entregou'; v_novo := 'aguardando_ciente_retirada';
    for v_item in select * from jsonb_array_elements(coalesce(p_itens, '[]')) loop
      update emprestimo_itens
         set estado_retirada = (v_item ->> 'estado')::estado_item,
             obs_retirada = nullif(trim(v_item ->> 'obs'), '')
       where id = (v_item ->> 'item_id')::uuid and emprestimo_id = e.id;
    end loop;
    if exists (select 1 from emprestimo_itens where emprestimo_id = e.id and estado_retirada is null) then
      raise exception 'Confira todos os itens antes de entregar';
    end if;

  elsif p_acao = 'ciente_retirada' and e.status = 'aguardando_ciente_retirada' then
    if not v_dono then raise exception 'O ciente de retirada é de quem fez o pedido'; end if;
    v_papel := 'solicitante'; v_tipo := 'ciente_retirada'; v_novo := 'em_uso';
    update emprestimos set retirado_em = now() where id = e.id;

  elsif p_acao = 'receber' and e.status = 'em_uso' then
    if not 'tecnico' = any(v_eu.papeis) then raise exception 'A devolução é conferida pelo técnico do LEA'; end if;
    v_papel := 'tecnico'; v_tipo := 'tecnico_recebeu'; v_novo := 'aguardando_ciente_devolucao';
    for v_item in select * from jsonb_array_elements(coalesce(p_itens, '[]')) loop
      update emprestimo_itens
         set estado_devolucao = (v_item ->> 'estado')::estado_item,
             obs_devolucao = nullif(trim(v_item ->> 'obs'), '')
       where id = (v_item ->> 'item_id')::uuid and emprestimo_id = e.id;
    end loop;
    if exists (select 1 from emprestimo_itens where emprestimo_id = e.id and estado_devolucao is null) then
      raise exception 'Confira todos os itens antes de receber';
    end if;
    if exists (select 1 from emprestimo_itens
                where emprestimo_id = e.id and estado_devolucao = 'com_ressalva' and obs_devolucao is null) then
      raise exception 'Descreva a ressalva de cada item devolvido com problema';
    end if;

  elsif p_acao = 'ciente_devolucao' and e.status = 'aguardando_ciente_devolucao' then
    if not v_dono then raise exception 'O ciente de devolução é de quem fez o pedido'; end if;
    v_papel := 'solicitante'; v_tipo := 'ciente_devolucao'; v_novo := 'encerrado';
    update emprestimos set devolvido_em = now() where id = e.id;

  elsif p_acao = 'cancelar'
        and e.status in ('aguardando_coordenacao', 'aguardando_lea', 'aguardando_retirada') then
    if not v_dono then raise exception 'Só quem pediu pode cancelar'; end if;
    v_papel := 'solicitante'; v_tipo := 'cancelado'; v_novo := 'cancelado';

  elsif p_acao = 'ocorrencia' and e.status in ('em_uso', 'aguardando_ciente_devolucao') then
    if not (v_dono or 'tecnico' = any(v_eu.papeis)) then raise exception 'Sem permissão'; end if;
    if v_obs is null then raise exception 'Descreva a ocorrência'; end if;
    v_papel := case when v_dono then 'solicitante'::papel else 'tecnico'::papel end;
    v_tipo := 'ocorrencia';

  elsif p_acao = 'pedir_prorrogacao' and e.status = 'em_uso' then
    if not v_dono then raise exception 'Só quem pediu pode solicitar prorrogação'; end if;
    if v_obs is null then raise exception 'Justifique a prorrogação'; end if;
    v_papel := 'solicitante'; v_tipo := 'prorrogacao_pedida';

  elsif p_acao = 'autorizar_prorrogacao' and e.status = 'em_uso' then
    if not 'responsavel_lea' = any(v_eu.papeis) then raise exception 'A prorrogação é autorizada pelo responsável pelo LEA'; end if;
    if p_nova_devolucao is null or p_nova_devolucao <= e.devolucao_prevista then
      raise exception 'Informe a nova data de devolução';
    end if;
    if exists (select 1 from ocupacao o
                 join emprestimo_itens i on i.unidade_id = o.unidade_id and i.emprestimo_id = e.id
                where o.de <= p_nova_devolucao and o.ate > e.devolucao_prevista
                  and not (o.de = e.retirada_prevista and o.ate = e.devolucao_prevista)) then
      raise exception 'Há outro pedido para esse equipamento no período da prorrogação';
    end if;
    v_papel := 'responsavel_lea'; v_tipo := 'prorrogacao_autorizada';
    update emprestimos set devolucao_prevista = p_nova_devolucao where id = e.id;

  else
    raise exception 'Ação "%" não cabe na etapa atual (%)', p_acao, e.status;
  end if;

  if v_tipo in ('coordenacao_recusou', 'lea_recusou') and v_obs is null then
    raise exception 'Explique o motivo da recusa';
  end if;

  update emprestimos set status = v_novo, atualizado_em = now() where id = e.id;
  insert into emprestimo_eventos (emprestimo_id, tipo, autor_id, autor_nome, autor_papel, observacao)
  values (e.id, v_tipo, v_eu.id, v_eu.nome, v_papel, v_obs);
  return v_novo;
end $$;

-- ---------------------------------------------------------------------------
-- Administração
-- ---------------------------------------------------------------------------
create function definir_papeis(p_pessoa uuid, p_papeis papel[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tenho_papel('admin') then raise exception 'Só a administração define papéis'; end if;
  if p_pessoa = auth.uid() and not 'admin' = any(p_papeis) then
    raise exception 'Você não pode retirar o próprio acesso de administração';
  end if;
  update pessoas
     set papeis = (select array_agg(distinct x) from unnest(p_papeis || 'solicitante'::papel) x)
   where id = p_pessoa;
end $$;

create function definir_uso_disciplina(p_disciplina text, p_modelo text, p_quantidade int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (tenho_papel('docente') or tenho_papel('coordenacao') or tenho_papel('admin')) then
    raise exception 'O uso em aula é informado pelos docentes';
  end if;
  if coalesce(p_quantidade, 0) <= 0 then
    delete from disciplina_equipamentos where disciplina_codigo = p_disciplina and modelo_id = p_modelo;
  else
    if p_quantidade > (select count(*) from unidades where modelo_id = p_modelo and situacao <> 'baixado') then
      raise exception 'O laboratório não tem tantas unidades desse modelo';
    end if;
    insert into disciplina_equipamentos (disciplina_codigo, modelo_id, quantidade, atualizado_por)
    values (p_disciplina, p_modelo, p_quantidade, auth.uid())
    on conflict (disciplina_codigo, modelo_id) do update
       set quantidade = excluded.quantidade, atualizado_por = excluded.atualizado_por, atualizado_em = now();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Lembretes por e-mail: quem precisa assinar ou dar ciente agora
-- ---------------------------------------------------------------------------
create function pendentes_de_ciente()
returns table (emprestimo_id uuid, codigo text, etapa status_emprestimo, pessoa_id uuid,
               nome text, email text, solicitante text, retirada date, devolucao date)
language sql stable security definer set search_path = public as $$
  -- etapas da equipe: todos que têm o papel da vez
  select e.id, e.codigo, e.status, p.id, p.nome, p.email, e.resp_nome, e.retirada_prevista, e.devolucao_prevista
    from emprestimos e
    join pessoas p on (e.status = 'aguardando_coordenacao' and 'coordenacao' = any(p.papeis))
                   or (e.status = 'aguardando_lea' and 'responsavel_lea' = any(p.papeis))
                   or (e.status = 'aguardando_retirada' and 'tecnico' = any(p.papeis)
                       and e.retirada_prevista <= current_date + 1)
  union all
  -- cientes de quem pediu, e devolução vencida
  select e.id, e.codigo, e.status, p.id, p.nome, p.email, e.resp_nome, e.retirada_prevista, e.devolucao_prevista
    from emprestimos e
    join pessoas p on p.id = e.solicitante_id
   where e.status in ('aguardando_ciente_retirada', 'aguardando_ciente_devolucao')
      or (e.status = 'em_uso' and e.devolucao_prevista < current_date)
$$;

-- Devolve só os lembretes que ainda não saíram dentro do intervalo, e já os registra.
-- Chamada pela função agendada (supabase/functions/lembretes) com a chave de serviço.
create function lembretes_a_enviar(p_intervalo interval default '24 hours')
returns table (emprestimo_id uuid, codigo text, etapa status_emprestimo, pessoa_id uuid,
               nome text, email text, solicitante text, retirada date, devolucao date)
language plpgsql security definer set search_path = public as $$
begin
  return query
  with novos as (
    select p.* from pendentes_de_ciente() p
     where not exists (select 1 from lembretes l
                        where l.emprestimo_id = p.emprestimo_id and l.pessoa_id = p.pessoa_id
                          and l.etapa = p.etapa and l.enviado_em > now() - p_intervalo)
  ), gravados as (
    insert into lembretes (emprestimo_id, pessoa_id, etapa)
    select n.emprestimo_id, n.pessoa_id, n.etapa from novos n
    returning 1
  )
  select n.* from novos n where (select count(*) from gravados) >= 0;
end $$;

-- ---------------------------------------------------------------------------
-- Acesso (RLS)
-- ---------------------------------------------------------------------------
alter table pessoas            enable row level security;
alter table categorias         enable row level security;
alter table modelos            enable row level security;
alter table unidades           enable row level security;
alter table emprestimos        enable row level security;
alter table emprestimo_itens   enable row level security;
alter table emprestimo_eventos enable row level security;

-- O acervo é público, como um catálogo de biblioteca.
create policy acervo_leitura on categorias for select using (true);
create policy acervo_leitura on modelos    for select using (true);
create policy acervo_leitura on unidades   for select using (true);
create function cuida_do_acervo() returns boolean
language sql stable security definer set search_path = public as $$
  select tenho_papel('tecnico') or tenho_papel('responsavel_lea') or tenho_papel('admin')
$$;
create policy acervo_edicao on categorias for all using (cuida_do_acervo()) with check (cuida_do_acervo());
create policy acervo_edicao on modelos    for all using (cuida_do_acervo()) with check (cuida_do_acervo());
create policy acervo_edicao on unidades   for all using (cuida_do_acervo()) with check (cuida_do_acervo());

-- Horário e uso em aula também são públicos; mudam por função ou pela administração.
alter table semestres               enable row level security;
alter table disciplinas             enable row level security;
alter table aulas                   enable row level security;
alter table disciplina_equipamentos enable row level security;
alter table lembretes               enable row level security;
create policy aulas_leitura on semestres               for select using (true);
create policy aulas_leitura on disciplinas             for select using (true);
create policy aulas_leitura on aulas                   for select using (true);
create policy aulas_leitura on disciplina_equipamentos for select using (true);
create policy semestre_edicao on semestres for all using (tenho_papel('admin')) with check (tenho_papel('admin'));

create policy pessoa_leitura on pessoas for select using (id = auth.uid() or sou_equipe());

-- Pedidos: cada um vê os seus; a equipe vê todos. Escrita só pelas funções acima.
create policy emprestimo_leitura on emprestimos for select
  using (solicitante_id = auth.uid() or sou_equipe());
create policy item_leitura on emprestimo_itens for select
  using (exists (select 1 from emprestimos e where e.id = emprestimo_id
                  and (e.solicitante_id = auth.uid() or sou_equipe())));
create policy evento_leitura on emprestimo_eventos for select
  using (exists (select 1 from emprestimos e where e.id = emprestimo_id
                  and (e.solicitante_id = auth.uid() or sou_equipe())));

-- Patrimônio e número de série de cada unidade: só para quem tem cadastro, e o cadastro exige
-- conta @ufv.br (salvar_perfil). Quem não entrou recebe a lista vazia.
create function identificacao_unidades()
returns table (id uuid, patrimonio text, numero_serie text)
language sql stable security definer set search_path = public as $$
  select u.id, u.patrimonio, u.numero_serie from unidades u
   where exists (select 1 from pessoas p where p.id = auth.uid())
$$;

-- No Supabase, tabelas, sequências e funções novas nascem liberadas para anon e authenticated.
-- Fecha tudo e libera só o que o site usa.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on categorias, modelos, ocupacao,
                semestres, disciplinas, aulas, disciplina_equipamentos to anon, authenticated;
-- unidades: patrimônio e número de série não são públicos (ver identificacao_unidades)
grant select (id, modelo_id, situacao, observacao) on unidades to anon, authenticated;
grant insert, update, delete on categorias, semestres to authenticated;
grant select on pessoas, emprestimos, emprestimo_itens, emprestimo_eventos to authenticated;
grant insert, update, delete on modelos, unidades to authenticated;
grant execute on function salvar_perfil, criar_emprestimo, avancar_emprestimo, definir_papeis,
                          definir_uso_disciplina, tenho_papel, sou_equipe, cuida_do_acervo, eu to authenticated;
grant execute on function reserva_aulas, tenho_papel, sou_equipe, cuida_do_acervo, eu, identificacao_unidades to anon, authenticated;
grant execute on function pendentes_de_ciente, lembretes_a_enviar to service_role;
