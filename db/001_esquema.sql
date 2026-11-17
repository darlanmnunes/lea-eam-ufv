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
