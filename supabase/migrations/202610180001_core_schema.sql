-- Ban Pan Mor project system: secure relational foundation
-- Run with Supabase CLI migrations. Never replace the policies below with USING (true).
create extension if not exists pgcrypto;

create type public.app_role as enum ('admin','teacher','department_head','budget_head','deputy_director','director');
create type public.document_status as enum ('draft','submitted','in_review','returned','approved','rejected','withdrawn','archived');
create type public.ledger_entry_type as enum ('payment','refund','adjustment','reversal','opening_balance');

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  authority text not null default 'สำนักงานเขตพื้นที่การศึกษาประถมศึกษาจันทบุรี เขต 2',
  created_at timestamptz not null default now()
);
insert into public.schools (id,name) values ('b0000000-0000-4000-8000-000000000001','โรงเรียนบ้านปั้นหม้อ') on conflict do nothing;

create table public.school_settings (
  school_id uuid primary key references public.schools(id),
  address text, phone text, director_name text, deputy_name text,
  logo_object_key text, garuda_object_key text, document_font_name text,
  theme_primary text not null default '#8b7bd8', theme_accent text not null default '#35b4b0',
  footer_text text, updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
create table public.fiscal_years (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  label text not null, start_date date not null, end_date date not null, is_open boolean not null default true,
  closed_at timestamptz, closed_by uuid references auth.users(id), reopen_reason text,
  created_at timestamptz not null default now(), unique(school_id,label), check(start_date <= end_date)
);
create table public.departments (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null check(name in ('กลุ่มบริหารวิชาการ','กลุ่มบริหารงบประมาณ','กลุ่มบริหารงานบุคคล','กลุ่มบริหารทั่วไป')),
  active boolean not null default true, unique(school_id,name)
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade, display_name text not null,
  position text, active boolean not null default true, created_at timestamptz not null default now()
);
create table public.role_assignments (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  user_id uuid not null references auth.users(id) on delete cascade, role public.app_role not null,
  department_id uuid references public.departments(id), active boolean not null default true,
  created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  check ((role='department_head') = (department_id is not null)), unique(school_id,user_id,role,department_id)
);
create table public.fund_sources (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, category text not null, restriction_note text, active boolean not null default true,
  created_at timestamptz not null default now(), unique(school_id,name)
);
create table public.funding_envelopes (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  fiscal_year_id uuid not null references public.fiscal_years(id), fund_source_id uuid not null references public.fund_sources(id),
  amount numeric(14,2) not null check(amount >= 0), reference_no text, reference_date date,
  conditions text, object_key text, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  unique(fiscal_year_id,fund_source_id)
);
create or replace function public.validate_envelope_links()
returns trigger language plpgsql set search_path=public as $$
declare v_committed numeric(14,2);
begin
 if not exists(select 1 from public.fiscal_years y where y.id=new.fiscal_year_id and y.school_id=new.school_id) then raise exception 'ปีงบประมาณไม่ตรงกับโรงเรียนของกรอบวงเงิน'; end if;
 if not exists(select 1 from public.fund_sources f where f.id=new.fund_source_id and f.school_id=new.school_id) then raise exception 'แหล่งเงินไม่ตรงกับโรงเรียนของกรอบวงเงิน'; end if;
 select coalesce(sum(a.allocated_amount),0) into v_committed from public.project_funding_allocations a join public.projects p on p.id=a.project_id where p.fiscal_year_id=new.fiscal_year_id and a.fund_source_id=new.fund_source_id and (p.status='approved' or (p.status='in_review' and p.approval_stage>=3));
 if v_committed>new.amount then raise exception 'ลดกรอบวงเงินต่ำกว่ายอดที่อนุมัติและกันไว้ไม่ได้'; end if;
 return new;
end $$;
create trigger funding_envelopes_school_guard before insert or update on public.funding_envelopes for each row execute function public.validate_envelope_links();
create table public.reference_categories (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, is_official boolean not null default false, active boolean not null default true, unique(school_id,name)
);
create table public.reference_items (
  id uuid primary key default gen_random_uuid(), category_id uuid not null references public.reference_categories(id),
  label text not null, description text, source_title text, source_year text, source_url text,
  active boolean not null default true, version int not null default 1, created_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  fiscal_year_id uuid not null references public.fiscal_years(id), department_id uuid not null references public.departments(id),
  title text not null, project_type text not null default 'new' check(project_type in ('new','continuing')),
  rationale text, objectives text[] not null default '{}', quantitative_target text, qualitative_target text,
  target_group text, target_count integer check(target_count is null or target_count >= 0), expected_results text[] not null default '{}',
  plan_start date, plan_end date, document_date date not null default current_date,
  owner_id uuid not null references auth.users(id), status public.document_status not null default 'draft',
  approval_stage smallint not null default 0 check(approval_stage between 0 and 4),
  revision int not null default 1, financial_version int not null default 1,
  submitted_at timestamptz, approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check(plan_start is null or plan_end is null or plan_start <= plan_end)
);
create index projects_school_year_status_idx on public.projects(school_id,fiscal_year_id,status,updated_at desc);
create index projects_owner_idx on public.projects(owner_id,updated_at desc);
create table public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade, user_id uuid not null references auth.users(id),
  member_role text not null default 'member', primary key(project_id,user_id)
);
create table public.project_reference_links (
  project_id uuid not null references public.projects(id) on delete cascade, reference_item_id uuid not null references public.reference_items(id),
  primary key(project_id,reference_item_id)
);
create table public.project_revisions (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id), revision int not null,
  snapshot jsonb not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  unique(project_id,revision)
);
create table public.activities (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id) on delete cascade,
  title text not null, objectives text[] not null default '{}', target_group text, target_count integer check(target_count is null or target_count >= 0),
  start_date date, end_date date, location text, summary text, expected_results text,
  status text not null default 'planned' check(status in ('planned','in_progress','completed','cancelled')),
  sort_order int not null default 0, created_at timestamptz not null default now(), check(start_date is null or end_date is null or start_date <= end_date)
);
create index activities_project_idx on public.activities(project_id,sort_order);
create table public.budget_items (
  id uuid primary key default gen_random_uuid(), activity_id uuid not null references public.activities(id) on delete cascade,
  fund_source_id uuid not null references public.fund_sources(id), label text not null, category text not null,
  quantity numeric(12,3) not null check(quantity >= 0), count_as text not null default 'ครั้ง', unit_price numeric(14,2) not null check(unit_price >= 0),
  total_amount numeric(14,2) generated always as (round(quantity * unit_price,2)) stored,
  quarter smallint check(quarter between 1 and 4), created_at timestamptz not null default now()
);
create index budget_items_activity_idx on public.budget_items(activity_id);
create table public.project_assessment_items (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id) on delete cascade,
  label text not null, target text, method text, instrument text, criteria text, risk text, mitigation text, sort_order int not null default 0
);
create index project_assessment_project_idx on public.project_assessment_items(project_id,sort_order);
create table public.project_funding_allocations (
  project_id uuid not null references public.projects(id), fund_source_id uuid not null references public.fund_sources(id),
  allocated_amount numeric(14,2) not null check(allocated_amount >= 0), primary key(project_id,fund_source_id)
);
create table public.approval_actions (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
  revision int not null, stage smallint not null check(stage between 1 and 4), actor_id uuid not null references auth.users(id),
  decision text not null check(decision in ('approved','returned','rejected')), comment text, document_date date not null,
  signature_object_key text, created_at timestamptz not null default now(), unique(project_id,revision,stage)
);
create table public.funding_requests (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
  activity_id uuid references public.activities(id), fund_source_id uuid not null references public.fund_sources(id),
  amount numeric(14,2) not null check(amount > 0), purpose text not null, status public.document_status not null default 'draft',
  approval_stage smallint not null default 0 check(approval_stage between 0 and 4), document_date date not null default current_date,
  created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.funding_request_actions (
  id uuid primary key default gen_random_uuid(), funding_request_id uuid not null references public.funding_requests(id),
  stage smallint not null check(stage between 1 and 4), actor_id uuid not null references auth.users(id),
  decision text not null check(decision in ('approved','returned','rejected')), comment text not null,
  document_date date not null, signature_object_key text not null, created_at timestamptz not null default now(),
  unique(funding_request_id,stage)
);
create index funding_requests_project_status_idx on public.funding_requests(project_id,status,approval_stage);
create index funding_requests_activity_fund_status_idx on public.funding_requests(activity_id,fund_source_id,status);
create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
  activity_id uuid references public.activities(id), budget_item_id uuid references public.budget_items(id), funding_request_id uuid references public.funding_requests(id), fund_source_id uuid not null references public.fund_sources(id),
  entry_type public.ledger_entry_type not null, amount numeric(14,2) not null check(amount > 0), entry_date date not null,
  payee text, evidence_no text, reason text, reverses_entry_id uuid references public.ledger_entries(id), object_key text,
  idempotency_key uuid not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  unique(project_id,idempotency_key), check(entry_type <> 'reversal' or reverses_entry_id is not null)
);
create index ledger_project_fund_date_idx on public.ledger_entries(project_id,fund_source_id,entry_date);
create index ledger_request_type_idx on public.ledger_entries(funding_request_id,entry_type);
create table public.project_reports (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id), revision int not null default 1,
  document_date date not null, assignment_order_no text, assignment_order_date date, status public.document_status not null default 'draft',
  completion_status text not null default 'in_progress' check(completion_status in ('in_progress','completed')),
  summary text, problems text, suggestions text, financial_version int not null, submitted_at timestamptz,
  created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), unique(project_id,revision)
);
create table public.activity_reports (
  id uuid primary key default gen_random_uuid(), report_id uuid not null references public.project_reports(id) on delete cascade,
  activity_id uuid not null references public.activities(id), actual_summary text, outcome text, issues text, suggestions text,
  unique(report_id,activity_id)
);
create table public.cipp_items (
  id uuid primary key default gen_random_uuid(), report_id uuid not null references public.project_reports(id) on delete cascade,
  dimension text not null check(dimension in ('context','input','process','product')),
  prompt text not null, target_percent numeric(5,2) check(target_percent between 0 and 100), weight numeric(8,3) not null default 1 check(weight > 0), sort_order int not null default 0
);
create table public.cipp_responses (
  id uuid primary key default gen_random_uuid(), item_id uuid not null references public.cipp_items(id) on delete cascade,
  respondent_code text not null, score smallint not null check(score between 1 and 5), created_at timestamptz not null default now(), unique(item_id,respondent_code)
);
create table public.evidence_files (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
  activity_id uuid references public.activities(id), report_id uuid references public.project_reports(id),
  bucket_id text not null, object_key text not null, file_name text not null, mime_type text not null, byte_size bigint not null check(byte_size > 0),
  caption text, sort_order int not null default 0, include_in_appendix boolean not null default true, created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.request_idempotency (
  actor_id uuid not null references auth.users(id), request_key uuid not null, request_hash text not null,
  result jsonb, created_at timestamptz not null default now(), primary key(actor_id,request_key)
);
create table public.audit_events (
  id bigint generated always as identity primary key, school_id uuid not null references public.schools(id),
  actor_id uuid not null references auth.users(id), action text not null, entity_type text not null, entity_id uuid,
  before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);

create or replace function public.has_school_role(p_school uuid, p_roles public.app_role[])
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id and p.active where r.school_id=p_school and r.user_id=auth.uid() and r.active and r.role=any(p_roles))
$$;
create or replace function public.is_school_member(p_school uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id where r.school_id=p_school and r.user_id=auth.uid() and r.active and p.active)
$$;
create or replace function public.can_see_profile(p_user uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select p_user=auth.uid() or exists(
   select 1 from public.role_assignments target
   join public.profiles target_profile on target_profile.id=target.user_id and target_profile.active
   join public.role_assignments viewer on viewer.school_id=target.school_id and viewer.user_id=auth.uid() and viewer.active
   join public.profiles viewer_profile on viewer_profile.id=viewer.user_id and viewer_profile.active
   where target.user_id=p_user and target.active
 )
$$;
create or replace function public.can_read_project(p_project uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.projects p where p.id=p_project and (
   p.owner_id=auth.uid() or public.has_school_role(p.school_id,array['admin','budget_head','deputy_director','director']::public.app_role[])
   or exists(select 1 from public.project_members m where m.project_id=p.id and m.user_id=auth.uid())
   or exists(select 1 from public.role_assignments r where r.school_id=p.school_id and r.user_id=auth.uid() and r.active and r.role='department_head' and r.department_id=p.department_id)
 ))
$$;
create or replace function public.can_edit_project(p_project uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.projects p where p.id=p_project and p.owner_id=auth.uid() and p.status in ('draft','returned'))
$$;
revoke all on function public.has_school_role(uuid,public.app_role[]) from public;
revoke all on function public.is_school_member(uuid) from public;
revoke all on function public.can_see_profile(uuid) from public;
revoke all on function public.can_read_project(uuid) from public;
revoke all on function public.can_edit_project(uuid) from public;
grant execute on function public.has_school_role(uuid,public.app_role[]) to authenticated;
grant execute on function public.is_school_member(uuid) to authenticated;
grant execute on function public.can_see_profile(uuid) to authenticated;
grant execute on function public.can_read_project(uuid) to authenticated;
grant execute on function public.can_edit_project(uuid) to authenticated;

-- RLS: role assignment is never self-managed; bootstrap the first administrator via the SQL editor.
do $$ declare t text; begin
  foreach t in array array['schools','school_settings','fiscal_years','departments','profiles','role_assignments','fund_sources','funding_envelopes','reference_categories','reference_items','projects','project_members','project_reference_links','project_revisions','activities','budget_items','project_assessment_items','project_funding_allocations','approval_actions','funding_requests','funding_request_actions','ledger_entries','project_reports','activity_reports','cipp_items','cipp_responses','evidence_files','request_idempotency','audit_events'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
create policy schools_members_read on public.schools for select to authenticated using (public.is_school_member(id));
create or replace function public.guard_project_state()
returns trigger language plpgsql set search_path=public,auth as $$
begin
 if current_setting('app.project_workflow',true)='allowed' then return new; end if;
 if new.status is distinct from old.status or new.approval_stage is distinct from old.approval_stage
   or new.revision is distinct from old.revision or new.financial_version is distinct from old.financial_version
   or new.submitted_at is distinct from old.submitted_at or new.approved_at is distinct from old.approved_at then
   raise exception 'สถานะและเลขฉบับแก้ไขได้ผ่าน workflow เท่านั้น';
 end if;
 return new;
end $$;
create trigger projects_state_guard before update on public.projects for each row execute function public.guard_project_state();
create policy settings_read on public.school_settings for select to authenticated using (public.is_school_member(school_id));
create policy settings_admin_write on public.school_settings for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy fiscal_read on public.fiscal_years for select to authenticated using (public.is_school_member(school_id));
create policy fiscal_admin_write on public.fiscal_years for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy departments_read on public.departments for select to authenticated using (public.is_school_member(school_id));
create policy departments_admin_write on public.departments for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy profile_read_members on public.profiles for select to authenticated using (public.can_see_profile(id));
create policy profile_self_update on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy roles_admin_read on public.role_assignments for select to authenticated using (user_id=auth.uid() or public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy roles_admin_write on public.role_assignments for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy fund_source_read on public.fund_sources for select to authenticated using (public.is_school_member(school_id));
create policy fund_source_admin_write on public.fund_sources for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy envelope_read on public.funding_envelopes for select to authenticated using (public.has_school_role(school_id,array['admin','budget_head']::public.app_role[]));
create policy envelope_budget_write on public.funding_envelopes for all to authenticated using (public.has_school_role(school_id,array['admin','budget_head']::public.app_role[])) with check (public.has_school_role(school_id,array['admin','budget_head']::public.app_role[]));
create policy ref_category_read on public.reference_categories for select to authenticated using (public.is_school_member(school_id));
create policy ref_category_admin_write on public.reference_categories for all to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[])) with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy ref_item_read on public.reference_items for select to authenticated using (exists(select 1 from public.reference_categories c where c.id=category_id and public.is_school_member(c.school_id)));
create policy ref_item_admin_write on public.reference_items for all to authenticated using (exists(select 1 from public.reference_categories c where c.id=category_id and public.has_school_role(c.school_id,array['admin']::public.app_role[]))) with check (exists(select 1 from public.reference_categories c where c.id=category_id and public.has_school_role(c.school_id,array['admin']::public.app_role[])));
create policy projects_read on public.projects for select to authenticated using (public.can_read_project(id));
create policy projects_admin_read_all on public.projects for select to authenticated using (exists(select 1 from public.role_assignments r where r.school_id=projects.school_id and r.user_id=auth.uid() and r.active));
create policy members_read on public.project_members for select to authenticated using (public.can_read_project(project_id));
create policy project_refs_read on public.project_reference_links for select to authenticated using (public.can_read_project(project_id));
create policy revisions_read on public.project_revisions for select to authenticated using (public.can_read_project(project_id));
create policy activities_read on public.activities for select to authenticated using (public.can_read_project(project_id));
create policy budget_read on public.budget_items for select to authenticated using (exists(select 1 from public.activities a where a.id=activity_id and public.can_read_project(a.project_id)));
create policy assessment_read on public.project_assessment_items for select to authenticated using (public.can_read_project(project_id));
create policy allocation_read on public.project_funding_allocations for select to authenticated using (public.can_read_project(project_id));
create policy approvals_read on public.approval_actions for select to authenticated using (public.can_read_project(project_id));
create policy request_read on public.funding_requests for select to authenticated using (public.can_read_project(project_id));
create policy request_actions_read on public.funding_request_actions for select to authenticated using (exists(select 1 from public.funding_requests f where f.id=funding_request_id and public.can_read_project(f.project_id)));
create policy ledger_read on public.ledger_entries for select to authenticated using (public.can_read_project(project_id));
create policy reports_read on public.project_reports for select to authenticated using (public.can_read_project(project_id));
create policy reports_owner_edit on public.project_reports for all to authenticated using (created_by=auth.uid() and status in ('draft','returned') and public.can_read_project(project_id)) with check (created_by=auth.uid() and status in ('draft','returned') and public.can_read_project(project_id));
create policy activity_report_read on public.activity_reports for select to authenticated using (exists(select 1 from public.project_reports r where r.id=report_id and public.can_read_project(r.project_id)));
create policy activity_report_owner_edit on public.activity_reports for all to authenticated using (exists(select 1 from public.project_reports r where r.id=report_id and r.created_by=auth.uid() and r.status in ('draft','returned'))) with check (exists(select 1 from public.project_reports r where r.id=report_id and r.created_by=auth.uid() and r.status in ('draft','returned')));
create policy cipp_read on public.cipp_items for select to authenticated using (exists(select 1 from public.project_reports r where r.id=report_id and public.can_read_project(r.project_id)));
create policy cipp_owner_edit on public.cipp_items for all to authenticated using (exists(select 1 from public.project_reports r where r.id=report_id and r.created_by=auth.uid() and r.status in ('draft','returned'))) with check (exists(select 1 from public.project_reports r where r.id=report_id and r.created_by=auth.uid() and r.status in ('draft','returned')));
create policy responses_read on public.cipp_responses for select to authenticated using (exists(select 1 from public.cipp_items i join public.project_reports r on r.id=i.report_id where i.id=item_id and public.can_read_project(r.project_id)));
create policy responses_owner_edit on public.cipp_responses for all to authenticated using (exists(select 1 from public.cipp_items i join public.project_reports r on r.id=i.report_id where i.id=item_id and r.created_by=auth.uid() and r.status in ('draft','returned'))) with check (exists(select 1 from public.cipp_items i join public.project_reports r on r.id=i.report_id where i.id=item_id and r.created_by=auth.uid() and r.status in ('draft','returned')));
create policy evidence_read on public.evidence_files for select to authenticated using (public.can_read_project(project_id));
create policy evidence_owner_insert on public.evidence_files for insert to authenticated with check (created_by=auth.uid() and public.can_edit_project(project_id));
create policy idempotency_self on public.request_idempotency for all to authenticated using (actor_id=auth.uid()) with check (actor_id=auth.uid());
create policy audit_admin_read on public.audit_events for select to authenticated using (public.has_school_role(school_id,array['admin']::public.app_role[]));

create or replace function public.save_project_bundle(p_project jsonb,p_activities jsonb,p_budget_items jsonb,p_assessments jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_school uuid; v_year uuid; v_department uuid; v_owner uuid; v_status public.document_status; v_revision int; a jsonb; b jsonb; item jsonb; v_activity_ids uuid[] := '{}'; v_idx int; v_activity uuid;
begin
 v_owner:=auth.uid();
 if v_owner is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 v_school:=(p_project->>'school_id')::uuid; v_year:=(p_project->>'fiscal_year_id')::uuid; v_department:=(p_project->>'department_id')::uuid;
 if not public.is_school_member(v_school) then raise exception 'ไม่มีสิทธิ์ในโรงเรียนนี้'; end if;
 if not exists(select 1 from public.fiscal_years where id=v_year and school_id=v_school and is_open) then raise exception 'ปีงบประมาณไม่เปิดใช้งาน'; end if;
 if not exists(select 1 from public.departments where id=v_department and school_id=v_school and active) then raise exception 'กลุ่มบริหารไม่ถูกต้อง'; end if;
 if nullif(trim(p_project->>'title'),'') is null then raise exception 'กรุณาระบุชื่อโครงการ'; end if;
 if nullif(p_project->>'id','') is null then
   insert into public.projects(school_id,fiscal_year_id,department_id,title,project_type,rationale,objectives,quantitative_target,qualitative_target,target_group,target_count,expected_results,plan_start,plan_end,document_date,owner_id)
   values(v_school,v_year,v_department,p_project->>'title',coalesce(p_project->>'project_type','new'),p_project->>'rationale',coalesce(array(select jsonb_array_elements_text(coalesce(p_project->'objectives','[]'::jsonb))),'{}'),p_project->>'quantitative_target',p_project->>'qualitative_target',p_project->>'target_group',nullif(p_project->>'target_count','')::int,coalesce(array(select jsonb_array_elements_text(coalesce(p_project->'expected_results','[]'::jsonb))),'{}'),nullif(p_project->>'plan_start','')::date,nullif(p_project->>'plan_end','')::date,coalesce(nullif(p_project->>'document_date','')::date,current_date),v_owner)
   returning id,status,revision into v_id,v_status,v_revision;
 else
   v_id:=(p_project->>'id')::uuid;
   select status,revision into v_status,v_revision from public.projects where id=v_id and owner_id=v_owner and status in ('draft','returned') for update;
   if not found then raise exception 'แก้ไขได้เฉพาะร่างของผู้ใช้'; end if;
   if v_status='returned' then v_revision:=v_revision+1; end if;
   perform set_config('app.project_workflow','allowed',true);
   update public.projects set fiscal_year_id=v_year,department_id=v_department,title=p_project->>'title',project_type=coalesce(p_project->>'project_type','new'),rationale=p_project->>'rationale',
     objectives=coalesce(array(select jsonb_array_elements_text(coalesce(p_project->'objectives','[]'::jsonb))),'{}'),quantitative_target=p_project->>'quantitative_target',qualitative_target=p_project->>'qualitative_target',target_group=p_project->>'target_group',target_count=nullif(p_project->>'target_count','')::int,
     expected_results=coalesce(array(select jsonb_array_elements_text(coalesce(p_project->'expected_results','[]'::jsonb))),'{}'),plan_start=nullif(p_project->>'plan_start','')::date,plan_end=nullif(p_project->>'plan_end','')::date,document_date=coalesce(nullif(p_project->>'document_date','')::date,current_date),revision=v_revision,status='draft',approval_stage=0,updated_at=now()
     where id=v_id;
   delete from public.activities where project_id=v_id;
 end if;
 for a in select value from jsonb_array_elements(coalesce(p_activities,'[]'::jsonb)) loop
   insert into public.activities(project_id,title,objectives,target_group,target_count,start_date,end_date,location,summary,expected_results,sort_order)
   values(v_id,a->>'title',coalesce(array(select jsonb_array_elements_text(coalesce(a->'objectives','[]'::jsonb))),'{}'),a->>'target_group',nullif(a->>'target_count','')::int,nullif(a->>'start_date','')::date,nullif(a->>'end_date','')::date,a->>'location',a->>'summary',a->>'expected_results',coalesce(nullif(a->>'sort_order','')::int,0)) returning id into v_activity;
   v_activity_ids:=array_append(v_activity_ids,v_activity);
 end loop;
 for b in select value from jsonb_array_elements(coalesce(p_budget_items,'[]'::jsonb)) loop
   v_idx:=coalesce(nullif(b->>'activity_index','')::int,0)+1;
   if v_idx < 1 or v_idx > coalesce(array_length(v_activity_ids,1),0) then raise exception 'รายการงบประมาณอ้างกิจกรรมไม่ถูกต้อง'; end if;
   if not exists(select 1 from public.fund_sources where id=(b->>'fund_source_id')::uuid and school_id=v_school and active) then raise exception 'แหล่งเงินไม่อยู่ในโรงเรียนนี้หรือปิดใช้งาน'; end if;
   v_activity:=v_activity_ids[v_idx];
   insert into public.budget_items(activity_id,fund_source_id,label,category,quantity,count_as,unit_price,quarter)
   values(v_activity,(b->>'fund_source_id')::uuid,b->>'label',coalesce(b->>'category','อื่น ๆ'),(b->>'quantity')::numeric,coalesce(b->>'count_as','ครั้ง'),(b->>'unit_price')::numeric,nullif(b->>'quarter','')::smallint);
 end loop;
 delete from public.project_funding_allocations where project_id=v_id;
 delete from public.project_assessment_items where project_id=v_id;
 for item in select value from jsonb_array_elements(coalesce(p_assessments,'[]'::jsonb)) loop
   insert into public.project_assessment_items(project_id,label,target,method,instrument,criteria,risk,mitigation,sort_order)
   values(v_id,item->>'label',item->>'target',item->>'method',item->>'instrument',item->>'criteria',item->>'risk',item->>'mitigation',coalesce(nullif(item->>'sort_order','')::int,0));
 end loop;
 insert into public.project_funding_allocations(project_id,fund_source_id,allocated_amount)
 select v_id,b.fund_source_id,sum(b.total_amount) from public.budget_items b join public.activities a on a.id=b.activity_id where a.project_id=v_id group by b.fund_source_id;
 insert into public.audit_events(school_id,actor_id,action,entity_type,entity_id,after_data)
 values(v_school,v_owner,'save_bundle','project',v_id,jsonb_build_object('revision',v_revision));
 return v_id;
end $$;
revoke all on function public.save_project_bundle(jsonb,jsonb,jsonb,jsonb) from public;
grant execute on function public.save_project_bundle(jsonb,jsonb,jsonb,jsonb) to authenticated;

-- The workflow is performed through RPCs, not direct client status edits.
create or replace function public.submit_project(p_project uuid)
returns public.projects language plpgsql security definer set search_path=public,auth as $$
declare v public.projects; v_activity_count int; v_budget_count int;
begin
 select * into v from public.projects where id=p_project for update;
 if not found or v.owner_id<>auth.uid() or v.status not in ('draft','returned') then raise exception 'โครงการนี้ยังส่งพิจารณาไม่ได้'; end if;
 if not public.is_school_member(v.school_id) then raise exception 'บัญชีนี้ถูกปิดใช้งานหรือไม่มีสิทธิ์ในโรงเรียน'; end if;
 select count(*) into v_activity_count from public.activities where project_id=p_project;
 select count(*) into v_budget_count from public.budget_items b join public.activities a on a.id=b.activity_id where a.project_id=p_project;
 if trim(v.title)='' or v_activity_count=0 or v_budget_count=0 then raise exception 'กรุณาระบุชื่อโครงการ กิจกรรม และรายการงบประมาณก่อนส่ง'; end if;
 if nullif(trim(v.rationale),'') is null or coalesce(cardinality(v.objectives),0)=0 or nullif(trim(v.quantitative_target),'') is null or nullif(trim(v.qualitative_target),'') is null or nullif(trim(v.target_group),'') is null or v.target_count is null or coalesce(cardinality(v.expected_results),0)=0 then raise exception 'กรุณากรอกหลักการและเหตุผล วัตถุประสงค์ เป้าหมาย และผลที่คาดว่าจะได้รับ'; end if;
 if v.plan_start is null or v.plan_end is null then raise exception 'กรุณาระบุช่วงเวลาดำเนินโครงการ'; end if;
 if not exists(select 1 from public.project_assessment_items where project_id=v.id) then raise exception 'กรุณาเพิ่มแผนประเมินอย่างน้อย 1 ตัวชี้วัด'; end if;
 if not exists(select 1 from public.fiscal_years y where y.id=v.fiscal_year_id and y.is_open) then raise exception 'ปีงบประมาณนี้ปิดแล้ว'; end if;
 insert into public.project_revisions(project_id,revision,snapshot,created_by)
 values(v.id,v.revision,to_jsonb(v)||jsonb_build_object(
   'activities',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.activities a where a.project_id=v.id),
   'budget_items',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.budget_items b join public.activities a on a.id=b.activity_id where a.project_id=v.id),
   'assessment_items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.project_assessment_items i where i.project_id=v.id)
 ),auth.uid())
 on conflict(project_id,revision) do nothing;
 perform set_config('app.project_workflow','allowed',true);
 update public.projects set status='submitted',approval_stage=1,submitted_at=now(),updated_at=now() where id=v.id returning * into v;
 return v;
