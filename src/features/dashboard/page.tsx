import { useEffect, useRef } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ArcElement, Chart as ChartJS, Tooltip, Legend, DoughnutController, type Chart } from 'chart.js'
import { ArrowUpRight, ClipboardList, CircleCheck, Clock3, FilePenLine, FolderOpen, RefreshCw } from 'lucide-react'
import { Link } from 'react-router-dom'
import { db, SCHOOL_ID, thaiDate } from '../../lib/supabase'
import { Empty } from '../../components/feedback'

ChartJS.register(ArcElement, Tooltip, Legend, DoughnutController)
const statusList = [
  { key:'draft', label:'ฉบับร่าง', color:'#bcb5d9', icon:FilePenLine },
  { key:'submitted', label:'รอพิจารณา', color:'#efb96f', icon:Clock3 },
  { key:'in_review', label:'อยู่ระหว่างพิจารณา', color:'#8e82d0', icon:ClipboardList },
  { key:'approved', label:'อนุมัติแล้ว', color:'#44a89b', icon:CircleCheck },
  { key:'returned', label:'ส่งกลับแก้ไข', color:'#e895a4', icon:RefreshCw },
]
export default function DashboardPage() {
  const chartCanvas = useRef<HTMLCanvasElement>(null)
  const chartRef = useRef<Chart|null>(null)
  const { data, isLoading, isError, refetch } = useQuery({ queryKey:['dashboard',SCHOOL_ID], enabled:!!db, queryFn:async()=>{
    const counts = await Promise.all(statusList.map(async x=>{
      const { count, error } = await db!.from('projects').select('id',{count:'exact',head:true}).eq('school_id',SCHOOL_ID).eq('status',x.key)
      if (error) throw error
      return { ...x, count:count||0 }
    }))
    const { data: recent, error } = await db!.from('projects').select('id,title,status,updated_at').eq('school_id',SCHOOL_ID).order('updated_at',{ascending:false}).limit(5)
    if (error) throw error
    return { counts, recent:recent||[], total:counts.reduce((sum,x)=>sum+x.count,0) }
  }})
  useEffect(()=>{
    if (!data || !chartCanvas.current) return
    chartRef.current?.destroy()
    chartRef.current = new ChartJS(chartCanvas.current,{type:'doughnut',data:{labels:data.counts.map(x=>x.label),datasets:[{data:data.counts.map(x=>x.count),backgroundColor:data.counts.map(x=>x.color),borderWidth:0,hoverOffset:5}]},options:{responsive:true,maintainAspectRatio:false,cutout:'70%',plugins:{legend:{display:false},tooltip:{callbacks:{label:ctx=>` ${ctx.label}: ${ctx.raw} โครงการ`}}}}})
    return ()=>chartRef.current?.destroy()
  },[data])
  if (!db) return <div className="page"><div className="notice warn">ยังไม่ได้ตั้งค่าการเชื่อมต่อ Supabase เปิดไฟล์ <code>.env.local</code> แล้วใส่ URL และ Publishable Key ก่อนใช้งาน</div></div>
  return <div className="page">
    <div className="page-heading"><div><div className="eyebrow">ภาพรวมการดำเนินงาน</div><h1>สวัสดี, ยินดีต้อนรับ</h1><p>สรุปสถานะโครงการจากข้อมูลที่บัญชีของคุณมีสิทธิ์เข้าถึง</p></div><button className="button secondary" onClick={()=>refetch()}><RefreshCw size={16}/> อัปเดตข้อมูล</button></div>
    {isError&&<div className="notice error">โหลดข้อมูลไม่สำเร็จ ตรวจสิทธิ์หรือการเชื่อมต่อ แล้วลองอัปเดตอีกครั้ง</div>}
    <section className="stat-grid">{statusList.map((x,i)=>{const Icon=x.icon;return <div className={`stat-card tone-${i}`} key={x.key}><div className="stat-top"><span>{x.label}</span><span className="stat-icon"><Icon size={18}/></span></div><strong>{isLoading?'—':data?.counts[i].count??0}</strong><small>โครงการ</small></div>})}</section>
    <section className="dashboard-grid"><div className="panel chart-panel"><div className="panel-heading"><div><h2>สถานะโครงการ</h2><p>จำนวนตามสถานะเอกสารในข้อมูลที่มองเห็น</p></div><span className="soft-chip">{data?.total??0} โครงการ</span></div>{isLoading?<div className="chart-skeleton"/>:data?.total===0?<Empty title="ยังไม่มีโครงการ" detail="เริ่มเขียนโครงการเพื่อแสดงภาพรวมที่นี่"/>:<><div className="donut-wrap"><canvas ref={chartCanvas}/><div className="donut-total"><strong>{data?.total}</strong><small>รวม</small></div></div><div className="legend-list">{data?.counts.map(x=><div key={x.key}><i style={{background:x.color}}/><span>{x.label}</span><b>{x.count}</b></div>)}</div></>}</div>
      <div className="panel recent-panel"><div className="panel-heading"><div><h2>รายการปรับปรุงล่าสุด</h2><p>รายการล่าสุดที่บัญชีนี้เปิดดูได้</p></div><Link className="text-link" to="/projects">ดูทั้งหมด <ArrowUpRight size={15}/></Link></div>{isLoading?<div className="skeleton-lines"><i/><i/><i/></div>:!data?.recent.length?<Empty title="ยังไม่มีรายการ" detail="โครงการที่บันทึกจะปรากฏในรายการนี้"/>:<div className="recent-list">{data.recent.map(row=><Link className="recent-row" key={row.id} to={`/projects/${row.id}/edit`}><div className="file-mark"><FolderOpen size={18}/></div><div className="recent-main"><b>{row.title}</b><span>แก้ไขล่าสุด {thaiDate(row.updated_at)}</span></div><span className={`status-badge status-${row.status}`}>{row.status}</span></Link>)}</div>}<Link to="/projects/new" className="button primary full create-cta"><ClipboardList size={17}/> เริ่มเขียนโครงการ</Link></div></section>
    <section className="panel tip-panel"><div className="tip-icon"><FolderOpen size={20}/></div><div><b>ยอดเงินจะปรากฏเมื่อมีการบันทึกกรอบและรายการเงินจริง</b><p>ระบบไม่แสดงยอดคงเหลือจากข้อมูลตัวอย่าง และคำนวณเงินจากทะเบียนรายการที่ได้รับการอนุมัติ</p></div><Link to="/budget" className="text-link">ไปหน้างบประมาณ <ArrowUpRight size={15}/></Link></section>
  </div>
}
