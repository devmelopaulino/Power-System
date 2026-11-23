import PendingWrites from './PendingWrites.jsx'
import { useState } from 'react'

export default function AccountHeader({ account, onError }) {
  const [leaving, setLeaving] = useState(false)
  async function logout() {
    setLeaving(true)
    onError('')
    try {
      const response = await fetch('/api/auth/logout', { method: 'POST', headers: { 'X-Power-System-Request': '1' } })
      if (!response.ok) throw new Error('Não foi possível sair. Tente novamente.')
      window.location.hash = '/entrar'
    } catch (failure) { onError(failure.message); setLeaving(false) }
  }
  return <><header className="site-header">
    <a className="brand" href="#/">POWER<span className="brand-light">SYSTEM</span></a>
    <div className="account-controls"><span>{account?.nome}</span><button onClick={logout} disabled={leaving || !account}>{leaving ? 'Saindo…' : 'Sair'}</button></div>
  </header><PendingWrites account={account}/></>
}