end $$;
revoke all on function public.submit_project(uuid) from public;
grant execute on function public.submit_project(uuid) to authenticated;

create or replace function public.decide_project(p_project uuid,p_decision text,p_comment text,p_document_date date,p_signature_key text default null)
returns public.projects language plpgsql security definer set search_path=public,auth as $$
declare v public.projects; v_role public.app_role; v_dept uuid; v_required_role public.app_role; v_next smallint; v_allocation record; v_envelope numeric(14,2); v_reserved numeric(14,2);
begin
 if p_decision not in ('approved','returned','rejected') then raise exception 'ผลการพิจารณาไม่ถูกต้อง'; end if;
 if p_signature_key is not null and left(p_signature_key,length(auth.uid()::text)+1)<>auth.uid()::text||'/' then raise exception 'ลายเซ็นต้องเป็นไฟล์ของผู้พิจารณา'; end if;
 select * into v from public.projects where id=p_project for update;
 if not found or v.status not in ('submitted','in_review') then raise exception 'รายการนี้ไม่อยู่ในขั้นพิจารณา'; end if;
 if not public.is_school_member(v.school_id) then raise exception 'บัญชีนี้ถูกปิดใช้งานหรือไม่มีสิทธิ์ในโรงเรียน'; end if;
 if v.owner_id=auth.uid() then raise exception 'ผู้รับผิดชอบโครงการไม่สามารถพิจารณาโครงการของตนเอง'; end if;
 if p_document_date>current_date then raise exception 'วันที่พิจารณาต้องไม่เป็นวันในอนาคต'; end if;
 if p_decision in ('returned','rejected') and nullif(trim(p_comment),'') is null then raise exception 'กรุณาระบุความเห็นหรือเหตุผล'; end if;
 select r.role,r.department_id into v_role,v_dept from public.role_assignments r where r.user_id=auth.uid() and r.school_id=v.school_id and r.active and (
   (v.approval_stage=1 and r.role='department_head' and r.department_id=v.department_id) or
   (v.approval_stage=2 and r.role='budget_head') or (v.approval_stage=3 and r.role='deputy_director') or (v.approval_stage=4 and r.role='director')) limit 1;
 if v_role is null then raise exception 'ไม่มีสิทธิ์พิจารณาในขั้นนี้'; end if;
 if exists(select 1 from public.approval_actions where project_id=v.id and revision=v.revision and stage=v.approval_stage) then raise exception 'มีผลพิจารณาขั้นนี้แล้ว'; end if;
 if p_decision='approved' and v.approval_stage=2 then
   for v_allocation in select fund_source_id,allocated_amount from public.project_funding_allocations where project_id=v.id order by fund_source_id loop
     select amount into v_envelope from public.funding_envelopes where fiscal_year_id=v.fiscal_year_id and fund_source_id=v_allocation.fund_source_id for update;
     if not found then raise exception 'แหล่งเงินยังไม่มีกรอบวงเงิน'; end if;
     select coalesce(sum(a.allocated_amount),0) into v_reserved
       from public.project_funding_allocations a join public.projects p on p.id=a.project_id
       where p.fiscal_year_id=v.fiscal_year_id and a.fund_source_id=v_allocation.fund_source_id and p.id<>v.id
         and (p.status='approved' or (p.status='in_review' and p.approval_stage>=3));
     if v_reserved+v_allocation.allocated_amount>v_envelope then raise exception 'กรอบวงเงินแหล่งนี้ไม่เพียงพอ'; end if;
   end loop;
 end if;
 insert into public.approval_actions(project_id,revision,stage,actor_id,decision,comment,document_date,signature_object_key)
 values(v.id,v.revision,v.approval_stage,auth.uid(),p_decision,p_comment,p_document_date,p_signature_key);
 perform set_config('app.project_workflow','allowed',true);
 if p_decision='returned' then update public.projects set status='returned',updated_at=now() where id=v.id returning * into v;
 elsif p_decision='rejected' then update public.projects set status='rejected',updated_at=now() where id=v.id returning * into v;
 elsif v.approval_stage=4 then update public.projects set status='approved',approved_at=now(),approval_stage=4,updated_at=now() where id=v.id returning * into v;
 else v_next:=v.approval_stage+1; update public.projects set status='in_review',approval_stage=v_next,updated_at=now() where id=v.id returning * into v;
 end if;
 return v;
