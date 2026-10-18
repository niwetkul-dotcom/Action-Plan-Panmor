import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, CalendarDays, Database, Plus, Save, Shield, Users } from 'lucide-react'
import Swal from 'sweetalert2'
import { db, SCHOOL_ID, errorMessage } from '../../lib/supabase'
import { useSession } from '../auth/session'

type Tab = 'school' | 'years' | 'references' | 'roles'
const tabs: { id: Tab; label: string; icon: typeof Building2 }[] = [
  { id: 'school', label: 'ข้อมูลโรงเรียน', icon: Building2 },
  { id: 'years', label: 'ปีงบประมาณ', icon: CalendarDays },
  { id: 'references', label: 'ข้อมูลอ้างอิง', icon: Database },
  { id: 'roles', label: 'บุคลากรและสิทธิ์', icon: Users },
]
const roleOptions = [
  ['teacher', 'ครู/ผู้รับผิดชอบ'], ['department_head', 'หัวหน้ากลุ่มบริหาร'], ['budget_head', 'หัวหน้ากลุ่มงบประมาณ'],
  ['deputy_director', 'รองผู้อำนวยการ'], ['director', 'ผู้อำนวยการ'], ['admin', 'ผู้ดูแลระบบ'],
]

export default function AdminPage() {
  const [tab, setTab] = useState<Tab>('school')
  const [busy, setBusy] = useState(false)
  const [year, setYear] = useState({ label: '', start_date: '', end_date: '' })
  const [reference, setReference] = useState({ category: '', label: '', source_title: '', source_year: '', source_url: '' })
  const [role, setRole] = useState({ user_id: '', role: 'teacher', department_id: '' })
  const { user } = useSession()
  const qc = useQueryClient()
  const query = useQuery({
    queryKey: ['admin-setup', SCHOOL_ID], enabled: !!db && !!user,
    queryFn: async () => {
      const [school, settings, years, departments, categories, assignments, profiles] = await Promise.all([
        db!.from('schools').select('id,name,authority').eq('id', SCHOOL_ID).single(),
        db!.from('school_settings').select('*').eq('school_id', SCHOOL_ID).maybeSingle(),
        db!.from('fiscal_years').select('id,label,start_date,end_date,is_open,closed_at,reopen_reason').eq('school_id', SCHOOL_ID).order('start_date', { ascending: false }).limit(50),
        db!.from('departments').select('id,name,active').eq('school_id', SCHOOL_ID).order('name'),
        db!.from('reference_categories').select('id,name,is_official,active,reference_items(id,label,source_title,source_year,source_url,active,version)').eq('school_id', SCHOOL_ID).order('name'),
        db!.from('role_assignments').select('id,user_id,role,department_id,active,profiles(display_name,position)').eq('school_id', SCHOOL_ID).order('created_at', { ascending: false }).limit(100),
        db!.from('profiles').select('id,display_name,position,active').order('display_name').limit(200),
      ])
      for (const result of [school, settings, years, departments, categories, assignments, profiles]) if (result.error) throw result.error
      return { school: school.data, settings: settings.data, years: years.data || [], departments: departments.data || [], categories: categories.data || [], assignments: assignments.data || [], profiles: profiles.data || [] }
    },
  })
  const refs = useMemo(() => query.data?.categories || [], [query.data])

  async function saveSettings(form: FormData) {
    if (!db) return
    setBusy(true)
    const values = Object.fromEntries(form.entries())
    const payload = { name: String(values.name || '').trim(), authority: String(values.authority || '').trim(), address: String(values.address || '').trim() || null, phone: String(values.phone || '').trim() || null, director_name: String(values.director_name || '').trim() || null, deputy_name: String(values.deputy_name || '').trim() || null, footer_text: String(values.footer_text || '').trim() || null }
    try {
      if (!payload.name) throw new Error('กรุณาระบุชื่อโรงเรียน')
      const { error } = await db.rpc('save_school_settings', { p_school: SCHOOL_ID, p_values: payload })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
      await Swal.fire({ icon: 'success', title: 'บันทึกข้อมูลโรงเรียนแล้ว' })
    } catch (error) { await Swal.fire({ icon: 'error', title: 'บันทึกไม่สำเร็จ', text: errorMessage(error) }) } finally { setBusy(false) }
  }

  async function addYear(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!db) return
    setBusy(true)
    try {
      if (!year.label.trim() || !year.start_date || !year.end_date || year.start_date > year.end_date) throw new Error('ระบุชื่อปีและช่วงวันที่ให้ถูกต้อง')
      const { error } = await db.rpc('create_fiscal_year', { p_school: SCHOOL_ID, p_label: year.label.trim(), p_start: year.start_date, p_end: year.end_date })
      if (error) throw error
      setYear({ label: '', start_date: '', end_date: '' }); await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
    } catch (error) { await Swal.fire({ icon: 'error', title: 'เพิ่มปีงบประมาณไม่สำเร็จ', text: errorMessage(error) }) } finally { setBusy(false) }
  }

  async function setYearOpen(id: string, open: boolean) {
    if (!db) return
    let reason: string | undefined
    if (open) {
      const result = await Swal.fire({ title: 'เหตุผลในการเปิดปีงบประมาณอีกครั้ง', input: 'textarea', inputPlaceholder: 'ระบุเหตุผลและเอกสารอ้างอิง', showCancelButton: true, confirmButtonText: 'เปิดปี', cancelButtonText: 'ยกเลิก', inputValidator: value => value?.trim() ? undefined : 'กรุณาระบุเหตุผล' })
      if (!result.isConfirmed) return
      reason = result.value.trim()
    } else {
      const result = await Swal.fire({ title: 'ปิดปีงบประมาณ?', text: 'ปีที่ปิดแล้วจะอ่านและพิมพ์ได้ แต่ใช้กับโครงการใหม่ไม่ได้', icon: 'warning', showCancelButton: true, confirmButtonText: 'ปิดปี', cancelButtonText: 'ยกเลิก' })
      if (!result.isConfirmed) return
    }
    setBusy(true)
    try {
      const { error } = await db.rpc('set_fiscal_year_open', { p_year: id, p_open: open, p_reason: reason || null })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
    } catch (error) { await Swal.fire({ icon: 'error', title: 'เปลี่ยนสถานะปีไม่สำเร็จ', text: errorMessage(error) }) } finally { setBusy(false) }
  }

  async function addReference(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!db) return
    setBusy(true)
    try {
      if (!reference.category.trim() || !reference.label.trim()) throw new Error('กรอกหมวดและรายการอ้างอิง')
      const found = refs.find((item: any) => item.name === reference.category.trim()) as any
      let categoryId = found?.id
      if (!categoryId) {
        const { data, error } = await db.from('reference_categories').insert({ school_id: SCHOOL_ID, name: reference.category.trim(), is_official: false }).select('id').single()
        if (error) throw error
        categoryId = data.id
      }
      const { error } = await db.from('reference_items').insert({ category_id: categoryId, label: reference.label.trim(), source_title: reference.source_title.trim() || null, source_year: reference.source_year.trim() || null, source_url: reference.source_url.trim() || null })
      if (error) throw error
      setReference({ category: '', label: '', source_title: '', source_year: '', source_url: '' }); await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
    } catch (error) { await Swal.fire({ icon: 'error', title: 'เพิ่มรายการไม่สำเร็จ', text: errorMessage(error) }) } finally { setBusy(false) }
  }

  async function addAssignment(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!db) return
    setBusy(true)
    try {
      if (!role.user_id) throw new Error('เลือกบัญชีบุคลากร')
      if (role.role === 'department_head' && !role.department_id) throw new Error('เลือกกลุ่มบริหารสำหรับหัวหน้ากลุ่ม')
      const { error } = await db.from('role_assignments').insert({ school_id: SCHOOL_ID, user_id: role.user_id, role: role.role, department_id: role.role === 'department_head' ? role.department_id : null, active: true, created_by: user?.id })
      if (error) throw error
      setRole({ user_id: '', role: 'teacher', department_id: '' }); await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
    } catch (error) { await Swal.fire({ icon: 'error', title: 'กำหนดสิทธิ์ไม่สำเร็จ', text: errorMessage(error) }) } finally { setBusy(false) }
  }

  async function toggleAssignment(id: string, active: boolean) {
    if (!db) return
    const result = await Swal.fire({ title: active ? 'ปิดสิทธิ์นี้?' : 'เปิดสิทธิ์นี้?', icon: 'warning', showCancelButton: true, confirmButtonText: active ? 'ปิดสิทธิ์' : 'เปิดสิทธิ์', cancelButtonText: 'ยกเลิก' })
    if (!result.isConfirmed) return
    const { error } = await db.from('role_assignments').update({ active: !active }).eq('id', id)
    if (error) await Swal.fire({ icon: 'error', title: 'เปลี่ยนสิทธิ์ไม่สำเร็จ', text: errorMessage(error) })
    else await qc.invalidateQueries({ queryKey: ['admin-setup', SCHOOL_ID] })
  }

  if (!db) return <div className="page"><div className="notice warn">ตั้งค่า URL และ publishable key ของ Supabase ใน `.env.local` ก่อน</div></div>
  if (query.isLoading) return <div className="page"><div className="panel">กำลังโหลดข้อมูลตั้งค่า…</div></div>
  if (query.isError) return <div className="page"><div className="notice error">โหลดข้อมูลตั้งค่าไม่สำเร็จ ตรวจบัญชีและสิทธิ์ผู้ดูแล แล้วลองใหม่</div></div>
  const isAdmin = query.data!.assignments.some((x: any) => x.user_id === user?.id && x.role === 'admin' && x.active)
  if (!isAdmin) return <div className="page"><div className="notice warn"><Shield size={17}/> หน้านี้เปิดได้เฉพาะผู้ดูแลระบบ</div></div>

  return <div className="page">
    <div className="page-heading"><div><div className="eyebrow">จัดการระบบ</div><h1>ตั้งค่าและข้อมูลพื้นฐาน</h1><p>ข้อมูลส่วนนี้ใช้กับแบบโครงการ เอกสาร และสิทธิ์ของบุคลากร</p></div></div>
    <div className="admin-tabs" role="tablist">{tabs.map(item => { const Icon = item.icon; return <button key={item.id} role="tab" aria-selected={tab === item.id} className={`admin-tab ${tab === item.id ? 'active' : ''}`} onClick={() => setTab(item.id)}><Icon size={16}/>{item.label}</button> })}</div>
    {tab === 'school' && <section className="panel form-panel"><div className="panel-heading"><div><h2>ข้อมูลที่ใช้ในเอกสาร</h2><p>ชื่อและข้อมูลที่ใช้แสดงผลจริงจากโรงเรียน</p></div></div><form action={saveSettings}><div className="form-grid"><label>ชื่อโรงเรียน<input name="name" defaultValue={query.data!.school?.name || ''} required/></label><label>สังกัด<input name="authority" defaultValue={query.data!.school?.authority || ''}/></label><label className="span-2">ที่อยู่<input name="address" defaultValue={query.data!.settings?.address || ''}/></label><label>โทรศัพท์<input name="phone" defaultValue={query.data!.settings?.phone || ''}/></label><label>ผู้อำนวยการ<input name="director_name" defaultValue={query.data!.settings?.director_name || ''}/></label><label>รองผู้อำนวยการ<input name="deputy_name" defaultValue={query.data!.settings?.deputy_name || ''}/></label><label className="span-2">ข้อความท้ายระบบ<input name="footer_text" defaultValue={query.data!.settings?.footer_text || ''}/></label></div><button className="button primary" disabled={busy} type="submit"><Save size={16}/> บันทึกข้อมูล</button></form><div className="notice info">ตราโรงเรียน ตราครุฑ และฟอนต์เอกสารยังต้องอัปโหลดไฟล์จริงก่อนใช้พิมพ์เอกสาร</div></section>}
    {tab === 'years' && <section className="admin-grid"><div className="panel form-panel"><h2>เพิ่มปีงบประมาณ</h2><p>ระบุช่วงวันที่ตามเอกสารที่โรงเรียนยืนยัน</p><form onSubmit={addYear} className="form-grid"><label>ชื่อปี<input value={year.label} onChange={e => setYear({ ...year, label: e.target.value })} placeholder="เช่น 2570" required/></label><label>วันเริ่ม<input type="date" value={year.start_date} onChange={e => setYear({ ...year, start_date: e.target.value })} required/></label><label>วันสิ้นสุด<input type="date" value={year.end_date} onChange={e => setYear({ ...year, end_date: e.target.value })} required/></label><button className="button primary" disabled={busy}><Plus size={16}/> เพิ่มปี</button></form></div><div className="panel list-panel"><div className="panel-heading"><div><h2>ปีที่ตั้งค่าแล้ว</h2><p>ปีที่ปิดยังอ่านและพิมพ์ได้</p></div></div>{!query.data!.years.length?<div className="notice warn">ยังไม่มีปีงบประมาณ โปรดระบุจากเอกสารจริง</div>:<div className="table-scroll"><table className="data-table"><thead><tr><th>ปี</th><th>ช่วงวันที่</th><th>สถานะ</th><th></th></tr></thead><tbody>{query.data!.years.map((item: any) => <tr key={item.id}><td><b>{item.label}</b></td><td>{item.start_date} – {item.end_date}</td><td><span className={`status-badge ${item.is_open ? 'status-approved' : 'status-archived'}`}>{item.is_open ? 'เปิดใช้งาน' : 'ปิดแล้ว'}</span>{item.reopen_reason && <small className="table-sub">เหตุผลเปิดใหม่: {item.reopen_reason}</small>}</td><td><button className="button secondary small" disabled={busy} onClick={() => setYearOpen(item.id, !item.is_open)}>{item.is_open ? 'ปิดปี' : 'เปิดใหม่'}</button></td></tr>)}</tbody></table></div>}</div></section>}
    {tab === 'references' && <section className="admin-grid"><div className="panel form-panel"><h2>เพิ่มข้อมูลอ้างอิง</h2><p>รายการนโยบายต้องมีเอกสารที่ตรวจสอบได้</p><form onSubmit={addReference} className="form-grid"><label>หมวด<input value={reference.category} onChange={e => setReference({ ...reference, category: e.target.value })} placeholder="เช่น สนองผลผลิต" required/></label><label>รายการ<input value={reference.label} onChange={e => setReference({ ...reference, label: e.target.value })} required/></label><label className="span-2">ชื่อเอกสารอ้างอิง<input value={reference.source_title} onChange={e => setReference({ ...reference, source_title: e.target.value })}/></label><label>ปี/ฉบับ<input value={reference.source_year} onChange={e => setReference({ ...reference, source_year: e.target.value })}/></label><label>URL แหล่งอ้างอิง<input type="url" value={reference.source_url} onChange={e => setReference({ ...reference, source_url: e.target.value })}/></label><button className="button primary" disabled={busy}><Plus size={16}/> เพิ่มรายการ</button></form></div><div className="panel list-panel"><div className="panel-heading"><div><h2>รายการอ้างอิง</h2><p>รายการที่ยังไม่มีเอกสารจะแสดงว่าไม่มีแหล่งอ้างอิง</p></div></div>{refs.map((category: any) => <div key={category.id} className="reference-group"><h3>{category.name}</h3>{category.reference_items?.length ? <ul>{category.reference_items.map((item: any) => <li key={item.id}>{item.label}<small>{[item.source_title, item.source_year].filter(Boolean).join(' · ') || 'ยังไม่ระบุเอกสารอ้างอิง'}</small></li>)}</ul> : <small>รอเพิ่มรายการที่มีแหล่งข้อมูลจริง</small>}</div>)}</div></section>}
    {tab === 'roles' && <section className="admin-grid"><div className="panel form-panel"><h2>กำหนดสิทธิ์บัญชี</h2><p>เลือกบัญชีที่มีอยู่ใน Supabase Auth; การเชิญ/ตั้งรหัสทำผ่านขั้นตอนผู้ดูแลที่ปลอดภัย</p><form onSubmit={addAssignment} className="form-grid"><label className="span-2">บุคลากร<select value={role.user_id} onChange={e => setRole({ ...role, user_id: e.target.value })} required><option value="">เลือกบัญชี</option>{query.data!.profiles.filter((x: any) => x.active).map((profile: any) => <option key={profile.id} value={profile.id}>{profile.display_name} · {profile.id.slice(0, 8)}</option>)}</select></label><label>บทบาท<select value={role.role} onChange={e => setRole({ ...role, role: e.target.value })}>{roleOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>{role.role === 'department_head' && <label>กลุ่มบริหาร<select value={role.department_id} onChange={e => setRole({ ...role, department_id: e.target.value })}><option value="">เลือกกลุ่ม</option>{query.data!.departments.map((department: any) => <option key={department.id} value={department.id}>{department.name}</option>)}</select></label>}<button className="button primary" disabled={busy}><Plus size={16}/> เพิ่มสิทธิ์</button></form></div><div className="panel list-panel"><div className="panel-heading"><div><h2>สิทธิ์ที่กำหนดไว้</h2><p>บัญชีเดียวมีหลายบทบาทได้</p></div></div><div className="table-scroll"><table className="data-table"><thead><tr><th>บุคลากร</th><th>บทบาท</th><th>สถานะ</th><th></th></tr></thead><tbody>{query.data!.assignments.map((item: any) => <tr key={item.id}><td>{item.profiles?.display_name || item.user_id.slice(0, 8)}<small className="table-sub">{item.profiles?.position || item.user_id}</small></td><td>{roleOptions.find(([value]) => value === item.role)?.[1] || item.role}</td><td>{item.active ? 'เปิด' : 'ปิด'}</td><td><button className="button secondary small" onClick={() => toggleAssignment(item.id, item.active)}>{item.active ? 'ปิดสิทธิ์' : 'เปิดสิทธิ์'}</button></td></tr>)}</tbody></table></div></div></section>}
  </div>
}
