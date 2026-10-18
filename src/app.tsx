import { lazy, Suspense } from 'react'
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom'
import { SessionProvider } from './features/auth/session'
import { ProtectedRoute } from './features/auth/guard'
import { LoadingScreen } from './components/feedback'
import { AppShell } from './components/shell'

const Login = lazy(() => import('./features/auth/login'))
const Dashboard = lazy(() => import('./features/dashboard/page'))
const Projects = lazy(() => import('./features/projects/list'))
const ProjectForm = lazy(() => import('./features/projects/form'))
const Workflow = lazy(() => import('./features/workflow/page'))
const Budget = lazy(() => import('./features/budget/page'))
const Cipp = lazy(() => import('./features/cipp/page'))
const ActivityRequests = lazy(() => import('./features/requests/page'))
const Admin = lazy(() => import('./features/admin/page'))

export function App() {
  return <SessionProvider><HashRouter><Suspense fallback={<LoadingScreen/>}><Routes>
    <Route path="/login" element={<Login/>}/>
    <Route element={<ProtectedRoute/>}><Route element={<AppShell/>}>
      <Route path="/" element={<Dashboard/>}/><Route path="/projects" element={<Projects/>}/><Route path="/projects/new" element={<ProjectForm/>}/><Route path="/projects/:id/edit" element={<ProjectForm/>}/>
      <Route path="/review" element={<Workflow/>}/><Route path="/requests" element={<ActivityRequests/>}/><Route path="/budget" element={<Budget/>}/><Route path="/cipp" element={<Cipp/>}/>
      <Route path="/admin" element={<Admin/>}/>
    </Route></Route>
    <Route path="*" element={<Navigate to="/" replace/>}/>
  </Routes></Suspense></HashRouter></SessionProvider>
}
