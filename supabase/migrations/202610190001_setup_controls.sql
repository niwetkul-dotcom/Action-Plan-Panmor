-- Setup mutations use server-checked RPCs so school identity and reopen history
-- are not split across unprotected client requests.

drop policy if exists settings_admin_write on public.school_settings;
drop policy if exists fiscal_admin_write on public.fiscal_years;

drop policy if exists ref_category_admin_write on public.reference_categories;
create policy ref_category_admin_insert on public.reference_categories for insert to authenticated
with check (public.has_school_role(school_id,array['admin']::public.app_role[]));
create policy ref_category_admin_update on public.reference_categories for update to authenticated
using (public.has_school_role(school_id,array['admin']::public.app_role[]))
with check (public.has_school_role(school_id,array['admin']::public.app_role[]));

drop policy if exists ref_item_admin_write on public.reference_items;
create policy ref_item_admin_insert on public.reference_items for insert to authenticated
with check (exists(select 1 from public.reference_categories c where c.id=category_id and public.has_school_role(c.school_id,array['admin']::public.app_role[])));
create policy ref_item_admin_update on public.reference_items for update to authenticated
using (exists(select 1 from public.reference_categories c where c.id=category_id and public.has_school_role(c.school_id,array['admin']::public.app_role[])))
with check (exists(select 1 from public.reference_categories c where c.id=category_id and public.has_school_role(c.school_id,array['admin']::public.app_role[])));

create or replace function public.create_fiscal_year(p_school uuid,p_label text,p_start date,p_end date)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.has_school_role(p_school,array['admin']::public.app_role[]) then
    raise exception 'ไม่มีสิทธิ์เพิ่มปีงบประมาณ';
  end if;
  if nullif(trim(p_label),'') is null or p_start is null or p_end is null or p_start>p_end then
    raise exception 'ชื่อปีหรือช่วงวันที่ไม่ถูกต้อง';
  end if;
  insert into public.fiscal_years(school_id,label,start_date,end_date,is_open)
  values(p_school,trim(p_label),p_start,p_end,true) returning id into v_id;
  insert into public.audit_events(school_id,actor_id,action,entity_type,entity_id,after_data)
  values(p_school,auth.uid(),'create','fiscal_year',v_id,jsonb_build_object('label',trim(p_label),'start_date',p_start,'end_date',p_end,'is_open',true));
  return v_id;
end;
$$;
revoke all on function public.create_fiscal_year(uuid,text,date,date) from public;
grant execute on function public.create_fiscal_year(uuid,text,date,date) to authenticated;

