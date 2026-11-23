-- Acervo do LEA | esquema completo para o Supabase (gerado por db/juntar-supabase.sh)

-- ===== 001_esquema.sql =====
-- LEA | Acervo e empréstimo de equipamentos
-- Esquema para PostgreSQL 14+ (Supabase). Aplicar na ordem: 001, 002, 003.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type papel as enum (
  'solicitante',      -- qualquer pessoa com cadastro
  'docente',          -- informa os equipamentos das suas disciplinas
  'coordenacao',      -- coordenação da área acadêmica: primeira autorização
  'responsavel_lea',  -- responsável pelo laboratório: segunda autorização
  'tecnico',          -- cadastra equipamentos, entrega e recebe
  'admin'             -- define papéis e semestres
);

create type situacao_unidade as enum (
  'disponivel',   -- circula: pode ir para aula ou empréstimo
  'manutencao',   -- em conserto ou calibração
  'estoque',      -- guardado, fora de circulação por ora
  'baixado'       -- saiu do acervo
);

create type status_emprestimo as enum (
  'aguardando_coordenacao',  -- pedido enviado e assinado pelo solicitante
  'aguardando_lea',          -- coordenação autorizou
  'aguardando_retirada',     -- responsável pelo LEA autorizou
  'aguardando_ciente_retirada', -- técnico conferiu e entregou; falta o ciente de quem retira
  'em_uso',                  -- retirada confirmada pelas duas partes
  'aguardando_ciente_devolucao', -- técnico conferiu a devolução; falta o ciente de quem devolve
  'encerrado',
  'recusado',
  'cancelado'
);

create type tipo_evento as enum (
  'pedido_assinado',
  'coordenacao_autorizou',
  'coordenacao_recusou',
  'lea_autorizou',
  'lea_recusou',
  'tecnico_entregou',
  'ciente_retirada',
  'tecnico_recebeu',
  'ciente_devolucao',
  'prorrogacao_pedida',
  'prorrogacao_autorizada',
  'ocorrencia',
  'cancelado'
);

create type estado_item as enum ('conforme', 'com_ressalva');

