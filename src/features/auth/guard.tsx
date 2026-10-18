import { Navigate, Outlet } from 'react-router-dom'
import { useSession } from './session'
import { LoadingScreen } from '../../components/feedback'
export function ProtectedRoute() {
  const { user, loading } = useSession()
  if (loading) return <LoadingScreen />
  return user ? <Outlet /> : <Navigate to="/login" replace />
}