create or replace function public.save_school_settings(p_school uuid, p_values jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_before jsonb;
begin
  if auth.uid() is null or not public.has_school_role(p_school, array['admin']::public.app_role[]) then
    raise exception 'ไม่มีสิทธิ์ตั้งค่าโรงเรียน';
  end if;
  if nullif(trim(p_values->>'name'), '') is null then
    raise exception 'กรุณาระบุชื่อโรงเรียน';
  end if;
  select jsonb_build_object('name', s.name, 'authority', s.authority) into v_before
  from public.schools s where s.id = p_school for update;
  if not found then raise exception 'ไม่พบโรงเรียน'; end if;

  update public.schools
  set name = trim(p_values->>'name'),
      authority = coalesce(nullif(trim(p_values->>'authority'), ''), authority)
  where id = p_school;

  insert into public.school_settings(school_id,address,phone,director_name,deputy_name,footer_text,updated_at,updated_by)
  values (p_school, nullif(trim(p_values->>'address'), ''), nullif(trim(p_values->>'phone'), ''),
          nullif(trim(p_values->>'director_name'), ''), nullif(trim(p_values->>'deputy_name'), ''),
          nullif(trim(p_values->>'footer_text'), ''), now(), auth.uid())
  on conflict (school_id) do update set
    address = excluded.address,
    phone = excluded.phone,
    director_name = excluded.director_name,
    deputy_name = excluded.deputy_name,
    footer_text = excluded.footer_text,
    updated_at = now(),
    updated_by = auth.uid();

  insert into public.audit_events(school_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values (p_school,auth.uid(),'update','school_settings',p_school,v_before,
          jsonb_build_object('name',trim(p_values->>'name'),'authority',nullif(trim(p_values->>'authority'),'')) || p_values - 'name' - 'authority');
end;
$$;
revoke all on function public.save_school_settings(uuid,jsonb) from public;
grant execute on function public.save_school_settings(uuid,jsonb) to authenticated;

create or replace function public.set_fiscal_year_open(p_year uuid, p_open boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_school uuid; v_before jsonb;
begin
  select school_id, jsonb_build_object('label',label,'is_open',is_open,'reopen_reason',reopen_reason)
  into v_school, v_before from public.fiscal_years where id=p_year for update;
  if not found then raise exception 'ไม่พบปีงบประมาณ'; end if;
  if auth.uid() is null or not public.has_school_role(v_school,array['admin']::public.app_role[]) then
    raise exception 'ไม่มีสิทธิ์จัดการปีงบประมาณ';
  end if;
  if p_open and (select is_open from public.fiscal_years where id=p_year) = false
     and nullif(trim(p_reason),'') is null then
    raise exception 'การเปิดปีที่ปิดแล้วต้องระบุเหตุผล';
  end if;
  update public.fiscal_years set is_open=p_open,
    closed_at=case when p_open then null else now() end,
    closed_by=case when p_open then null else auth.uid() end,
    reopen_reason=case when p_open then trim(p_reason) else null end
  where id=p_year;
  insert into public.audit_events(school_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(v_school,auth.uid(),case when p_open then 'reopen' else 'close' end,'fiscal_year',p_year,v_before,
         jsonb_build_object('is_open',p_open,'reason',nullif(trim(p_reason),'')));
end;
$$;
revoke all on function public.set_fiscal_year_open(uuid,boolean,text) from public;
grant execute on function public.set_fiscal_year_open(uuid,boolean,text) to authenticated;

-- Seed only reference structures and the six explicitly supplied output labels.
-- No project, activity, assessment result, financial event, or signature is seeded.
insert into public.reference_categories(school_id,name,is_official,active)
select 'b0000000-0000-4000-8000-000000000001'::uuid, x.name, false, true
from (values
  ('แผนงาน'),('สนองผลผลิต'),('ยุทธศาสตร์ชาติระยะ 20 ปี'),('แผนการศึกษาแห่งชาติ พ.ศ. 2560–2579'),
  ('นโยบาย สพฐ.'),('นโยบาย สพป.จันทบุรี เขต 2'),('กลยุทธ์ สพป.จันทบุรี เขต 2'),
  ('มาตรฐานโรงเรียน'),('กลยุทธ์โรงเรียน'),('หมวดรายจ่าย')
) as x(name)
where not exists (
  select 1 from public.reference_categories c
  where c.school_id='b0000000-0000-4000-8000-000000000001'::uuid and c.name=x.name
);

insert into public.reference_items(category_id,label,description,active)
select c.id, x.label, 'รายการตั้งต้นจากข้อกำหนดระบบ ต้องตรวจและปรับตามเอกสารของโรงเรียน', true
from public.reference_categories c
cross join (values
 ('ผู้จบการศึกษาก่อนประถมศึกษา'),
 ('ผู้จบการศึกษาภาคบังคับ'),
 ('ผู้จบการศึกษามัธยมศึกษาตอนปลาย'),
 ('เด็กพิการได้รับการศึกษาขั้นพื้นฐานและการพัฒนาสมรรถภาพ'),
 ('เด็กด้อยโอกาสได้รับการศึกษาขั้นพื้นฐาน'),
 ('เด็กผู้มีความสามารถพิเศษได้รับการพัฒนาศักยภาพ')
) as x(label)
where c.school_id='b0000000-0000-4000-8000-000000000001'::uuid
  and c.name='สนองผลผลิต'
  and not exists(select 1 from public.reference_items i where i.category_id=c.id and i.label=x.label);
