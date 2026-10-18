import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Search, Plus, ChevronLeft, ChevronRight, FileText } from 'lucide-react'
import { db, SCHOOL_ID, thaiDate } from '../../lib/supabase'
import { Empty } from '../../components/feedback'
const pageSize=20
export default function ProjectsPage(){
  const [page,setPage]=useState(0),[search,setSearch]=useState(''),[status,setStatus]=useState('')
  const query=useQuery({queryKey:['projects',page,search,status],enabled:!!db,queryFn:async()=>{
    let q=db!.from('projects').select('id,title,status,updated_at,plan_start,plan_end', {count:'exact'}).eq('school_id',SCHOOL_ID).order('updated_at',{ascending:false}).range(page*pageSize,(page+1)*pageSize-1)
    if(search.trim())q=q.ilike('title',`%${search.trim()}%`)
    if(status)q=q.eq('status',status)
    const {data,error,count}=await q;if(error)throw error;return {rows:data||[],count:count||0}
  }})
  return <div className="page"><div className="page-heading"><div><div className="eyebrow">โครงการ</div><h1>โครงการของฉัน</h1><p>รายการที่มองเห็นตามสิทธิ์ของบัญชี</p></div><Link className="button primary" to="/projects/new"><Plus size={17}/> เขียนโครงการ</Link></div>
    <section className="panel list-panel"><div className="filter-row"><label className="search-box"><Search size={17}/><input value={search} onChange={e=>{setSearch(e.target.value);setPage(0)}} placeholder="ค้นหาชื่อโครงการ"/></label><select value={status} onChange={e=>{setStatus(e.target.value);setPage(0)}} aria-label="กรองสถานะ"><option value="">ทุกสถานะ</option><option value="draft">ฉบับร่าง</option><option value="submitted">รอพิจารณา</option><option value="in_review">กำลังพิจารณา</option><option value="returned">ส่งกลับแก้ไข</option><option value="approved">อนุมัติแล้ว</option><option value="rejected">ไม่อนุมัติ</option></select><span className="result-count">{query.data?.count??0} รายการ</span></div>
    {query.isLoading?<div className="skeleton-lines"><i/><i/><i/><i/></div>:query.isError?<div className="notice error">โหลดรายการไม่สำเร็จ กรุณาตรวจสิทธิ์และลองใหม่</div>:!query.data?.rows.length?<Empty title="ไม่พบโครงการ" detail={search||status?'ลองเปลี่ยนคำค้นหาหรือตัวกรอง':'เริ่มบันทึกร่างโครงการเพื่อให้รายการปรากฏที่นี่'}/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>ชื่อโครงการ</th><th>สถานะเอกสาร</th><th>ช่วงดำเนินการ</th><th>แก้ไขล่าสุด</th><th></th></tr></thead><tbody>{query.data.rows.map(row=><tr key={row.id}><td><div className="table-title"><span className="table-file"><FileText size={16}/></span><b>{row.title}</b></div></td><td><span className={`status-badge status-${row.status}`}>{({draft:'ฉบับร่าง',submitted:'รอพิจารณา',in_review:'กำลังพิจารณา',returned:'ส่งกลับแก้ไข',approved:'อนุมัติแล้ว',rejected:'ไม่อนุมัติ'} as Record<string,string>)[row.status]||row.status}</span></td><td>{row.plan_start&&row.plan_end?`${thaiDate(row.plan_start)} – ${thaiDate(row.plan_end)}`:'ยังไม่ระบุ'}</td><td>{thaiDate(row.updated_at)}</td><td>{['draft','returned'].includes(row.status)?<Link className="small-link" to={`/projects/${row.id}/edit`}>เปิดแก้ไข</Link>:<span className="muted">ดูข้อมูล</span>}</td></tr>)}</tbody></table></div>}
    <div className="pagination"><span>หน้า {page+1} จาก {Math.max(1,Math.ceil((query.data?.count||0)/pageSize))}</span><div><button className="icon-button" disabled={page===0} onClick={()=>setPage(Math.max(0,page-1))}><ChevronLeft size={18}/></button><button className="icon-button" disabled={!query.data||((page+1)*pageSize>=query.data.count)} onClick={()=>setPage(page+1)}><ChevronRight size={18}/></button></div></div></section></div>
}
