import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
export const isSupabaseConfigured = Boolean(url && key && !url.includes('your-project'))
export const db = (isSupabaseConfigured ? createClient(url!, key!) : null) as SupabaseClient<any> | null
export const SCHOOL_ID = 'b0000000-0000-4000-8000-000000000001'
export const thaiDate = (date: string | Date) => new Intl.DateTimeFormat('th-TH-u-ca-buddhist', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }).format(new Date(date))
export const todayBangkok = () => {
  const values = Object.fromEntries(new Intl.DateTimeFormat('en', { timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit' }).formatToParts(new Date()).map(part=>[part.type,part.value]))
  return `${values.year}-${values.month}-${values.day}`
}
export const baht = (amount: number | string | null | undefined) => new Intl.NumberFormat('th-TH', { style: 'currency', currency: 'THB', maximumFractionDigits: 2 }).format(Number(amount || 0))
export const errorMessage = (error: unknown) => error instanceof Error ? error.message : 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่'
