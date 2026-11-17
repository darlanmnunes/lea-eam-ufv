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
  ordem         int not null default 0
);

create table unidades (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     text not null references modelos(id),
  patrimonio    text,                      -- nº de patrimônio UFV
  numero_serie  text,                      -- quando não há patrimônio
  situacao      situacao_unidade not null default 'disponivel',
  observacao    text,
  unique (patrimonio),
  unique (modelo_id, numero_serie)
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
  v_email text := auth.jwt() ->> 'email';
begin
  if auth.uid() is null then raise exception 'Entre para continuar'; end if;
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
  ('laser-scanner', 'Laser scanner', 'LS', 4),
  ('aeronave', 'Drones e VANT', 'VT', 5),
  ('apoio', 'Apoio de campo', 'AP', 6);

insert into modelos (id, categoria_id, marca, nome, descricao, foto, ordem) values
  ('geodetic-gd2i', 'estacao-total', 'Geodetic', 'GD2i', 'Estação total das aulas práticas de Topografia. É o modelo com mais unidades no laboratório.', 'geodetic-gd2i.webp', 1),
  ('geodetic-gd8i', 'estacao-total', 'Geodetic', 'GD8i', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gd8i.webp', 2),
  ('geodetic-gt2-plus', 'estacao-total', 'Geodetic', 'GT2+', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gt2-plus.webp', 3),
  ('topcon-gts-212', 'estacao-total', 'Topcon', 'GTS-212', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-212.webp', 4),
  ('topcon-gts-102n', 'estacao-total', 'Topcon', 'GTS-102N', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-102n.webp', 5),
  ('topcon-es-65', 'estacao-total', 'Topcon', 'ES-65', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-es-65.webp', 6),
  ('topomap-t10', 'gnss', 'Topomap', 'T10', 'Par base e rover para posicionamento RTK.', 'rtk-topomap-t10.webp', 7),
  ('chc-i50', 'gnss', 'CHC Nav', 'i50', 'Receptor GNSS para posicionamento RTK.', 'chc-nav-i50.webp', 8),
  ('hi-target-v200', 'gnss', 'Hi-Target', 'V200', 'Receptor GNSS para posicionamento RTK.', null, 9),
  ('javad-triumph-1', 'gnss', 'Javad', 'Triumph-1', 'Receptor GNSS geodésico para rastreio estático e apoio de campo.', 'javad-trimph-1.webp', 10),
  ('emlid-reach-rs2', 'gnss', 'Emlid', 'Reach RS2', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emild-reach-rs2.webp', 11),
  ('emlid-reach-rs2-plus', 'gnss', 'Emlid', 'Reach RS2+', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emilid-reach-rs2-plus.webp', 12),
  ('topcon-dl-502', 'nivel', 'Topcon', 'DL-502', 'Nível digital para nivelamento geométrico.', 'nivel-topcon-dl-502.webp', 13),
  ('riegl-vz-400', 'laser-scanner', 'Riegl', 'VZ-400', 'Laser scanner terrestre para nuvens de pontos.', 'riegl-vz-400.webp', 14),
  ('batmap-ii', 'aeronave', 'Batmap', 'II', 'VANT de asa fixa para aerolevantamento.', 'batmap-ii.webp', 15),
  ('dji-mavic-air-2', 'aeronave', 'DJI', 'Mavic Air 2', 'Drone multirrotor para imagens aéreas.', 'drone-dji-mavic-air-2.webp', 16),
  ('buffalo-bfg-2500', 'apoio', 'Buffalo', 'BFG 2500', 'Gerador a gasolina para energia em campo.', 'gerador-buffalo-bfg-2500.webp', 17),
  ('bosch-martelete', 'apoio', 'Bosch', 'Martelete', 'Martelete para implantação de marcos e pinos.', 'martelete-bosch.webp', 18);

insert into unidades (modelo_id, patrimonio, numero_serie, observacao) values
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd2i', null, '[removido]', null),
  ('geodetic-gd8i', null, '287402', null),
  ('geodetic-gd8i', null, '288160', null),
  ('geodetic-gt2-plus', null, null, 'Fora da planilha de controle: confirmar patrimônio.'),
  ('topcon-gts-212', '[removido]', null, null),
  ('topcon-gts-102n', '[removido]', null, null),
  ('topcon-es-65', '[removido]', null, null),
  ('topomap-t10', '[removido]', null, null),
  ('chc-i50', '[removido]', null, null),
  ('hi-target-v200', '[removido]', null, null),
  ('javad-triumph-1', '[removido]', null, null),
  ('emlid-reach-rs2', null, null, 'Fora da planilha de controle: confirmar patrimônio.'),
  ('emlid-reach-rs2-plus', null, null, 'Fora da planilha de controle: confirmar patrimônio.'),
  ('topcon-dl-502', null, null, 'Sem número de patrimônio na planilha.'),
  ('riegl-vz-400', '[removido]', null, null),
  ('batmap-ii', '[removido]', null, null),
  ('dji-mavic-air-2', null, null, 'Fora da planilha de controle: confirmar patrimônio.'),
  ('buffalo-bfg-2500', '[removido]', null, null),
  ('bosch-martelete', '[removido]', null, null);

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
