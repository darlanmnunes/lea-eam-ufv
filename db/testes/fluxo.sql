-- Percorre o fluxo completo e confere as travas. Falha com exceção se algo sair do esperado.
\set ON_ERROR_STOP on
\set QUIET on

insert into pessoas (id, nome, email, matricula, telefone, papeis) values
  ('00000000-0000-0000-0000-000000000001', 'Estudante Teste', 'estudante@ufv.example', '100001', '31 0000-0001', '{solicitante}'),
  ('00000000-0000-0000-0000-000000000002', 'Coordenação Teste', 'coord@ufv.example', '200001', '31 0000-0002', '{solicitante,coordenacao}'),
  ('00000000-0000-0000-0000-000000000003', 'Responsável Teste', 'lea@ufv.example', '300001', '31 0000-0003', '{solicitante,responsavel_lea}'),
  ('00000000-0000-0000-0000-000000000004', 'Técnico Teste', 'tecnico@ufv.example', '400001', '31 0000-0004', '{solicitante,tecnico}'),
  ('00000000-0000-0000-0000-000000000005', 'Outra Estudante', 'outra@ufv.example', '100002', '31 0000-0005', '{solicitante}');

create function pg_temp.como(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p::text, false)
$$;

create function pg_temp.deve_falhar(p_sql text, p_trecho text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_trecho in sqlerrm) = 0 then
      raise exception 'Falhou com outra mensagem: % (esperado: %)', sqlerrm, p_trecho;
    end if;
    return;
  end;
  raise exception 'Deveria ter falhado: %', p_sql;
end $$;

create temp table t (id uuid, u1 uuid, u2 uuid);
grant all on t to authenticated;
insert into t (u1, u2)
  select (select id from unidades where patrimonio = '356629'),
         (select id from unidades where numero_serie = '173675');

set role authenticated;

-- 1. pedido
select pg_temp.como('00000000-0000-0000-0000-000000000001');
update t set id = criar_emprestimo('Aula de campo', 'EAM 301', 'Viçosa',
  current_date + 1, current_date + 3, array['Colega A'], null,
  (select jsonb_build_array(jsonb_build_object('unidade_id', u1), jsonb_build_object('unidade_id', u2, 'observacao', 'com tripé')) from t));

-- mesma unidade no mesmo período: recusa
select pg_temp.como('00000000-0000-0000-0000-000000000005');
select pg_temp.deve_falhar(format($q$select criar_emprestimo('x','y','z', current_date + 2, current_date + 5, '{}', null, '[{"unidade_id":"%s"}]')$q$, (select u1 from t)), 'comprometida');
-- outra pessoa não enxerga o pedido
do $$ begin if (select count(*) from emprestimos) <> 0 then raise exception 'RLS: pedido alheio visível'; end if; end $$;

-- 2. etapas fora de ordem e por quem não deve
select pg_temp.como('00000000-0000-0000-0000-000000000001');
select pg_temp.deve_falhar(format($q$select avancar_emprestimo('%s','autorizar')$q$, (select id from t)), 'coordenação');
select pg_temp.como('00000000-0000-0000-0000-000000000004');
select pg_temp.deve_falhar(format($q$select avancar_emprestimo('%s','entregar')$q$, (select id from t)), 'não cabe');

-- 3. autorizações
select pg_temp.como('00000000-0000-0000-0000-000000000002');
select avancar_emprestimo((select id from t), 'autorizar', 'De acordo.');
select pg_temp.como('00000000-0000-0000-0000-000000000003');
select avancar_emprestimo((select id from t), 'autorizar');

-- 4. retirada: técnico confere, solicitante dá ciente
select pg_temp.como('00000000-0000-0000-0000-000000000004');
select pg_temp.deve_falhar(format($q$select avancar_emprestimo('%s','entregar')$q$, (select id from t)), 'Confira todos');
select avancar_emprestimo((select id from t), 'entregar', 'Baterias carregadas.',
  (select jsonb_agg(jsonb_build_object('item_id', i.id, 'estado', 'conforme')) from emprestimo_itens i where i.emprestimo_id = (select id from t)));
select pg_temp.deve_falhar(format($q$select avancar_emprestimo('%s','ciente_retirada')$q$, (select id from t)), 'quem fez o pedido');
select pg_temp.como('00000000-0000-0000-0000-000000000001');
select avancar_emprestimo((select id from t), 'ciente_retirada');

-- 5. prorrogação
select avancar_emprestimo((select id from t), 'pedir_prorrogacao', 'Chuva atrasou o campo.');
select pg_temp.como('00000000-0000-0000-0000-000000000003');
select avancar_emprestimo((select id from t), 'autorizar_prorrogacao', null, null, current_date + 5);

