import { useState } from 'react'
import { Mail, LockKeyhole, ArrowRight, KeyRound, GraduationCap } from 'lucide-react'
import Swal from 'sweetalert2'
import { Link, Navigate } from 'react-router-dom'
import { db, errorMessage, isSupabaseConfigured } from '../../lib/supabase'
import { useSession } from './session'

export default function LoginPage() {
  const { user } = useSession()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  if (user) return <Navigate to="/" replace/>
  async function signIn(e: React.FormEvent) {
    e.preventDefault()
    if (!db) return
    setBusy(true)
    const { error } = await db.auth.signInWithPassword({ email: email.trim(), password })
    setBusy(false)
    if (error) { await Swal.fire({ icon: 'error', title: 'เข้าสู่ระบบไม่สำเร็จ', text: error.message }); return }
  }
  async function forgotPassword() {
    if (!db || !email.trim()) { await Swal.fire({ icon: 'info', title: 'กรอกอีเมลก่อน', text: 'ระบุอีเมลบัญชีที่ได้รับเชิญ แล้วจึงขอตั้งรหัสผ่านใหม่' }); return }
    setBusy(true)
    const { error } = await db.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${window.location.origin}${window.location.pathname}#/login` })
    setBusy(false)
    await Swal.fire(error ? { icon: 'error', title: 'ส่งคำขอไม่สำเร็จ', text: errorMessage(error) } : { icon: 'success', title: 'ตรวจสอบอีเมล', text: 'หากบัญชีนี้ได้รับอนุญาต ระบบจะส่งลิงก์ตั้งรหัสผ่านให้' })
  }
  return <main className="login-page">
    <section className="login-art"><div className="brand-symbol"><GraduationCap size={32}/></div><p className="eyebrow">BAN PAN MOR SCHOOL</p><h1>ระบบเขียนและ<br/>รายงานโครงการ</h1><p>วางแผน ติดตามงบประมาณ และสรุปผลโครงการในพื้นที่ทำงานเดียว</p><div className="art-orbit"><span>แผน</span><span>กิจกรรม</span><span>รายงาน</span></div></section>
    <section className="login-card"><div className="mobile-brand"><div className="brand-symbol"><GraduationCap size={25}/></div><span>โรงเรียนบ้านปั้นหม้อ</span></div><div className="login-heading"><div className="overline">ยินดีต้อนรับ</div><h2>เข้าสู่ระบบ</h2><p>ใช้บัญชีที่ผู้ดูแลระบบสร้างให้</p></div>
      {!isSupabaseConfigured && <div className="notice warn">ยังไม่ได้เชื่อมต่อ Supabase โปรดตั้งค่า VITE_SUPABASE_URL และ VITE_SUPABASE_PUBLISHABLE_KEY ในไฟล์ .env.local</div>}
      <form onSubmit={signIn} className="form-stack"><label>อีเมล<div className="input-icon"><Mail size={17}/><input autoComplete="username" type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@example.com"/></div></label><label>รหัสผ่าน<div className="input-icon"><LockKeyhole size={17}/><input autoComplete="current-password" type="password" required value={password} onChange={e=>setPassword(e.target.value)} placeholder="กรอกรหัสผ่าน"/></div></label><button className="button primary full" type="submit" disabled={busy||!isSupabaseConfigured}>{busy?'กำลังตรวจสอบ...':'เข้าสู่ระบบ'}<ArrowRight size={17}/></button></form>
      <button className="link-button forgot" onClick={forgotPassword} disabled={busy}><KeyRound size={15}/> ลืมรหัสผ่าน</button>
      <div className="login-foot"><span>บัญชีเข้าใช้งานจัดการโดยผู้ดูแลระบบ</span><Link to="/">หน้าภาพรวม</Link></div>
    </section>
  </main>
}
