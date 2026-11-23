import { useEffect, useState } from 'react'
import GoogleMark from '../components/GoogleMark.jsx'

export default function InvitePage({ token }) {
  const [status, setStatus] = useState('loading')
  const [coach, setCoach] = useState('')
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setStatus('loading')
      try {
        const response = await fetch('/api/convites/verificar', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token }), signal: controller.signal })
        if (response.status === 404) { setStatus('invalid'); return }
        if (!response.ok) throw new Error('unavailable')
        const invite = await response.json()
        setCoach(invite.treinador)
        const config = await fetch('/api/auth/config', { signal: controller.signal, cache: 'no-store' })
        if (!config.ok) throw new Error('unavailable')
        setStatus((await config.json()).google ? 'ready' : 'unconfigured')
      } catch (failure) { if (failure.name !== 'AbortError') setStatus('error') }
    }
    load()
    return () => controller.abort()
  }, [token, attempt])

  return <main className="invitation-page"><a className="brand" href="#/">POWER<span className="brand-light">SYSTEM</span></a><section className="invitation-card" aria-labelledby="invitation-title"><p className="eyebrow">CONVITE PARA ALUNO</p><h1 id="invitation-title">Seu treino.<br />Sua evolução.</h1>
    {status === 'loading' ? <p role="status">Verificando seu convite…</p> : status === 'invalid' ? <div role="alert"><h2>Este convite não está disponível.</h2><p>Ele pode ter expirado, já ter sido usado ou ter sido substituído. Peça um novo link ao seu treinador.</p><a className="primary-link" href="#/entrar">Já tenho acesso →</a></div> : status === 'error' ? <div role="alert"><p>Não foi possível verificar o convite agora.</p><button className="dashboard-action" onClick={() => setAttempt((value) => value + 1)}>Tentar novamente</button></div> : <>
      <p><strong>{coach}</strong> convidou você para acompanhar seus treinos no Power System.</p><p>Entre com sua conta Google. Depois, confirme seu nome. Se quiser, informe também seu peso corporal; ele é opcional e pode ser registrado mais tarde.</p>
      {status === 'ready' ? <a className="google-button" href={`/api/auth/google?convite=${encodeURIComponent(token)}`}><GoogleMark /><span>Entrar com o Google</span></a> : <p className="auth-message">O acesso com Google está temporariamente indisponível. Tente novamente mais tarde.</p>}
      <p className="auth-privacy">Sua senha do Google não é compartilhada com o Power System. Seu cadastro só é concluído depois que você confirmar seu nome. Este convite é de uso único.</p>
    </>}
    <a className="auth-back" href="#/">← Voltar ao início</a>
  </section></main>
}
