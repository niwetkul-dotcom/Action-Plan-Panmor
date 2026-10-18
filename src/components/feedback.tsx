import { LoaderCircle } from 'lucide-react'
export function LoadingScreen() { return <div className="loading-screen"><LoaderCircle className="spin" size={30}/><span>กำลังโหลด...</span></div> }
export function Empty({ title, detail }: { title: string; detail: string }) { return <div className="empty-state"><div className="empty-mark">•</div><strong>{title}</strong><span>{detail}</span></div> }
