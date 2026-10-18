import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { db } from '../../lib/supabase'

type SessionValue = { session: Session | null; user: User | null; displayName: string; loading: boolean }
const SessionContext = createContext<SessionValue>({ session: null, user: null, displayName: '', loading: true })
export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [displayName, setDisplayName] = useState('')
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    if (!db) { setLoading(false); return }
    let alive = true
    db.auth.getSession().then(async ({ data }) => {
      if (!alive) return
      setSession(data.session)
      if (data.session?.user) await loadProfile(data.session.user.id)
      setLoading(false)
    })
    const { data: listener } = db.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      setLoading(false)
      if (next?.user) queueMicrotask(() => loadProfile(next.user.id))
      else setDisplayName('')
    })
    async function loadProfile(id: string) {
      const { data } = await db!.from('profiles').select('display_name').eq('id', id).maybeSingle()
      if (alive && data?.display_name) setDisplayName(data.display_name)
    }
    return () => { alive = false; listener.subscription.unsubscribe() }
  }, [])
  const value = useMemo(() => ({ session, user: session?.user ?? null, displayName, loading }), [session, displayName, loading])
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}
export const useSession = () => useContext(SessionContext)