end $$;
revoke all on function public.decide_project(uuid,text,text,date,text) from public;
grant execute on function public.decide_project(uuid,text,text,date,text) to authenticated;

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant insert,update on public.profiles to authenticated;
grant insert,update,delete on public.role_assignments to authenticated;
grant insert,update,delete on public.school_settings,public.fiscal_years,public.departments,public.fund_sources,public.reference_categories,public.reference_items,public.funding_envelopes to authenticated;
grant insert,update,delete on public.project_reports,public.activity_reports,public.cipp_items,public.cipp_responses,public.evidence_files,public.request_idempotency to authenticated;

create or replace view public.project_budget_summary with (security_invoker=true) as
select p.id project_id, b.fund_source_id, sum(b.total_amount) planned_amount
from public.projects p join public.activities a on a.project_id=p.id join public.budget_items b on b.activity_id=a.id
group by p.id,b.fund_source_id;
grant select on public.project_budget_summary to authenticated;

-- Private project evidence and signature objects; public reads are limited to school branding.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('project-files','project-files',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf']),
       ('user-signatures','user-signatures',false,1048576,array['image/png','image/webp']),
       ('school-branding','school-branding',true,2097152,array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict(id) do nothing;
create policy project_files_read on storage.objects for select to authenticated
using (bucket_id='project-files' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and public.can_read_project(((storage.foldername(name))[1])::uuid));
create policy project_files_write on storage.objects for insert to authenticated
with check (bucket_id='project-files' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and public.can_edit_project(((storage.foldername(name))[1])::uuid));
create policy project_files_remove_draft on storage.objects for delete to authenticated
using (bucket_id='project-files' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and public.can_edit_project(((storage.foldername(name))[1])::uuid));
create policy signatures_owner_insert on storage.objects for insert to authenticated
with check (bucket_id='user-signatures' and (storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$' and public.can_read_project(((storage.foldername(name))[2])::uuid));
create policy signatures_owner_read on storage.objects for select to authenticated
using (bucket_id='user-signatures' and (
  (storage.foldername(name))[1]=auth.uid()::text or
  ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$' and public.can_read_project(((storage.foldername(name))[2])::uuid))
));
create policy branding_public_read on storage.objects for select using (bucket_id='school-branding');
create policy branding_admin_write on storage.objects for all to authenticated
using (bucket_id='school-branding' and public.has_school_role('b0000000-0000-4000-8000-000000000001',array['admin']::public.app_role[]))
with check (bucket_id='school-branding' and public.has_school_role('b0000000-0000-4000-8000-000000000001',array['admin']::public.app_role[]));

-- Idempotent reference setup. These are structure labels only; no funding amounts are assumed.
insert into public.departments(school_id,name) values
 ('b0000000-0000-4000-8000-000000000001','กลุ่มบริหารวิชาการ'),
 ('b0000000-0000-4000-8000-000000000001','กลุ่มบริหารงบประมาณ'),
 ('b0000000-0000-4000-8000-000000000001','กลุ่มบริหารงานบุคคล'),
 ('b0000000-0000-4000-8000-000000000001','กลุ่มบริหารทั่วไป') on conflict do nothing;
insert into public.fund_sources(school_id,name,category,restriction_note) values
 ('b0000000-0000-4000-8000-000000000001','เงินเดือน/ค่าจ้างบุคลากร','เงินงบประมาณ','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าสาธารณูปโภค','เงินงบประมาณ','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าจัดการเรียนการสอน','เงินอุดหนุนการศึกษาขั้นพื้นฐาน','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าหนังสือเรียน','เงินอุดหนุนการศึกษาขั้นพื้นฐาน','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าเครื่องแบบนักเรียน','เงินอุดหนุนการศึกษาขั้นพื้นฐาน','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าอุปกรณ์การเรียน','เงินอุดหนุนการศึกษาขั้นพื้นฐาน','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','ค่าจัดกิจกรรมพัฒนาผู้เรียน','เงินอุดหนุนการศึกษาขั้นพื้นฐาน','ตั้งค่าเงื่อนไขตามเอกสารที่โรงเรียนได้รับ'),
 ('b0000000-0000-4000-8000-000000000001','เงินรายได้สถานศึกษา','เงินนอกงบประมาณ','ใช้ตามเอกสารและข้อจำกัดของเงิน'),
 ('b0000000-0000-4000-8000-000000000001','เงินโครงการอาหารกลางวัน','เงินนอกงบประมาณ','ใช้ตามเอกสารและข้อจำกัดของเงิน'),
 ('b0000000-0000-4000-8000-000000000001','เงินบริจาคที่มีวัตถุประสงค์','เงินนอกงบประมาณ','ใช้ตามวัตถุประสงค์และหลักฐาน'),
 ('b0000000-0000-4000-8000-000000000001','เงินลูกเสือเนตรนารี','เงินนอกงบประมาณ','ใช้ตามเอกสารและข้อจำกัดของเงิน') on conflict(school_id,name) do nothing;

create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
 insert into public.profiles(id,display_name) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),new.email,'ผู้ใช้')) on conflict(id) do nothing;
 return new;
end $$;
create trigger auth_user_profile after insert on auth.users for each row execute function public.create_profile_for_auth_user();

-- Restrict direct anonymous access; authenticated reads remain subject to every table's RLS.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke insert,update on public.profiles from authenticated;
grant update(display_name,position) on public.profiles to authenticated;
revoke all on function public.create_profile_for_auth_user() from public;
revoke all on function public.guard_project_state() from public;

create or replace function public.create_funding_request(p_project uuid,p_activity uuid,p_fund uuid,p_amount numeric,p_purpose text,p_document_date date)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_project public.projects; v_start date; v_end date; v_planned numeric(14,2); v_id uuid;
begin
 if auth.uid() is null or p_amount<=0 or nullif(trim(p_purpose),'') is null then raise exception 'กรุณาระบุจำนวนเงินและวัตถุประสงค์'; end if;
 select * into v_project from public.projects where id=p_project and owner_id=auth.uid() and status='approved' for update;
 if not found or not public.is_school_member(v_project.school_id) then raise exception 'สร้างคำขอได้เฉพาะโครงการที่อนุมัติและเป็นผู้รับผิดชอบ'; end if;
 select start_date,end_date into v_start,v_end from public.fiscal_years where id=v_project.fiscal_year_id and is_open;
 if not found or p_document_date<v_start or p_document_date>v_end or p_document_date>current_date then raise exception 'วันที่เอกสารอยู่นอกช่วงปีงบประมาณหรือเป็นวันในอนาคต'; end if;
 if not exists(select 1 from public.activities where id=p_activity and project_id=p_project) then raise exception 'กิจกรรมไม่อยู่ในโครงการนี้'; end if;
 select coalesce(sum(total_amount),0) into v_planned from public.budget_items where activity_id=p_activity and fund_source_id=p_fund;
 if v_planned=0 or p_amount>v_planned then raise exception 'จำนวนเงินเกินประมาณการของกิจกรรมและแหล่งเงิน'; end if;
 insert into public.funding_requests(project_id,activity_id,fund_source_id,amount,purpose,document_date,created_by)
 values(p_project,p_activity,p_fund,p_amount,trim(p_purpose),p_document_date,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.create_funding_request(uuid,uuid,uuid,numeric,text,date) from public;
grant execute on function public.create_funding_request(uuid,uuid,uuid,numeric,text,date) to authenticated;

create or replace function public.submit_funding_request(p_request uuid)
returns public.funding_requests language plpgsql security definer set search_path=public,auth as $$
declare v public.funding_requests; v_project public.projects;
begin
 select * into v from public.funding_requests where id=p_request for update;
 if not found or v.created_by<>auth.uid() or v.status not in ('draft','returned') then raise exception 'คำขอนี้ยังส่งพิจารณาไม่ได้'; end if;
 select * into v_project from public.projects where id=v.project_id;
 if v_project.status<>'approved' or not public.is_school_member(v_project.school_id) then raise exception 'โครงการยังไม่พร้อมขอใช้วงเงิน'; end if;
 update public.funding_requests set status='submitted',approval_stage=1 where id=v.id returning * into v;
 return v;
end $$;
revoke all on function public.submit_funding_request(uuid) from public;
grant execute on function public.submit_funding_request(uuid) to authenticated;

create or replace function public.decide_funding_request(p_request uuid,p_decision text,p_comment text,p_document_date date,p_signature_key text)
returns public.funding_requests language plpgsql security definer set search_path=public,auth as $$
declare v public.funding_requests; v_project public.projects; v_role public.app_role; v_dept uuid; v_next smallint; v_project_alloc numeric(14,2); v_project_reserved numeric(14,2); v_activity_cap numeric(14,2); v_activity_reserved numeric(14,2);
begin
 if p_decision not in ('approved','returned','rejected') then raise exception 'ผลการพิจารณาไม่ถูกต้อง'; end if;
 select * into v from public.funding_requests where id=p_request for update;
 if not found or v.status not in ('submitted','in_review') then raise exception 'คำขอนี้ไม่อยู่ในขั้นพิจารณา'; end if;
 select * into v_project from public.projects where id=v.project_id;
 if not public.is_school_member(v_project.school_id) or v.created_by=auth.uid() then raise exception 'บัญชีนี้ไม่มีสิทธิ์พิจารณาคำขอนี้'; end if;
 if p_document_date>current_date or nullif(trim(p_comment),'') is null then raise exception 'ระบุวันที่และความเห็นให้ครบ'; end if;
 if p_signature_key is null or split_part(p_signature_key,'/',1)<>auth.uid()::text or split_part(p_signature_key,'/',2)<>v.project_id::text then raise exception 'ลายเซ็นต้องเป็นไฟล์ของผู้พิจารณาสำหรับโครงการนี้'; end if;
 select r.role into v_role from public.role_assignments r where r.school_id=v_project.school_id and r.user_id=auth.uid() and r.active and
 ((v.approval_stage=1 and r.role='department_head' and r.department_id=v_project.department_id) or
 (v.approval_stage=2 and r.role='budget_head') or (v.approval_stage=3 and r.role='deputy_director') or (v.approval_stage=4 and r.role='director')) limit 1;
 if v_role is null then raise exception 'ไม่มีสิทธิ์พิจารณาในขั้นนี้'; end if;
 if exists(select 1 from public.funding_request_actions where funding_request_id=v.id and stage=v.approval_stage) then raise exception 'มีผลพิจารณาขั้นนี้แล้ว'; end if;
 if p_decision='approved' and v.approval_stage=4 then
   select allocated_amount into v_project_alloc from public.project_funding_allocations where project_id=v.project_id and fund_source_id=v.fund_source_id for update;
   if not found then raise exception 'โครงการไม่มีกรอบจัดสรรจากแหล่งเงินนี้'; end if;
   select coalesce(sum(amount),0) into v_project_reserved from public.funding_requests where project_id=v.project_id and fund_source_id=v.fund_source_id and status='approved' and id<>v.id;
   if v_project_reserved+v.amount>v_project_alloc then raise exception 'คำขอรวมเกินวงเงินจัดสรรของโครงการ'; end if;
   select coalesce(sum(total_amount),0) into v_activity_cap from public.budget_items where activity_id=v.activity_id and fund_source_id=v.fund_source_id;
   select coalesce(sum(amount),0) into v_activity_reserved from public.funding_requests where activity_id=v.activity_id and fund_source_id=v.fund_source_id and status='approved' and id<>v.id;
   if v_activity_reserved+v.amount>v_activity_cap then raise exception 'คำขอรวมเกินประมาณการของกิจกรรม'; end if;
 end if;
 insert into public.funding_request_actions(funding_request_id,stage,actor_id,decision,comment,document_date,signature_object_key)
 values(v.id,v.approval_stage,auth.uid(),p_decision,trim(p_comment),p_document_date,p_signature_key);
 if p_decision='returned' then update public.funding_requests set status='returned' where id=v.id returning * into v;
 elsif p_decision='rejected' then update public.funding_requests set status='rejected' where id=v.id returning * into v;
 elsif v.approval_stage=4 then update public.funding_requests set status='approved' where id=v.id returning * into v;
 else v_next:=v.approval_stage+1; update public.funding_requests set status='in_review',approval_stage=v_next where id=v.id returning * into v;
 end if;
 return v;
end $$;
revoke all on function public.decide_funding_request(uuid,text,text,date,text) from public;
grant execute on function public.decide_funding_request(uuid,text,text,date,text) to authenticated;

create or replace function public.record_payment(p_request uuid,p_amount numeric,p_entry_date date,p_payee text,p_evidence_no text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.funding_requests; v_project public.projects; v_year public.fiscal_years; v_used numeric(14,2); v_id uuid; v_existing public.ledger_entries;
begin
 if p_idempotency_key is null then raise exception 'ต้องมีรหัสคำขอสำหรับป้องกันการบันทึกซ้ำ'; end if;
 select * into v from public.funding_requests where id=p_request for update;
 if not found or v.status<>'approved' then raise exception 'จ่ายได้เฉพาะคำขอที่อนุมัติแล้ว'; end if;
 select * into v_project from public.projects where id=v.project_id;
 if not public.has_school_role(v_project.school_id,array['admin','budget_head']::public.app_role[]) then raise exception 'ไม่มีสิทธิ์บันทึกการจ่าย'; end if;
 select * into v_year from public.fiscal_years where id=v_project.fiscal_year_id;
 if p_amount<=0 or not v_year.is_open or p_entry_date<v_year.start_date or p_entry_date>v_year.end_date or p_entry_date>current_date then raise exception 'จำนวนเงิน วันที่ หรือสถานะปีงบประมาณไม่ถูกต้อง'; end if;
 select * into v_existing from public.ledger_entries where project_id=v.project_id and idempotency_key=p_idempotency_key;
 if found then
   if v_existing.funding_request_id<>v.id or v_existing.amount<>p_amount or v_existing.entry_type<>'payment' or v_existing.entry_date<>p_entry_date or coalesce(v_existing.payee,'')<>coalesce(nullif(trim(p_payee),''),'') or coalesce(v_existing.evidence_no,'')<>coalesce(nullif(trim(p_evidence_no),''),'') then raise exception 'idempotency key นี้ถูกใช้กับข้อมูลคนละรายการ'; end if;
   return v_existing.id;
 end if;
 select coalesce(sum(case when entry_type='payment' then amount when entry_type in ('refund','reversal') then -amount else 0 end),0) into v_used from public.ledger_entries where funding_request_id=v.id;
 if v_used+p_amount>v.amount then raise exception 'จ่ายเกินวงเงินที่อนุมัติ หรือมีการจ่ายไปแล้ว'; end if;
 insert into public.ledger_entries(project_id,activity_id,funding_request_id,fund_source_id,entry_type,amount,entry_date,payee,evidence_no,idempotency_key,created_by)
 values(v.project_id,v.activity_id,v.id,v.fund_source_id,'payment',p_amount,p_entry_date,nullif(trim(p_payee),''),nullif(trim(p_evidence_no),''),p_idempotency_key,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.record_payment(uuid,numeric,date,text,text,uuid) from public;
grant execute on function public.record_payment(uuid,numeric,date,text,text,uuid) to authenticated;

create or replace function public.refund_payment(p_payment uuid,p_amount numeric,p_entry_date date,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare original public.ledger_entries; v public.funding_requests; v_project public.projects; v_refunded numeric(14,2); v_id uuid; v_existing public.ledger_entries;
begin
 if p_idempotency_key is null then raise exception 'ต้องมีรหัสคำขอสำหรับป้องกันการบันทึกซ้ำ'; end if;
 select * into original from public.ledger_entries where id=p_payment and entry_type='payment';
 if not found or original.funding_request_id is null then raise exception 'ไม่พบรายการจ่ายต้นฉบับ'; end if;
 select * into v from public.funding_requests where id=original.funding_request_id for update;
 select * into v_project from public.projects where id=v.project_id;
 if not public.has_school_role(v_project.school_id,array['admin','budget_head']::public.app_role[]) then raise exception 'ไม่มีสิทธิ์บันทึกรับคืน'; end if;
 if p_amount<=0 or p_entry_date>current_date or p_entry_date<(select start_date from public.fiscal_years where id=v_project.fiscal_year_id) or p_entry_date>(select end_date from public.fiscal_years where id=v_project.fiscal_year_id) or nullif(trim(p_reason),'') is null then raise exception 'ระบุจำนวน วันที่ในปีงบประมาณ และเหตุผลให้ถูกต้อง'; end if;
 if exists(select 1 from public.ledger_entries e where e.project_id=v.project_id and e.idempotency_key=p_idempotency_key) then
   select * into v_existing from public.ledger_entries where project_id=v.project_id and idempotency_key=p_idempotency_key;
   if v_existing.entry_type='refund' and v_existing.reverses_entry_id=original.id and v_existing.amount=p_amount and v_existing.entry_date=p_entry_date and v_existing.reason=trim(p_reason) then return v_existing.id; end if;
   raise exception 'idempotency key นี้ถูกใช้กับข้อมูลคนละรายการ';
 end if;
 select coalesce(sum(amount),0) into v_refunded from public.ledger_entries where reverses_entry_id=original.id and entry_type='refund';
 if v_refunded+p_amount>original.amount then raise exception 'ยอดรับคืนเกินรายการจ่ายต้นฉบับ'; end if;
 insert into public.ledger_entries(project_id,activity_id,funding_request_id,fund_source_id,entry_type,amount,entry_date,reason,reverses_entry_id,idempotency_key,created_by)
 values(v.project_id,v.activity_id,v.id,v.fund_source_id,'refund',p_amount,p_entry_date,trim(p_reason),original.id,p_idempotency_key,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.refund_payment(uuid,numeric,date,text,uuid) from public;
grant execute on function public.refund_payment(uuid,numeric,date,text,uuid) to authenticated;

create or replace function public.reverse_payment(p_payment uuid,p_entry_date date,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare original public.ledger_entries; v public.funding_requests; v_project public.projects; v_id uuid; v_existing public.ledger_entries;
begin
 if p_idempotency_key is null then raise exception 'ต้องมีรหัสคำขอสำหรับป้องกันการบันทึกซ้ำ'; end if;
 select * into original from public.ledger_entries where id=p_payment and entry_type='payment';
 if not found or original.funding_request_id is null then raise exception 'ไม่พบรายการจ่ายต้นฉบับ'; end if;
 select * into v from public.funding_requests where id=original.funding_request_id for update;
 select * into v_project from public.projects where id=v.project_id;
 if not public.has_school_role(v_project.school_id,array['admin','budget_head']::public.app_role[]) then raise exception 'ไม่มีสิทธิ์กลับรายการ'; end if;
 if p_entry_date>current_date or p_entry_date<(select start_date from public.fiscal_years where id=v_project.fiscal_year_id) or p_entry_date>(select end_date from public.fiscal_years where id=v_project.fiscal_year_id) or nullif(trim(p_reason),'') is null then raise exception 'ระบุวันที่ในปีงบประมาณและเหตุผลให้ถูกต้อง'; end if;
 select * into v_existing from public.ledger_entries where project_id=v.project_id and idempotency_key=p_idempotency_key;
 if found then
   if v_existing.entry_type='reversal' and v_existing.reverses_entry_id=original.id and v_existing.entry_date=p_entry_date and v_existing.reason=trim(p_reason) then return v_existing.id; end if;
   raise exception 'idempotency key นี้ถูกใช้กับข้อมูลคนละรายการ';
 end if;
 if exists(select 1 from public.ledger_entries where reverses_entry_id=original.id) then raise exception 'รายการนี้มีการรับคืนหรือกลับรายการแล้ว'; end if;
 insert into public.ledger_entries(project_id,activity_id,funding_request_id,fund_source_id,entry_type,amount,entry_date,reason,reverses_entry_id,idempotency_key,created_by)
 values(v.project_id,v.activity_id,v.id,v.fund_source_id,'reversal',original.amount,p_entry_date,trim(p_reason),original.id,p_idempotency_key,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.reverse_payment(uuid,date,text,uuid) from public;
grant execute on function public.reverse_payment(uuid,date,text,uuid) to authenticated;

create or replace view public.project_fund_ledger_summary with (security_invoker=true) as
with ledger as (
  select project_id,fund_source_id,
    sum(case when entry_type='payment' then amount when entry_type in ('refund','reversal') then -amount else 0 end) as used_net
  from public.ledger_entries group by project_id,fund_source_id
), request_net as (
  select r.id,r.project_id,r.fund_source_id,r.amount,
    coalesce(sum(case when l.entry_type='payment' then l.amount when l.entry_type in ('refund','reversal') then -l.amount else 0 end),0) as paid_net
  from public.funding_requests r left join public.ledger_entries l on l.funding_request_id=r.id
  where r.status='approved' group by r.id,r.project_id,r.fund_source_id,r.amount
), reserved as (
  select project_id,fund_source_id,sum(greatest(amount-paid_net,0)) as reserved_amount
  from request_net group by project_id,fund_source_id
)
select a.project_id,a.fund_source_id,a.allocated_amount,
  coalesce(l.used_net,0)::numeric(14,2) as used_net,
  coalesce(r.reserved_amount,0)::numeric(14,2) as reserved_amount,
  (a.allocated_amount-coalesce(l.used_net,0)-coalesce(r.reserved_amount,0))::numeric(14,2) as available_amount
from public.project_funding_allocations a
join public.projects p on p.id=a.project_id and (p.status='approved' or (p.status='in_review' and p.approval_stage>=3))
left join ledger l using(project_id,fund_source_id)
left join reserved r using(project_id,fund_source_id);
grant select on public.project_fund_ledger_summary to authenticated;


create or replace view public.funding_envelope_summary with (security_invoker=true) as
select e.id,e.school_id,e.fiscal_year_id,e.fund_source_id,e.amount,
  coalesce(sum(a.allocated_amount) filter(where p.status='approved' or (p.status='in_review' and p.approval_stage>=3)),0)::numeric(14,2) as allocated_to_projects,
  (e.amount-coalesce(sum(a.allocated_amount) filter(where p.status='approved' or (p.status='in_review' and p.approval_stage>=3)),0))::numeric(14,2) as unallocated_to_projects
from public.funding_envelopes e
left join public.project_funding_allocations a on a.fund_source_id=e.fund_source_id
left join public.projects p on p.id=a.project_id and p.fiscal_year_id=e.fiscal_year_id
group by e.id,e.school_id,e.fiscal_year_id,e.fund_source_id,e.amount;
grant select on public.funding_envelope_summary to authenticated;
