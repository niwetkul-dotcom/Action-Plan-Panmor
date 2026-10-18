-- Run after applying migrations with `npx supabase test db`.
begin;
do $$
declare
  missing text;
begin
  select string_agg(t.name, ', ') into missing
  from (values
    ('schools'),('school_settings'),('fiscal_years'),('departments'),('profiles'),('role_assignments'),
    ('fund_sources'),('funding_envelopes'),('reference_categories'),('reference_items'),('projects'),
    ('project_revisions'),('activities'),('budget_items'),('project_assessment_items'),('approval_actions'),('funding_requests'),('funding_request_actions'),
    ('ledger_entries'),('project_reports'),('cipp_items'),('cipp_responses'),('evidence_files')
  ) as t(name)
  join pg_class c on c.relname=t.name join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relrowsecurity is false;
  if missing is not null then raise exception 'RLS is not enabled on: %', missing; end if;

  if exists (
    select 1 from pg_policies p
    where p.schemaname='public' and p.tablename in ('projects','ledger_entries','profiles','role_assignments')
      and coalesce(trim(p.qual::text),'') in ('true','(true)')
  ) then raise exception 'A core data policy is unconditionally open'; end if;

  if has_table_privilege('anon','public.projects','select') then
    raise exception 'anon role must not have direct project table access';
  end if;
  if has_function_privilege('anon','public.submit_project(uuid)','execute') then
    raise exception 'anon role must not execute project workflow RPCs';
  end if;
  if not has_function_privilege('authenticated','public.submit_project(uuid)','execute') then
    raise exception 'authenticated role must be able to submit through the protected RPC';
  end if;
end $$;
rollback;
