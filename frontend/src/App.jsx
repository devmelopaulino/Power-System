import { useEffect, useState } from 'react'
import HomePage from './pages/HomePage.jsx'
import AuthPage from './pages/AuthPage.jsx'
import StudentsPage from './pages/StudentsPage.jsx'
import InvitePage from './pages/InvitePage.jsx'
import MyWorkoutsPage from './pages/MyWorkoutsPage.jsx'
import CompleteStudentSignupPage from './pages/CompleteStudentSignupPage.jsx'
import StudentProfilePage from './pages/StudentProfilePage.jsx'

function currentLocation() {
  const [path, query = ''] = window.location.hash.slice(1).split('?')
  return { path: path.startsWith('/') ? path : '/', query }
}

export default function App() {
  const [location, setLocation] = useState(currentLocation)
  useEffect(() => {
    const update = () => setLocation(currentLocation())
    window.addEventListener('hashchange', update)
    return () => window.removeEventListener('hashchange', update)
  }, [])
  useEffect(() => {
    if (location.path !== '/') window.scrollTo(0, 0)
    document.title = location.path === '/completar-cadastro' ? 'Concluir cadastro | Power System'
      : location.path === '/minha-evolucao' ? 'Minha evolução | Power System'
      : location.path === '/meu-peso' ? 'Peso corporal | Power System'
      : location.path === '/meu-perfil' ? 'Meu perfil | Power System'
      : location.path === '/meus-treinos' ? 'Meus treinos | Power System'
      : location.path.startsWith('/convite/') ? 'Convite para aluno | Power System'
      : location.path.startsWith('/alunos/') ? 'Perfil do aluno | Power System'
      : location.path === '/alunos' ? 'Meus alunos | Power System'
      : location.path === '/entrar' ? 'Entrar | Power System'
        : location.path === '/cadastro' ? 'Criar conta | Power System' : 'Power System'
  }, [location.path])

  if (location.path === '/entrar' || location.path === '/cadastro') {
    return <AuthPage key={location.path + location.query} registering={location.path === '/cadastro'} query={location.query} />
  }
  if (location.path === '/alunos') return <StudentsPage />
  const studentRoute = location.path.match(/^\/alunos\/(\d+)(\/(?:treino|dados))?$/)
  if (studentRoute) return <StudentProfilePage key={studentRoute[1] + (studentRoute[2] || '')} studentId={studentRoute[1]} editor={studentRoute[2] === '/treino'} athleteData={studentRoute[2] === '/dados'} query={location.query} />
  if (location.path === '/completar-cadastro') return <CompleteStudentSignupPage />
  if (location.path === '/minha-evolucao') return <MyWorkoutsPage evolution />
  if (location.path === '/meu-peso') return <MyWorkoutsPage bodyWeight />
  if (location.path === '/meu-perfil') return <MyWorkoutsPage personal />
  if (location.path === '/meus-treinos') return <MyWorkoutsPage />
  if (location.path.startsWith('/convite/')) return <InvitePage token={location.path.slice('/convite/'.length)} />
  return <HomePage />
}
