-- 007: patrimônio e número de série deixam de ser públicos.
-- Para o banco que já recebeu 001 a 006 (instalações novas já trazem isto em 002).
-- Sem login, a tabela unidades entrega só id, modelo, situação e observação. Patrimônio e série vêm
-- de identificacao_unidades(), que responde só a quem tem cadastro (conta @ufv.br).

create or replace function identificacao_unidades()
returns table (id uuid, patrimonio text, numero_serie text)
language sql stable security definer set search_path = public as $$
  select u.id, u.patrimonio, u.numero_serie from unidades u
   where exists (select 1 from pessoas p where p.id = auth.uid())
$$;

revoke select on unidades from anon, authenticated;
grant select (id, modelo_id, situacao, observacao) on unidades to anon, authenticated;

revoke execute on function identificacao_unidades() from public;
grant execute on function identificacao_unidades() to anon, authenticated;
