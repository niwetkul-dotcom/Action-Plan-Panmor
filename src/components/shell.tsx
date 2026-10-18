import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { LayoutDashboard, FolderKanban, CirclePlus, ClipboardCheck, WalletCards, ChartNoAxesCombined, Settings, Menu, LogOut, School, X, ReceiptText } from 'lucide-react'
import Swal from 'sweetalert2'
import { db, SCHOOL_ID } from '../lib/supabase'
import { useSession } from '../features/auth/session'

const links = [
  { to: '/', label: 'ภาพรวม', icon: LayoutDashboard, group: 'งานหลัก' },
  { to: '/projects', label: 'โครงการ', icon: FolderKanban, group: 'งานหลัก' },
  { to: '/projects/new', label: 'เขียนโครงการ', icon: CirclePlus, group: 'งานหลัก' },
  { to: '/review', label: 'งานรอพิจารณา', icon: ClipboardCheck, group: 'ติดตามงาน' },
  { to: '/requests', label: 'ขอดำเนินกิจกรรม', icon: ReceiptText, group: 'ติดตามงาน' },
  { to: '/budget', label: 'งบประมาณ', icon: WalletCards, group: 'ติดตามงาน' },
  { to: '/cipp', label: 'รายงานและ CIPP', icon: ChartNoAxesCombined, group: 'ติดตามงาน' },
  { to: '/admin', label: 'ตั้งค่าและข้อมูลพื้นฐาน', icon: Settings, group: 'ผู้ดูแล' },
]
export function AppShell() {
  const { displayName, user } = useSession()
  const navigate = useNavigate(), location = useLocation()
  const [roleNames, setRoleNames] = useState<string[]>([])
  const [mobileMenu, setMobileMenu] = useState(false)
  useEffect(() => { if (user && db) db.from('role_assignments').select('role').eq('school_id',SCHOOL_ID).eq('user_id',user.id).eq('active',true).then(({data})=>setRoleNames((data||[]).map((x:any)=>x.role))) },[user])
  async function signOut() {
    const result = await Swal.fire({ title:'ออกจากระบบ?', text:'ต้องการออกจากระบบใช่หรือไม่', icon:'question', showCancelButton:true, confirmButtonText:'ออกจากระบบ', cancelButtonText:'ยกเลิก', confirmButtonColor:'#7163c5' })
    if (result.isConfirmed && db) { await db.auth.signOut(); navigate('/login',{replace:true}) }
  }
  const isAdmin = roleNames.includes('admin')
  const title = links.find(x=>x.to===location.pathname)?.label || 'ระบบโครงการ'
  return <div className="app-layout">
    <aside className={`sidebar ${mobileMenu?'open':''}`}>
      <div className="sidebar-brand"><div className="brand-symbol small"><School size={20}/></div><div><strong>บ้านปั้นหม้อ</strong><small>ระบบโครงการ</small></div><button className="icon-button sidebar-close" onClick={()=>setMobileMenu(false)} aria-label="ปิดเมนู"><X size={19}/></button></div>
      <div className="sidebar-school">สำนักงานเขตพื้นที่การศึกษาประถมศึกษาจันทบุรี เขต 2</div>
      <nav>{['งานหลัก','ติดตามงาน','ผู้ดูแล'].map(group=>{if(group==='ผู้ดูแล'&&!isAdmin)return null;return <div className="nav-group" key={group}><span className="nav-label">{group}</span>{links.filter(x=>x.group===group).map(item=><NavLink key={item.to} to={item.to} end={item.to==='/'} onClick={()=>setMobileMenu(false)} className={({isActive})=>`nav-link ${isActive?'active':''}`}><item.icon size={18}/><span>{item.label}</span></NavLink>)}</div>})}</nav>
      <div className="sidebar-bottom"><div className="user-chip"><div className="avatar">{(displayName||'ผ').slice(0,1)}</div><div className="user-meta"><b>{displayName||'ผู้ใช้'}</b><small>{isAdmin?'ผู้ดูแลระบบ':roleNames[0]||'ผู้ใช้งาน'}</small></div><button className="icon-button" onClick={signOut} aria-label="ออกจากระบบ"><LogOut size={17}/></button></div></div>
    </aside>
    {mobileMenu&&<button className="mobile-backdrop" aria-label="ปิดเมนู" onClick={()=>setMobileMenu(false)}/>}
    <main className="main-area"><header className="topbar"><button className="icon-button mobile-menu-button" onClick={()=>setMobileMenu(true)} aria-label="เปิดเมนู"><Menu size={20}/></button><div className="breadcrumb"><span>ระบบโครงการ</span><b>/</b><strong>{title}</strong></div><div className="topbar-actions"><span className="year-chip">ปีงบประมาณ</span><div className="avatar mini">{(displayName||'ผ').slice(0,1)}</div></div></header><div className="page-content"><Outlet/></div>
      <nav className="mobile-nav">{links.filter(x=>['/','/projects','/projects/new','/review'].includes(x.to)).map(item=><NavLink key={item.to} to={item.to} end={item.to==='/'} className={({isActive})=>`mobile-nav-link ${isActive?'active':''}`}><item.icon size={19}/><span>{item.label}</span></NavLink>)}<button className="mobile-nav-link" onClick={()=>setMobileMenu(true)}><Menu size={19}/><span>เมนู</span></button></nav>
    </main>
  </div>
}