-- ---------------------------------------------------------------------------
-- Pessoas
-- ---------------------------------------------------------------------------
create table pessoas (
  id          uuid primary key,            -- = auth.users.id no Supabase
  nome        text not null check (length(trim(nome)) >= 3),
  email       text not null unique,
  matricula   text,
  telefone    text,
  vinculo     text,                         -- discente, docente, técnico...
  papeis      papel[] not null default '{solicitante}',
  criado_em   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Acervo
-- ---------------------------------------------------------------------------
create table categorias (
  id     text primary key,                 -- 'estacao-total'
  nome   text not null,
  sigla  text not null,                    -- 'ET', usada na cota do acervo
  ordem  int  not null default 0
);

create table modelos (
  id            text primary key,          -- 'geodetic-gd2i'
  categoria_id  text not null references categorias(id),
  marca         text not null,
  nome          text not null,
  descricao     text,
  acompanha     text[] not null default '{}',  -- acessórios que saem junto
  foto          text,
  emprestavel   boolean not null default true,  -- falso: aparece no acervo, sem pedido
  ordem         int not null default 0
);

create table unidades (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     text not null references modelos(id),
  patrimonio    text,                      -- nº de patrimônio UFV
  numero_serie  text,                      -- quando não há patrimônio
  situacao      situacao_unidade not null default 'disponivel',
  observacao    text,
  unique (patrimonio)
);

-- ---------------------------------------------------------------------------
-- Empréstimos
-- ---------------------------------------------------------------------------
create sequence emprestimo_seq;

create table emprestimos (
  id                  uuid primary key default gen_random_uuid(),
  codigo              text not null unique,            -- LEA-2026-0007
  solicitante_id      uuid not null references pessoas(id),
  -- identificação registrada no momento do pedido (seção 1 do termo)
  resp_nome           text not null,
  resp_matricula      text not null,
  resp_telefone       text not null,
  resp_email          text not null,
  -- atividade (seção 2)
  finalidade          text not null,
  projeto             text not null,
  local_uso           text not null,
  retirada_prevista   date not null,
  devolucao_prevista  date not null,
  -- participantes (seção 3)
  participantes       text[] not null default '{}',
  observacao          text,
  status              status_emprestimo not null default 'aguardando_coordenacao',
  retirado_em         timestamptz,
  devolvido_em        timestamptz,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  check (devolucao_prevista >= retirada_prevista)
);

create index on emprestimos (solicitante_id);
create index on emprestimos (status);

create table emprestimo_itens (
  id                 uuid primary key default gen_random_uuid(),
  emprestimo_id      uuid not null references emprestimos(id) on delete cascade,
  unidade_id         uuid not null references unidades(id),
  observacao         text,                 -- observação do pedido (seção 4)
  estado_retirada    estado_item,
  obs_retirada       text,
  estado_devolucao   estado_item,
  obs_devolucao      text,
  unique (emprestimo_id, unidade_id)
);

create index on emprestimo_itens (unidade_id);

-- Registro de assinaturas e cientes. Só recebe inserções.
create table emprestimo_eventos (
  id             bigint generated always as identity primary key,
  emprestimo_id  uuid not null references emprestimos(id) on delete cascade,
  tipo           tipo_evento not null,
  autor_id       uuid not null references pessoas(id),
  autor_nome     text not null,
  autor_papel    papel not null,
  observacao     text,
  criado_em      timestamptz not null default now()
);

create index on emprestimo_eventos (emprestimo_id, criado_em);

create function bloquear_alteracao_evento() returns trigger language plpgsql as $$
begin
  raise exception 'O registro de assinaturas não pode ser alterado';
end $$;

create trigger eventos_imutaveis
  before update or delete on emprestimo_eventos
  for each row execute function bloquear_alteracao_evento();

-- ---------------------------------------------------------------------------
-- Ocupação: períodos em que cada unidade está comprometida.
-- Não expõe quem pediu; alimenta a disponibilidade do catálogo público.
-- ---------------------------------------------------------------------------
create view ocupacao as
  select i.unidade_id,
         e.retirada_prevista as de,
         e.devolucao_prevista as ate,
         e.status
    from emprestimo_itens i
    join emprestimos e on e.id = i.emprestimo_id
   where e.status not in ('encerrado', 'recusado', 'cancelado');

-- ---------------------------------------------------------------------------
-- Aulas: o horário do semestre reserva equipamentos antes de qualquer empréstimo
-- ---------------------------------------------------------------------------
create table semestres (
  id        text primary key,              -- '2026-2'
  ano       int not null,
  semestre  int not null check (semestre in (1, 2)),
  inicio    date,                          -- sem datas, o semestre não reserva nada
  fim       date,
  check (fim is null or inicio is null or fim >= inicio)
);

create table disciplinas (
  codigo  text primary key,                -- 'EAM 301'
  nome    text not null
);

create table aulas (
  id                 bigint generated always as identity primary key,
  semestre_id        text not null references semestres(id) on delete cascade,
  disciplina_codigo  text not null references disciplinas(codigo),
  tipo               char(1) not null check (tipo in ('T', 'P')),
  turma              int not null,
  dia_semana         int not null check (dia_semana between 2 and 7),  -- 2 = segunda, como na DTI
  hora_inicio        int not null,
  hora_fim           int not null,
  sala               text
);

create index on aulas (semestre_id, dia_semana);

-- O que cada disciplina usa nas aulas práticas. Quem informa é o docente.
create table disciplina_equipamentos (
  disciplina_codigo  text not null references disciplinas(codigo),
  modelo_id          text not null references modelos(id) on delete cascade,
  quantidade         int not null check (quantidade > 0),
  atualizado_por     uuid references pessoas(id),
  atualizado_em      timestamptz not null default now(),
  primary key (disciplina_codigo, modelo_id)
);

-- Lembretes já enviados por e-mail (um por pessoa, pedido e etapa a cada intervalo)
create table lembretes (
  id             bigint generated always as identity primary key,
  emprestimo_id  uuid not null references emprestimos(id) on delete cascade,
  pessoa_id      uuid not null references pessoas(id),
  etapa          status_emprestimo not null,
  enviado_em     timestamptz not null default now()
);

create index on lembretes (emprestimo_id, pessoa_id, etapa, enviado_em desc);

-- ===== 002_regras.sql =====
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

-- No Supabase, tabelas, sequências e funções novas nascem liberadas para anon e authenticated.
-- Fecha tudo e libera só o que o site usa.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on categorias, modelos, unidades, ocupacao,
                semestres, disciplinas, aulas, disciplina_equipamentos to anon, authenticated;
grant insert, update, delete on categorias, semestres to authenticated;
grant select on pessoas, emprestimos, emprestimo_itens, emprestimo_eventos to authenticated;
grant insert, update, delete on modelos, unidades to authenticated;
grant execute on function salvar_perfil, criar_emprestimo, avancar_emprestimo, definir_papeis,
                          definir_uso_disciplina, tenho_papel, sou_equipe, cuida_do_acervo, eu to authenticated;
grant execute on function reserva_aulas, tenho_papel, sou_equipe, cuida_do_acervo, eu to anon, authenticated;
grant execute on function pendentes_de_ciente, lembretes_a_enviar to service_role;

-- ===== 003_acervo.sql =====
-- Acervo inicial do LEA. Gerado por scripts/gerar-sql-acervo.mjs; não editar à mão.

insert into categorias (id, nome, sigla, ordem) values
  ('estacao-total', 'Estações totais', 'ET', 1),
  ('gnss', 'Receptores GNSS e RTK', 'GN', 2),
  ('nivel', 'Níveis', 'NV', 3),
  ('teodolito', 'Teodolitos', 'TD', 4),
  ('laser-scanner', 'Laser scanner', 'LS', 5),
  ('aeronave', 'Drones e VANT', 'VT', 6),
  ('medicao', 'Bússolas e instrumentos de medição', 'MD', 7),
  ('acessorio', 'Miras, tripés e acessórios', 'AC', 8),
  ('desenho', 'Planímetros e desenho', 'DS', 9),
  ('apoio', 'Apoio de campo', 'AP', 10);

insert into modelos (id, categoria_id, marca, nome, descricao, foto, emprestavel, ordem) values
  ('geodetic-gd2i', 'estacao-total', 'Geodetic', 'GD2i', 'Estação total das aulas práticas de Topografia. É o modelo com mais unidades no laboratório.', 'geodetic-gd2i.webp', true, 1),
  ('geodetic-gt2-plus', 'estacao-total', 'Geodetic', 'GT2+', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gt2-plus.webp', true, 2),
  ('geodetic-gd8i', 'estacao-total', 'Geodetic', 'GD8i', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gd8i.webp', true, 3),
  ('estacao-total-pentax', 'estacao-total', 'Estação total', 'Pentax', 'Estação total, precisão linear 2 mm + 2 ppm, alcance 3.500 m com 1 prisma e 250 m sem prisma, tempo medição 1 s, uso topografia, ac. 2 prismas alvos, 2 bastões 3,60 m, nível esférico, tripé ext. em alumínio, cabo transm.', 'pentax-r-315nx.webp', true, 4),
  ('topcon-es-65', 'estacao-total', 'Topcon', 'ES-65', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-es-65.webp', true, 5),
  ('topcon-gts-102n', 'estacao-total', 'Topcon', 'GTS-102N', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-102n.webp', true, 6),
  ('topcon-gts-212', 'estacao-total', 'Topcon', 'GTS-212', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-212.webp', true, 7),
  ('chc-i50', 'gnss', 'CHC Nav', 'i50', 'Receptor GNSS para posicionamento RTK.', 'chc-nav-i50.webp', true, 8),
  ('topomap-t10', 'gnss', 'Topomap', 'T10', 'Receptor GNSS para posicionamento RTK, usado em par como base e rover.', 'rtk-topomap-t10.webp', true, 9),
  ('emlid-reach-rs2', 'gnss', 'Emlid', 'Reach RS2', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emild-reach-rs2.webp', true, 10),
  ('emlid-reach-rs2-plus', 'gnss', 'Emlid', 'Reach RS2+', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emilid-reach-rs2-plus.webp', true, 11),
  ('javad-triumph-1', 'gnss', 'Javad', 'Triumph-1', 'Receptor GNSS geodésico para rastreio estático e apoio de campo.', 'javad-trimph-1.webp', true, 12),
  ('hi-target-v200', 'gnss', 'Hi-Target', 'V200', 'Receptor GNSS para posicionamento RTK.', null, true, 13),
  ('receptor-gnss-trimble', 'gnss', 'Receptor GNSS', 'Trimble', 'Receptor GPS.', null, true, 14),
  ('receptor-gnss-leica', 'gnss', 'Receptor GNSS', 'Leica', 'Receptor GPS de sinais de constelações com capacidade de correção.', null, true, 15),
  ('receptor-gnss-sem-marca', 'gnss', 'Receptor GNSS', 'sem marca', 'Receptor GPS para medição geodésica, com 02 receptores com 02 bolsas de temperatura.', null, true, 16),
  ('nivel-zeiss', 'nivel', 'Nível', 'Zeiss', 'Nível para topografia acondicionado em caixa de madeira. cor: cinza.', 'nivel-zeiss-ni-002.webp', true, 17),
  ('nivel-foif', 'nivel', 'Nível', 'Foif', 'Nível óptico.', 'nivel-foif.webp', true, 18),
  ('nivel-mom', 'nivel', 'Nível', 'MOM', 'Nível para topografia, pequeno instrumento de nivelacao automática, em estojo de couro. cor: vermelha.', 'nivel-mom-ni-b5.webp', true, 19),
  ('nivel-siom', 'nivel', 'Nível', 'Siom', 'Nível para topografia, escala de 0 a 350 graus, em estojo e tripé em madeira e pontas de ferro. cor: laranja.', 'nivel-siom.webp', true, 20),
  ('nivel-wild', 'nivel', 'Nível', 'Wild', 'Nível topográfico acondicionado em caixa de plástico.', 'nivel-wild.webp', true, 21),
  ('topcon-dl-502', 'nivel', 'Topcon', 'DL-502', 'Nível digital para nivelamento geométrico.', 'nivel-topcon-dl-502.webp', true, 22),
  ('nivel-kern', 'nivel', 'Nível', 'Kern', 'Nível para topografia, acondicionado em caixa plástica. cor: marrom/verde.', null, true, 23),
  ('nivel-sem-marca', 'nivel', 'Nível', 'sem marca', 'Nível para topografia, automático, para levantamento de média precisão com acessórios, caixa em madeira e tripé tambem em madeira tipo - k002. cor: cinza.', null, true, 24),
  ('luneta-de-nivel-niveltec', 'nivel', 'Luneta de nível', 'Niveltec', 'Luneta, com tripé, altura regulável, com capa, acompanhada de uma mira em PVC de 2,5m. cor: preta.', null, true, 25),
  ('nivel-sion', 'nivel', 'Nível', 'Sion', 'Nível para topografia, com giro de 360 graus e 1 luneta, estojo de madiera portátil com chave. cor: laranja.', null, true, 26),
  ('nivel-gurley', 'nivel', 'Nível', 'Gurley', 'Nível para topografia, de luneta, em metal amarela, com tripé(para fins didáticos). cor: amarelo.', null, true, 27),
  ('nivel-mitutoyo', 'nivel', 'Nível', 'Mitutoyo', 'Nível de pedreiro metálico, precisão 0.02mm/m, em estojo de madeira envernizado. cor: cinza dimensões: 0,20x0,04x0,04 m.', null, true, 28),
  ('nivel-pzo', 'nivel', 'Nível', 'PZO', 'Nível para topografia com objetiva auxiliar acoplada na base,capa plástica, acondicionado em caixa metálica com alça e trincos, equipado com 1 mira falante extensiva em madeira envernizada 4m de altura pat.', null, true, 29),
  ('teodolito-berger', 'teodolito', 'Teodolito', 'Berger', 'Teodolito digital, com prumo óptico, leitura digital de 10 segundos, com porcentagem de rampa, com estojo para aconcionamento, proteção e transporte, com tripé de alumínio.', 'teodolito-berger-dgt20.webp', true, 30),
  ('teodolito-world', 'teodolito', 'Teodolito', 'World', 'Teodolito de leitura externa, escala de 0 a 360 graus, precisão de 1 minuto, com bússola. cor: bege.', 'teodolito-world.webp', true, 31),
  ('teodolito-vasconcelos', 'teodolito', 'Teodolito', 'Vasconcelos', 'Teodolito, com limbos externos, aproximadamente de 1 minuto no limbo horizontal e no vertical, em estojo metálico tipo campanula de cor cinza e preta com tripé em madeira, altura regulável. cor: cinza.', 'teodolito-vasconcelos.webp', true, 32),
  ('teodolito-wild', 'teodolito', 'Teodolito', 'Wild', 'Teodolito, com limbos internos, aproximadamente de 1 minuto nos limbos horizontais e verticais, luneta autoredutor, em caixa metálica tipo campanula cor verde, com tripé em madeiraaltura regulável.', 'teodolito-wild-t2.webp', true, 33),
  ('teodolito-zeiss', 'teodolito', 'Teodolito', 'Zeiss', 'Teodolito, com limbos internos em caixa metálica tipo maleta de cor azul, com tripé de madeira, altura regulável. cor: cinza.', 'teodolito-zeiss-th2.webp', true, 34),
  ('teodolito-zeiss-jena', 'teodolito', 'Teodolito', 'Zeiss Jena', 'Teodolito de escala, micrométrico, 7 ajustes, procedência alemã.', 'teodolito-zeiss-theo-015.webp', true, 35),
  ('teodolito-sem-marca', 'teodolito', 'Teodolito', 'sem marca', 'Teodolito taqueômetro de alta precisão, com acessórios, tripé em madeira k-001, em caixa de madeira. cor: cinza.', null, true, 36),
  ('teodolito-dfv', 'teodolito', 'Teodolito', 'DFV', 'Teodolito repetidor, ajustável, com bússola e luneta em caixa cinza e preta portátil, tripé regulável em madeira cor: cinza.', null, true, 37),
  ('teodolito-keuffel', 'teodolito', 'Teodolito', 'Keuffel', 'Teodolito, com limbos internos, aproximadamente de 1 minuto no limbo horizontal e no vertical, em caixa metálica tipo campanula cor verde, com tripé de madeira, altura regulável.', null, true, 38),
  ('teodolito-sunray', 'teodolito', 'Teodolito', 'Sunray', 'Teodolito, com limbo externo, aproximadamente de 20 segundos no limbo horizontal e 1 minuto no limbo vertical, acondicionado em caixa tipo maleta, bolsa a tira colo cor laranja, com tripé de madeira, altura regulável.', null, true, 39),
  ('teodolito-breithaupt', 'teodolito', 'Teodolito', 'Breithaupt', 'Teodolito metálico com bússola, base de madeira.', null, true, 40),
  ('teodolito-mon-richer', 'teodolito', 'Teodolito', 'Mon Richer', 'Teodolito, metálico (para fins didáticos). cor: bronzeado.', null, true, 41),
  ('teodolito-oms', 'teodolito', 'Teodolito', 'OMS', 'Teodolito, base de ferro (para fins didáticos). cor: cinza.', null, true, 42),
  ('teodolito-zuhio', 'teodolito', 'Teodolito', 'Zuhio', 'Teodolito, em caixa de madeira, com tripé e bússola com limbos externos e sessenta segundos no limbo interno. cor: cinza.', null, true, 43),
  ('riegl-vz-400', 'laser-scanner', 'Riegl', 'VZ-400', 'Laser scanner terrestre para nuvens de pontos.', 'riegl-vz-400.webp', true, 44),
  ('batmap-ii', 'aeronave', 'Batmap', 'II', 'VANT de asa fixa para aerolevantamento.', 'batmap-ii.webp', true, 45),
  ('dji-mavic-air-2', 'aeronave', 'DJI', 'Mavic Air 2', 'Drone multirrotor para imagens aéreas.', 'drone-dji-mavic-air-2.webp', true, 46),
  ('binoculo-bushnell', 'medicao', 'Binóculo', 'Bushnell', 'Binóculo com diâmetro de 35mm, aumento 7x15 vezes com zoom, com tampa protetora das lentes, acompanha bolsa em courvin para acondicionamento. cor: preto.', 'binoculo-bushnell.webp', true, 47),
  ('telemetro-wild', 'medicao', 'Telêmetro', 'Wild', 'Telêmetro com cabeçote, marca Wild, com limbos externos horizontais e verticais em estojo metálico.', 'telemetro-wild.webp', true, 48),
  ('bussola-passed', 'medicao', 'Bússola', 'Passed', 'Bússola com luneta, tipo brunton, origem japonesa, disco de 50 a 50, acondicionada com bolsa de couro marrom, com tripé em madeira envernizada e altura regulável. cor: verde e preta.', null, true, 49),
  ('trena-eletronica-leica', 'medicao', 'Trena eletrônica', 'Leica', 'Trena eletrônica.', null, true, 50),
  ('altimetro-sem-marca', 'medicao', 'Altímetro', 'sem marca', 'Altímetro, com escala de metro em metro e de 5 em 5 metros, acondicionado em bolsa de couro. cor: alumínio.', null, true, 51),
  ('altimetro-wallace', 'medicao', 'Altímetro', 'Wallace', 'Altímetro de precisão com termômetro de bulbo seco e bulbo úmido, acondicionado em caixa metálica. cor: verde.', null, true, 52),
  ('bussola-ushikata', 'medicao', 'Bússola', 'Ushikata', 'Bússola com luneta, acondicionado em estojo de couro preto, com escala de 360 graus, luneta com objetiva de 18m/m, escaladupla de 0 a 50 graus, tripé metálico regulável com capa de tecido amarelo com alça. cor: bege.', null, true, 53),
  ('pantometro-sem-marca', 'medicao', 'Pantômetro', 'sem marca', 'Pantômetro, com luneta e bússola, metálico, base de ferro, tripé de madeira. cor: cinza.', null, true, 54),
  ('podometro-teiluiz', 'medicao', 'Podômetro', 'Teiluiz', 'Podômetro 0-40km, aparelho para medir distância em junção de número de passos dados.', null, true, 55),
  ('prancheta-topografica-sem-marca', 'medicao', 'Prancheta topográfica', 'sem marca', 'Prancheta topográfica, caixa em madeira, bolsa em lona, tripé em madeira, tipo k-014. cor: cinza.', null, true, 56),
  ('bussola-fuji', 'medicao', 'Bússola', 'Fuji', 'Bússola com tripé, 0-360 graus, com luneta. cor: cinza.', null, true, 57),
  ('bussola-osaka-tamaya', 'medicao', 'Bússola', 'Osaka-Tamaya', 'Bússola com tripé, 0-360 graus, com luneta. cor: cinza.', null, true, 58),
  ('clinometro-casella', 'medicao', 'Clinômetro', 'Casella', 'Clinômetro metálico com escala de 0 a 90 graus, acondicionado em caixa de madeira revestida em plástico.', null, true, 59),
  ('clinometro-fuji', 'medicao', 'Clinômetro', 'Fuji', 'Clinômetro de pêndulo, com escala espelhada de 0 a 50, metálico, com bússola número 25, em caixa de couro. cor: cinza.', null, true, 60),
  ('clinometro-meridian', 'medicao', 'Clinômetro', 'Meridian', 'Clinômetro (clisímetro) portátil com bolsa de couro para seu acondicionamento.', null, true, 61),
  ('medidor-topografico-genovesi', 'medicao', 'Medidor topográfico', 'Genovesi', 'Medidor topográfico, com leituras parciais em decímetros, capacidade máxima do registrador 10 km cor laranja.', null, true, 62),
  ('tripe-miratec', 'acessorio', 'Tripé', 'Miratec', 'Tripé para teodolito, com pernas extensíveis em alumínio, com placa de apoio do instrumento e parafusos de fixação.', null, true, 63),
  ('mira-foif', 'acessorio', 'Mira', 'Foif', 'Mira uso topográfico, material alumínio, tipo encaixe, comprimento 4 m, aplicação topografia e agrimensura.', null, true, 64),
  ('baliza-sem-marca', 'acessorio', 'Baliza', 'sem marca', 'Baliza topográfica, cor branca/vermelha, 3/4", metálica, com 10 hastes, cor branca/vermelha, 3/4", metálica.', null, true, 65),
  ('mira-desetec-trident', 'acessorio', 'Mira', 'Desetec/Trident', 'Mira topográfica, tipo encaixe, 3 metros de comprimento, em madeira graduada de 01 em 01 cm, base metálica.', null, true, 66),
  ('mira-sem-marca', 'acessorio', 'Mira', 'sem marca', 'Mira topográfica, metálica, de invar, inteiriça 4m. cor: laranja.', null, true, 67),
  ('tripe-cst', 'acessorio', 'Tripé', 'CST', 'Tripé cabeça hidráulica, material em duralumínio, base em meia esfera engate rápido, altura máxima 1,90 m, bolsa de transporte.', null, true, 68),
  ('tripe-desetec-trident', 'acessorio', 'Tripé', 'Desetec/Trident', 'Tripé para equipamentos topográficos, em madeira, 3 torniquetes, 3 pés metalicos, em bolsa de couro com acessorio. cor: amarela.', null, true, 69),
  ('mira-mom', 'acessorio', 'Mira', 'MOM', 'Mira para leitura graduada, dobrável envernizada. cor verde.', null, true, 70),
  ('mira-zeiss', 'acessorio', 'Mira', 'Zeiss', 'Mira topográfica falante, 175cm, precisão 1cm, equipada com 1nivel e base de pretecao, em caixa de madeira. cor: amarela.', null, true, 71),
  ('micrometro-optico-mom', 'acessorio', 'Micrômetro óptico', 'MOM', 'Micrômetro óptico, para níveis de NI-B3, 4, 5, 6 em estojo de couro. cor: cinza.', null, true, 72),
  ('mira-miratec', 'acessorio', 'Mira', 'Miratec', 'Mira falante em madeira envernizada, com 3 peças de encaixar, medindo 3 metros. cor clara dimensões: 400x8x4,7 cm.', null, true, 73),
  ('base-topografica-mom', 'acessorio', 'Base topográfica', 'MOM', 'Base para medição topográfica, sem tripé, em caixa de madeira sem alça. cor: cinza.', null, true, 74),
  ('mira-amapal', 'acessorio', 'Mira', 'Amapal', 'Mira topográfica, dobrável, em alumínio, graduada, portátil. cor: cinza.', null, true, 75),
  ('oculares-mom', 'acessorio', 'Oculares', 'MOM', 'Conjunto de oculares de ângulos, em caixa de madeira. cor: cinza.', null, true, 76),
  ('oculares-sem-marca', 'acessorio', 'Oculares', 'sem marca', 'Estojo de oculares de cotovelo, composto de duas peças, referências: 704127 e 704211, em estojo de madeira aglomerada. cor: cinza e preta dimensões do estojo: 0,15x0,08x0,04 m.', null, true, 77),
  ('prisma-pentax', 'acessorio', 'Prisma', 'Pentax', 'Equipamento diversos para serviços profissionais, prisma para estação total.', null, true, 78),
  ('prumo-zenital-sem-marca', 'acessorio', 'Prumo zenital', 'sem marca', 'Prumo zenital óptico de precisão.', null, true, 79),
  ('tripe-sem-marca', 'acessorio', 'Tripé', 'sem marca', 'Tripé para equipamentos topográficos, em madeira envernizada, ref 20, estrutura metálica, 3 torniquetes. cor: verde.', null, true, 80),
  ('tripe-techgeo', 'acessorio', 'Tripé', 'Techgeo', 'Tripé para GPS, componente para o sistema RTK GTR-G2.', null, true, 81),
  ('tripe-trident', 'acessorio', 'Tripé', 'Trident', 'Tripé para equipamentos topográficos, em madeira acompanhado de 1 chave halem e 1 fio de plumo. cor: amarela.', null, true, 82),
  ('tripe-world', 'acessorio', 'Tripé', 'World', 'Tripé topográfico, em madeira pintada, regulável, pés com ponteira metálica. cor: laranja.', null, true, 83),
  ('planimetro-k-pluse', 'desenho', 'Planímetro', 'K+E', 'Planímetro compensado, acondicionado em estojo de madeira revestido em plástico, serial 51361. cor: verde.', null, true, 84),
  ('planimetro-mom', 'desenho', 'Planímetro', 'MOM', 'Planímetro, acondicionado em caixa de madeira revestida em plástico. cor: preta.', null, true, 85),
  ('planimetro-sem-marca', 'desenho', 'Planímetro', 'sem marca', 'Planímetro g. coradi ag zurich. acondicionado em estojo em madeira, com revestimento em plástico. cor: cinza.', null, true, 86),
  ('planimetro-tama-sokki', 'desenho', 'Planímetro', 'Tama Sokki', 'Planímetro, acondicionado em caixa de madeira revestida em plástico. cor: cinza.', null, true, 87),
  ('estereoscopio-zeiss', 'desenho', 'Estereoscópio', 'Zeiss', 'Estereoscópio de restituição, para fotografias até 30 x 30cm,composto de 1 estereoscópio de espelho com 2 oculares de 3.5 x 15 e 4 hastess para sustencao, 1 estereopantometro de desenho com guia paralela e 4 rodizios.', null, true, 88),
  ('normografo-leroy-keuffel-esser', 'desenho', 'Normógrafo', 'Leroy/Keuffel & Esser', 'Normógrafo, acondicionado em estojo de madeira envernizada, com 11 réguas, 11 penas, 1 aranha, 1 portatinta e 1 ponteirade grafite.', null, true, 89),
  ('normografo-trident', 'desenho', 'Normógrafo', 'Trident', 'Normógrafo completo em estojo de madeira envernizada, com 11 réguas, 10 penas com os seguintes números: 0.3 a 0.8; 1.0; 1.2; 1.5 e 1.8. dimensões do estojo: 0,44x0,17x0,06m.', null, true, 90),
  ('planimetro-ansler', 'desenho', 'Planímetro', 'Ansler', 'Planímetro, acondicionado em estojo de madeira revestido em plástico. cor: preta.', null, true, 91),
  ('regua-de-escala-kern', 'desenho', 'Régua de escala', 'Kern', 'Régua de escala topográfica, metálica, um transferidor metálico de 180 graus, um compasso bomba, 1 estojo para ponta seca,1 cintel, 1 alfinete para copia, 2 compassos para lapis, 1 compasso de linha pararelas.', null, true, 92),
  ('bosch-martelete', 'apoio', 'Bosch', 'Martelete', 'Martelete perfurador e rompedor para implantação de marcos e pinos.', 'martelete-bosch.webp', true, 93),
  ('buffalo-bfg-2500', 'apoio', 'Buffalo', 'BFG 2500', 'Gerador a gasolina para energia em campo.', 'gerador-buffalo-bfg-2500.webp', true, 94),
  ('camera-digital-nikon', 'apoio', 'Câmera digital', 'Nikon', 'Câmera digital.', 'camera-nikon.webp', true, 95);

insert into unidades (modelo_id, patrimonio, numero_serie, situacao, observacao) values
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gd2i', null, '[removido]', 'disponivel', null),
  ('geodetic-gt2-plus', '[removido]', null, 'disponivel', null),
  ('geodetic-gt2-plus', '[removido]', null, 'disponivel', null),
  ('geodetic-gt2-plus', '[removido]', null, 'disponivel', null),
  ('geodetic-gt2-plus', '[removido]', null, 'disponivel', null),
  ('geodetic-gt2-plus', '[removido]', null, 'disponivel', null),
  ('geodetic-gd8i', '[removido]', null, 'disponivel', null),
  ('geodetic-gd8i', '[removido]', null, 'disponivel', null),
  ('estacao-total-pentax', '[removido]', '[removido]', 'disponivel', null),
  ('topcon-es-65', '[removido]', null, 'disponivel', null),
  ('topcon-gts-102n', '[removido]', null, 'disponivel', null),
  ('topcon-gts-212', '[removido]', null, 'disponivel', null),
  ('chc-i50', '[removido]', null, 'disponivel', null),
  ('chc-i50', null, null, 'disponivel', 'Sem número de patrimônio na planilha.'),
  ('topomap-t10', '[removido]', null, 'disponivel', null),
  ('topomap-t10', '[removido]', null, 'disponivel', null),
  ('emlid-reach-rs2', '[removido]', null, 'disponivel', null),
  ('emlid-reach-rs2-plus', '[removido]', null, 'disponivel', null),
  ('javad-triumph-1', '[removido]', null, 'disponivel', null),
  ('hi-target-v200', '[removido]', null, 'disponivel', null),
  ('hi-target-v200', '[removido]', null, 'disponivel', null),
  ('receptor-gnss-trimble', '[removido]', '[removido]', 'disponivel', null),
  ('receptor-gnss-trimble', '[removido]', '[removido]', 'disponivel', null),
  ('receptor-gnss-leica', '[removido]', '[removido]', 'disponivel', null),
  ('receptor-gnss-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', null, 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-foif', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-foif', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-foif', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-foif', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-mom', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-siom', '[removido]', null, 'disponivel', null),
  ('nivel-wild', '[removido]', null, 'disponivel', null),
  ('topcon-dl-502', null, null, 'disponivel', 'Sem número de patrimônio na planilha.'),
  ('nivel-kern', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-kern', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-kern', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('luneta-de-nivel-niveltec', '[removido]', '[removido]', 'disponivel', null),
  ('luneta-de-nivel-niveltec', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-sion', '[removido]', '670', 'disponivel', null),
  ('nivel-sion', '[removido]', '[removido]', 'disponivel', null),
  ('nivel-gurley', '[removido]', null, 'disponivel', null),
  ('nivel-mitutoyo', '[removido]', null, 'disponivel', null),
  ('nivel-pzo', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-berger', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-world', '[removido]', '[removido]', 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('teodolito-world', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', null, 'disponivel', null),
  ('teodolito-vasconcelos', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-wild', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-wild', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-wild', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-wild', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-zeiss-jena', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-dfv', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-dfv', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-dfv', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-dfv', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-keuffel', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-keuffel', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-keuffel', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sunray', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sunray', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-sunray', '[removido]', '[removido]', 'disponivel', null),
  ('teodolito-breithaupt', '[removido]', null, 'disponivel', null),
  ('teodolito-mon-richer', '[removido]', null, 'disponivel', null),
  ('teodolito-oms', '[removido]', null, 'disponivel', null),
  ('teodolito-zuhio', '[removido]', null, 'disponivel', null),
  ('riegl-vz-400', '[removido]', null, 'disponivel', null),
  ('batmap-ii', '[removido]', null, 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('dji-mavic-air-2', '[removido]', null, 'disponivel', null),
  ('binoculo-bushnell', '[removido]', '[removido]', 'disponivel', null),
  ('telemetro-wild', '[removido]', null, 'disponivel', null),
  ('bussola-passed', '[removido]', null, 'disponivel', null),
  ('bussola-passed', '[removido]', null, 'disponivel', null),
  ('bussola-passed', '[removido]', null, 'disponivel', null),
  ('bussola-passed', '[removido]', null, 'disponivel', null),
  ('bussola-passed', '[removido]', null, 'disponivel', null),
  ('trena-eletronica-leica', '[removido]', null, 'disponivel', null),
  ('trena-eletronica-leica', '[removido]', null, 'disponivel', null),
  ('trena-eletronica-leica', '[removido]', null, 'disponivel', null),
  ('trena-eletronica-leica', '[removido]', null, 'disponivel', null),
  ('altimetro-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('altimetro-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('altimetro-wallace', '[removido]', '[removido]', 'disponivel', null),
  ('altimetro-wallace', '[removido]', '[removido]', 'disponivel', null),
  ('bussola-ushikata', '[removido]', '[removido]', 'disponivel', null),
  ('bussola-ushikata', '[removido]', '[removido]', 'disponivel', null),
  ('pantometro-sem-marca', '[removido]', null, 'disponivel', null),
  ('pantometro-sem-marca', '[removido]', null, 'disponivel', null),
  ('podometro-teiluiz', '[removido]', null, 'disponivel', null),
  ('podometro-teiluiz', '[removido]', null, 'disponivel', null),
  ('prancheta-topografica-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('prancheta-topografica-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('bussola-fuji', '[removido]', null, 'disponivel', null),
  ('bussola-osaka-tamaya', '[removido]', null, 'disponivel', null),
  ('clinometro-casella', '[removido]', null, 'disponivel', null),
  ('clinometro-fuji', '[removido]', null, 'disponivel', null),
  ('clinometro-meridian', '[removido]', null, 'disponivel', null),
  ('medidor-topografico-genovesi', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('tripe-miratec', '[removido]', null, 'disponivel', null),
  ('mira-foif', '[removido]', null, 'disponivel', null),
  ('mira-foif', '[removido]', null, 'disponivel', null),
  ('mira-foif', '[removido]', null, 'disponivel', null),
  ('mira-foif', '[removido]', null, 'disponivel', null),
  ('mira-foif', '[removido]', null, 'disponivel', null),
  ('baliza-sem-marca', '[removido]', null, 'disponivel', null),
  ('baliza-sem-marca', '[removido]', null, 'disponivel', null),
  ('baliza-sem-marca', '[removido]', null, 'disponivel', null),
  ('baliza-sem-marca', '[removido]', null, 'disponivel', null),
  ('mira-desetec-trident', '[removido]', null, 'disponivel', null),
  ('mira-desetec-trident', '[removido]', null, 'disponivel', null),
  ('mira-desetec-trident', '[removido]', null, 'disponivel', null),
  ('mira-desetec-trident', '[removido]', null, 'disponivel', null),
  ('mira-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('mira-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('mira-sem-marca', '[removido]', null, 'disponivel', null),
  ('mira-sem-marca', '[removido]', '[removido]', 'disponivel', null),
  ('tripe-cst', '[removido]', null, 'disponivel', null),
  ('tripe-cst', '[removido]', null, 'disponivel', null),
  ('tripe-cst', '[removido]', null, 'disponivel', null),
  ('tripe-cst', '[removido]', null, 'disponivel', null),
  ('tripe-desetec-trident', '[removido]', null, 'disponivel', null),
  ('tripe-desetec-trident', '[removido]', null, 'disponivel', null),
  ('tripe-desetec-trident', '[removido]', null, 'disponivel', null),
  ('tripe-desetec-trident', '[removido]', null, 'disponivel', null),
  ('mira-mom', '[removido]', null, 'disponivel', null),
  ('mira-mom', '[removido]', null, 'disponivel', null),
  ('mira-mom', '[removido]', null, 'disponivel', null),
  ('mira-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('mira-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('mira-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('micrometro-optico-mom', '[removido]', '[removido]', 'disponivel', null),
  ('micrometro-optico-mom', '[removido]', '[removido]', 'disponivel', null),
  ('mira-miratec', '[removido]', null, 'disponivel', null),
  ('mira-miratec', '[removido]', null, 'disponivel', null),
  ('base-topografica-mom', '[removido]', '[removido]', 'disponivel', null),
  ('mira-amapal', '[removido]', null, 'disponivel', null),
  ('oculares-mom', '[removido]', '[removido]', 'disponivel', null),
  ('oculares-sem-marca', '[removido]', null, 'disponivel', null),
  ('prisma-pentax', '[removido]', null, 'disponivel', null),
  ('prumo-zenital-sem-marca', '[removido]', null, 'disponivel', null),
  ('tripe-sem-marca', '[removido]', null, 'disponivel', null),
  ('tripe-techgeo', '[removido]', null, 'disponivel', null),
  ('tripe-trident', '[removido]', null, 'disponivel', null),
  ('tripe-world', '[removido]', null, 'disponivel', null),
  ('planimetro-k-pluse', '[removido]', '[removido]', 'disponivel', null),
  ('planimetro-k-pluse', '[removido]', '[removido]', 'disponivel', null),
  ('planimetro-k-pluse', '[removido]', null, 'disponivel', null),
  ('planimetro-k-pluse', '[removido]', null, 'disponivel', null),
  ('planimetro-k-pluse', '[removido]', null, 'disponivel', null),
  ('planimetro-mom', '[removido]', '[removido]', 'disponivel', null),
  ('planimetro-mom', '[removido]', '[removido]', 'disponivel', null),
  ('planimetro-sem-marca', '[removido]', null, 'disponivel', null),
  ('planimetro-sem-marca', '[removido]', null, 'disponivel', null),
  ('planimetro-tama-sokki', '[removido]', null, 'disponivel', null),
  ('planimetro-tama-sokki', '[removido]', null, 'disponivel', null),
  ('estereoscopio-zeiss', '[removido]', '[removido]', 'disponivel', null),
  ('normografo-leroy-keuffel-esser', '[removido]', '[removido]', 'disponivel', null),
  ('normografo-trident', '[removido]', null, 'disponivel', null),
  ('planimetro-ansler', '[removido]', '[removido]', 'disponivel', null),
  ('regua-de-escala-kern', '[removido]', null, 'disponivel', null),
  ('bosch-martelete', '[removido]', null, 'disponivel', null),
  ('buffalo-bfg-2500', '[removido]', null, 'disponivel', null),
  ('camera-digital-nikon', '[removido]', '[removido]', 'disponivel', null);

-- ===== 004_horarios.sql =====
-- Horário de aulas EAM (fonte: DTI/UFV). Gerado por scripts/importar-horarios.mjs.

insert into semestres (id, ano, semestre) values
  ('2026-1', 2026, 1),
  ('2026-2', 2026, 2)
on conflict (id) do nothing;

insert into disciplinas (codigo, nome) values
  ('EAM 190', 'INTRODUÇÃO À ENGENHARIA DE AGRIMENSURA E CARTOGRÁFICA'),
  ('EAM 191', 'INTRODUÇÃO À EXTENSÃO UNIVERSITÁRIA'),
  ('EAM 300', 'TOPOGRAFIA E ESTRADAS'),
  ('EAM 301', 'TOPOGRAFIA BÁSICA'),
  ('EAM 310', 'TOPOGRAFIA I'),
  ('EAM 311', 'TOPOGRAFIA II'),
  ('EAM 312', 'TOPOGRAFIA III'),
  ('EAM 313', 'TOPOGRAFIA IV'),
  ('EAM 330', 'CARTOGRAFIA GERAL'),
  ('EAM 351', 'FUNDAMENTOS DE SISTEMAS DE INFORMAÇÃO GEOGRÁFICA'),
  ('EAM 380', 'AJUSTAMENTO DE OBSERVAÇÕES'),
  ('EAM 392', 'ATIVIDADES DE EXTENSÃO PARA O CURSO DE ENGENHARIA DE AGRIMENSURA E CARTOGRÁFICA'),
  ('EAM 393', 'PROJETO DE EXTENSÃO I'),
  ('EAM 394', 'PROJETO DE EXTENSÃO II'),
  ('EAM 410', 'HIDROGRAFIA I'),
  ('EAM 420', 'GEODÉSIA III'),
  ('EAM 421', 'GEODÉSIA I'),
  ('EAM 422', 'GEODESIA II'),
  ('EAM 431', 'PROJEÇÕES CARTOGRÁFICAS'),
  ('EAM 433', 'CARTOGRAFIA DIGITAL I'),
  ('EAM 434', 'CARTOGRAFIA DIGITAL II'),
  ('EAM 436', 'CONTROLE DE QUALIDADE CARTOGRÁFICA'),
  ('EAM 440', 'TOPOGRAFIA DIGITAL'),
  ('EAM 441', 'DESENHO TOPOGRÁFICO DIGITAL'),
  ('EAM 442', 'PROCESSAMENTO DE DADOS HIDROGRÁFICOS'),
  ('EAM 450', 'SENSORIAMENTO REMOTO I'),
  ('EAM 451', 'SISTEMA DE INFORMAÇÃO GEOGRÁFICA'),
  ('EAM 461', 'ENGENHARIA DE AVALIAÇÃO'),
  ('EAM 463', 'PARCELAMENTO DO SOLO URBANO E RURAL'),
  ('EAM 464', 'CADASTRO TERRITORIAL MULTIFINALITÁRIO'),
  ('EAM 465', 'INTELIGÊNCIA GEOESPACIAL E GESTÃO TERRITORIAL'),
  ('EAM 470', 'FOTOGRAMETRIA I'),
  ('EAM 471', 'FOTOGRAMETRIA II'),
  ('EAM 480', 'PROGRAMAÇÃO APLICADA À ENGENHARIA DE AGRIMENSURA E CARTOGRÁFICA'),
  ('EAM 482', 'BANCO DE DADOS GEOGRÁFICOS'),
  ('EAM 484', 'CIÊNCIA DE DADOS GEOESPACIAIS'),
  ('EAM 492', 'ESTÁGIO SUPERVISIONADO'),
  ('EAM 493', 'ATIVIDADES COMPLEMENTARES I'),
  ('EAM 494', 'ATIVIDADES COMPLEMENTARES II'),
  ('EAM 495', 'ATIVIDADES COMPLEMENTARES III'),
  ('EAM 496', 'ATIVIDADES COMPLEMENTARES IV'),
  ('EAM 497', 'SEMINÁRIO E MONOGRAFIA I'),
  ('EAM 498', 'SEMINÁRIO E MONOGRAFIA II'),
  ('EAM 499', 'TÓPICOS EM ENGENHARIA DE AGRIMENSURA E CARTOGRÁFICA'),
  ('EAM 610', 'GEOACÚSTICA SUBMARINA'),
  ('EAM 620', 'POSICIONAMENTO POR SATÉLITES'),
  ('EAM 630', 'APRENDIZADO DE MÁQUINA: PRINCÍPIOS E APLICAÇÕES'),
  ('EAM 640', 'QUALIDADE DE DADOS GEOESPACIAIS I'),
  ('EAM 650', 'SENSORIAMENTO REMOTO AVANÇADO'),
  ('EAM 670', 'FOTOGRAMETRIA DIGITAL I')
on conflict (codigo) do update set nome = excluded.nome;

delete from aulas where semestre_id in ('2026-1', '2026-2');
insert into aulas (semestre_id, disciplina_codigo, tipo, turma, dia_semana, hora_inicio, hora_fim, sala) values
  ('2026-1', 'EAM 190', 'T', 1, 2, 14, 15, 'PVB200'),
  ('2026-1', 'EAM 300', 'T', 1, 2, 9, 10, 'PVB304'),
  ('2026-1', 'EAM 300', 'T', 1, 4, 14, 16, 'PVB304'),
  ('2026-1', 'EAM 300', 'P', 1, 3, 8, 10, 'LEA102'),
  ('2026-1', 'EAM 300', 'P', 2, 3, 16, 18, 'LEA102'),
  ('2026-1', 'EAM 301', 'T', 1, 6, 8, 10, 'PVA239'),
  ('2026-1', 'EAM 301', 'T', 2, 6, 10, 12, 'PVA153'),
  ('2026-1', 'EAM 301', 'P', 1, 4, 8, 10, 'LEA102'),
  ('2026-1', 'EAM 301', 'P', 2, 4, 16, 18, 'LEA102'),
  ('2026-1', 'EAM 301', 'P', 3, 5, 8, 10, 'LEA102'),
  ('2026-1', 'EAM 301', 'P', 4, 5, 16, 18, 'LEA102'),
  ('2026-1', 'EAM 301', 'P', 5, 6, 8, 10, 'LEA102'),
  ('2026-1', 'EAM 301', 'P', 6, 6, 16, 18, 'LEA102'),
  ('2026-1', 'EAM 310', 'T', 1, 3, 14, 16, 'PVA353'),
  ('2026-1', 'EAM 310', 'P', 1, 4, 8, 10, 'LEA101'),
  ('2026-1', 'EAM 310', 'P', 2, 5, 10, 12, 'LEA101'),
  ('2026-1', 'EAM 312', 'T', 1, 2, 16, 18, 'PVA284'),
  ('2026-1', 'EAM 312', 'P', 1, 2, 8, 10, 'LEA101'),
  ('2026-1', 'EAM 312', 'P', 2, 2, 10, 12, 'LEA101'),
  ('2026-1', 'EAM 330', 'T', 1, 2, 16, 18, 'PVA165'),
  ('2026-1', 'EAM 330', 'T', 1, 3, 16, 18, 'PVA277'),
  ('2026-1', 'EAM 380', 'T', 1, 3, 16, 18, 'LEA101'),
  ('2026-1', 'EAM 380', 'T', 1, 4, 10, 12, 'LEA101'),
  ('2026-1', 'EAM 393', 'P', 1, 5, 7, 12, 'CCE322'),
  ('2026-1', 'EAM 410', 'T', 1, 2, 16, 18, 'CCE319'),
  ('2026-1', 'EAM 410', 'T', 1, 4, 14, 16, 'CCE319'),
  ('2026-1', 'EAM 420', 'T', 1, 3, 10, 12, 'PVA310'),
  ('2026-1', 'EAM 420', 'P', 1, 3, 14, 16, 'CCE322'),
  ('2026-1', 'EAM 421', 'T', 1, 3, 10, 12, 'PVA172'),
  ('2026-1', 'EAM 421', 'T', 1, 3, 14, 16, 'PVA172'),
  ('2026-1', 'EAM 433', 'T', 1, 5, 14, 15, 'CCE323'),
  ('2026-1', 'EAM 433', 'P', 1, 5, 15, 17, 'CCE323'),
  ('2026-1', 'EAM 436', 'T', 1, 5, 8, 10, 'CCE323'),
  ('2026-1', 'EAM 436', 'P', 1, 5, 10, 12, 'CCE323'),
  ('2026-1', 'EAM 441', 'P', 1, 6, 8, 10, 'CCE322'),
  ('2026-1', 'EAM 441', 'P', 2, 6, 10, 12, 'CCE322'),
  ('2026-1', 'EAM 442', 'T', 1, 6, 13, 16, 'CCE322'),
  ('2026-1', 'EAM 450', 'T', 1, 2, 10, 12, 'PVA115'),
  ('2026-1', 'EAM 450', 'P', 1, 2, 16, 18, 'CCE322'),
  ('2026-1', 'EAM 450', 'P', 2, 2, 14, 16, 'CCE322'),
  ('2026-1', 'EAM 451', 'P', 1, 3, 14, 18, 'CCE323'),
  ('2026-1', 'EAM 451', 'P', 2, 6, 14, 18, 'CCE323'),
  ('2026-1', 'EAM 463', 'T', 1, 3, 8, 10, 'PVA388'),
  ('2026-1', 'EAM 463', 'P', 1, 6, 8, 10, 'CCE323'),
  ('2026-1', 'EAM 463', 'P', 2, 6, 16, 18, 'CCE322'),
  ('2026-1', 'EAM 465', 'T', 1, 2, 8, 10, 'CCE322'),
  ('2026-1', 'EAM 465', 'P', 1, 4, 10, 12, 'CCE322'),
  ('2026-1', 'EAM 471', 'T', 1, 5, 14, 16, 'CCE321'),
  ('2026-1', 'EAM 471', 'P', 1, 5, 16, 18, 'CCE321'),
  ('2026-1', 'EAM 482', 'T', 1, 3, 8, 10, 'LEA101'),
  ('2026-1', 'EAM 482', 'P', 1, 4, 8, 10, 'CCE322'),
  ('2026-1', 'EAM 484', 'T', 1, 4, 16, 18, 'CCE323'),
  ('2026-1', 'EAM 484', 'P', 1, 6, 10, 12, 'CCE323'),
  ('2026-1', 'EAM 497', 'T', 1, 2, 10, 11, 'CCE319'),
  ('2026-1', 'EAM 498', 'T', 1, 2, 14, 15, 'LEA101'),
  ('2026-1', 'EAM 499', 'T', 1, 6, 8, 9, 'LEA103'),
  ('2026-1', 'EAM 499', 'P', 1, 6, 9, 12, 'LEA103'),
  ('2026-1', 'EAM 620', 'T', 1, 5, 8, 12, 'CCE321'),
  ('2026-1', 'EAM 630', 'T', 1, 4, 8, 9, 'CCE321'),
  ('2026-1', 'EAM 630', 'P', 1, 4, 9, 12, 'CCE321'),
  ('2026-1', 'EAM 670', 'T', 1, 3, 14, 16, 'CCE321'),
  ('2026-1', 'EAM 670', 'P', 1, 3, 16, 18, 'CCE321'),
  ('2026-2', 'EAM 191', 'T', 1, 3, 8, 10, 'PVB107'),
  ('2026-2', 'EAM 300', 'T', 1, 2, 15, 16, 'PVA117'),
  ('2026-2', 'EAM 300', 'T', 1, 4, 8, 10, 'PVA277'),
  ('2026-2', 'EAM 300', 'T', 2, 2, 16, 17, 'PVA117'),
  ('2026-2', 'EAM 300', 'T', 2, 4, 14, 16, 'PVA277'),
  ('2026-2', 'EAM 300', 'P', 1, 3, 16, 18, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 2, 3, 14, 16, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 3, 3, 8, 10, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 4, 4, 10, 12, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 5, 5, 10, 12, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 6, 3, 10, 12, 'LEA102'),
  ('2026-2', 'EAM 300', 'P', 7, 4, 8, 10, 'LEA102'),
  ('2026-2', 'EAM 301', 'T', 1, 2, 16, 18, 'PVB300'),
  ('2026-2', 'EAM 301', 'T', 2, 2, 14, 16, 'PVA153'),
  ('2026-2', 'EAM 301', 'P', 1, 4, 16, 18, 'LEA101'),
  ('2026-2', 'EAM 301', 'P', 2, 5, 8, 10, 'LEA101'),
  ('2026-2', 'EAM 301', 'P', 3, 5, 16, 18, 'LEA102'),
  ('2026-2', 'EAM 301', 'P', 4, 6, 8, 10, 'LEA102'),
  ('2026-2', 'EAM 311', 'T', 1, 3, 10, 12, 'PVA353'),
  ('2026-2', 'EAM 311', 'P', 1, 3, 14, 16, 'LEA103'),
  ('2026-2', 'EAM 311', 'P', 2, 3, 16, 18, 'LEA103'),
  ('2026-2', 'EAM 313', 'T', 1, 3, 8, 10, 'LEA101'),
  ('2026-2', 'EAM 313', 'P', 1, 5, 10, 12, 'CCE323'),
  ('2026-2', 'EAM 351', 'P', 1, 2, 8, 12, 'CCE322'),
  ('2026-2', 'EAM 351', 'P', 2, 5, 8, 12, 'CCE322'),
  ('2026-2', 'EAM 394', 'P', 1, 4, 14, 18, 'CCE323'),
  ('2026-2', 'EAM 422', 'T', 1, 2, 10, 12, 'PVA310'),
  ('2026-2', 'EAM 422', 'T', 1, 5, 8, 10, 'PVA310'),
  ('2026-2', 'EAM 422', 'P', 1, 2, 14, 16, 'CCE323'),
  ('2026-2', 'EAM 431', 'T', 1, 5, 14, 16, 'CCE322'),
  ('2026-2', 'EAM 431', 'P', 1, 5, 16, 18, 'CCE322'),
  ('2026-2', 'EAM 434', 'T', 1, 5, 14, 15, 'CCE323'),
  ('2026-2', 'EAM 434', 'P', 1, 5, 15, 17, 'CCE323'),
  ('2026-2', 'EAM 440', 'P', 1, 3, 14, 16, 'CCE323'),
  ('2026-2', 'EAM 440', 'P', 2, 3, 16, 18, 'CCE323'),
  ('2026-2', 'EAM 442', 'T', 1, 2, 10, 12, 'CCE323'),
  ('2026-2', 'EAM 442', 'T', 1, 2, 13, 14, 'CCE323'),
  ('2026-2', 'EAM 451', 'P', 1, 3, 14, 18, 'CCE322'),
  ('2026-2', 'EAM 461', 'T', 1, 6, 14, 16, 'CCE322'),
  ('2026-2', 'EAM 461', 'P', 1, 6, 16, 18, 'CCE322'),
  ('2026-2', 'EAM 464', 'T', 1, 2, 8, 10, 'PVA348'),
  ('2026-2', 'EAM 464', 'P', 1, 3, 10, 12, 'CCE323'),
  ('2026-2', 'EAM 470', 'T', 1, 4, 16, 18, 'LEA102'),
  ('2026-2', 'EAM 470', 'P', 1, 5, 8, 10, 'CCE321'),
  ('2026-2', 'EAM 480', 'P', 1, 4, 14, 16, 'CCE322'),
  ('2026-2', 'EAM 497', 'T', 1, 6, 13, 14, 'LEA103'),
  ('2026-2', 'EAM 498', 'T', 1, 4, 13, 14, 'LEA101'),
  ('2026-2', 'EAM 499', 'T', 1, 6, 8, 9, 'LEA103'),
  ('2026-2', 'EAM 499', 'P', 1, 6, 9, 12, 'LEA103'),
  ('2026-2', 'EAM 610', 'T', 1, 2, 14, 17, 'CCE321'),
  ('2026-2', 'EAM 650', 'T', 1, 3, 14, 16, 'CCE321'),
  ('2026-2', 'EAM 650', 'P', 1, 3, 16, 18, 'CCE321');