-- 6. devolução com ressalva exige descrição
select pg_temp.como('00000000-0000-0000-0000-000000000004');
select pg_temp.deve_falhar(format($q$select avancar_emprestimo('%s','receber', null, '%s')$q$, (select id from t),
  (select jsonb_agg(jsonb_build_object('item_id', i.id, 'estado', 'com_ressalva')) from emprestimo_itens i where i.emprestimo_id = (select id from t))), 'ressalva');
select avancar_emprestimo((select id from t), 'receber', null,
  (select jsonb_agg(jsonb_build_object('item_id', i.id, 'estado', 'com_ressalva', 'obs', 'Prumo óptico desregulado')) from emprestimo_itens i where i.emprestimo_id = (select id from t)));
select pg_temp.como('00000000-0000-0000-0000-000000000001');
select avancar_emprestimo((select id from t), 'ciente_devolucao', 'Ciente da ressalva.');

do $$
declare n int; s status_emprestimo;
begin
  select status into s from emprestimos;
  if s <> 'encerrado' then raise exception 'Status final inesperado: %', s; end if;
  select count(*) into n from emprestimo_eventos;
  if n <> 9 then raise exception 'Esperava 9 eventos, há %', n; end if;
  if (select count(*) from ocupacao) <> 0 then raise exception 'Ocupação não liberou'; end if;
end $$;

-- 6b. aulas práticas reservam equipamento
reset role;
update semestres set inicio = current_date - 30, fim = current_date + 60 where id = '2026-2';
insert into pessoas (id, nome, email, matricula, telefone, papeis) values
  ('00000000-0000-0000-0000-000000000006', 'Docente Teste', 'docente@ufv.example', '500001', '31 0000-0006', '{solicitante,docente}'),
  ('00000000-0000-0000-0000-000000000007', 'Admin Teste', 'admin@ufv.example', '600001', '31 0000-0007', '{solicitante,admin}');
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-000000000001');
select pg_temp.deve_falhar($q$select definir_uso_disciplina('EAM 300', 'geodetic-gd2i', 6)$q$, 'docentes');
select pg_temp.como('00000000-0000-0000-0000-000000000006');
select pg_temp.deve_falhar($q$select definir_uso_disciplina('EAM 300', 'geodetic-gd2i', 7)$q$, 'tantas unidades');
select definir_uso_disciplina('EAM 300', 'geodetic-gd2i', 6);
do $$ begin
  if reserva_aulas('geodetic-gd2i', current_date, current_date + 6) <> 6 then raise exception 'Reserva de aula não contou'; end if;
  if reserva_aulas('topcon-es-65', current_date, current_date + 6) <> 0 then raise exception 'Reserva indevida'; end if;
end $$;
-- uma semana inteira pega a terça de EAM 300: as 6 GD2i estão em aula
select pg_temp.como('00000000-0000-0000-0000-000000000005');
select pg_temp.deve_falhar(format($q$select criar_emprestimo('x','y','z', current_date + 1, current_date + 8, '{}', null, '[{"unidade_id":"%s"}]')$q$, (select u2 from t)), 'aulas práticas');
-- papéis: só a administração
select pg_temp.deve_falhar($q$select definir_papeis('00000000-0000-0000-0000-000000000005', '{tecnico}')$q$, 'administração');
select pg_temp.como('00000000-0000-0000-0000-000000000007');
select definir_papeis('00000000-0000-0000-0000-000000000005', '{tecnico}');
reset role;
do $$ begin
  if not (select papeis @> '{solicitante,tecnico}' from pessoas where id = '00000000-0000-0000-0000-000000000005') then
    raise exception 'Papéis não gravados';
  end if;
end $$;

-- 6c. lembretes: sai um por pendência e não repete dentro do intervalo
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-000000000001');
select criar_emprestimo('Campo', 'TCC', 'Viçosa', current_date + 1, current_date + 1, '{}', null,
  format('[{"unidade_id":"%s"}]', (select u1 from t))::jsonb);
reset role;
set role service_role;
do $$ declare n int; begin
  select count(*) into n from lembretes_a_enviar();
  if n <> 1 then raise exception 'Esperava 1 lembrete (coordenação), vieram %', n; end if;
  select count(*) into n from lembretes_a_enviar();
  if n <> 0 then raise exception 'Lembrete repetido dentro do intervalo'; end if;
  select count(*) into n from lembretes_a_enviar(interval '0 seconds');
  if n <> 1 then raise exception 'Lembrete não voltou após o intervalo'; end if;
end $$;
reset role;

-- 7. o registro de assinaturas não se altera
reset role;
select pg_temp.deve_falhar('delete from emprestimo_eventos', 'não pode ser alterado');

-- 8. visitante vê o acervo, não vê pedidos
set role anon;
do $$ begin
  if (select count(*) from unidades) < 20 then raise exception 'Acervo não visível ao visitante'; end if;
end $$;
select pg_temp.deve_falhar('select * from emprestimos', 'permission denied');
reset role;

\echo 'Fluxo completo: OK'
