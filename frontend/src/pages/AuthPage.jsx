import { useEffect, useState } from 'react'

import GoogleMark from '../components/GoogleMark.jsx'

export default function AuthPage({ registering, query }) {
  const [status, setStatus] = useState('loading')
  const [attempt, setAttempt] = useState(0)
  const [profile, setProfile] = useState('treinador')
  const callbackError = new URLSearchParams(query).get('erro')

  useEffect(() => {
    const controller = new AbortController()
    async function checkAccess() {
      setStatus('loading')
      try {
        const configResponse = await fetch('/api/auth/config', { signal: controller.signal, cache: 'no-store' })
        if (!configResponse.ok) throw new Error('unavailable')
        const config = await configResponse.json()
        if (!config.google) { setStatus('unconfigured'); return }
        const sessionResponse = await fetch('/api/auth/me', { signal: controller.signal, cache: 'no-store' })
        if (sessionResponse.ok && !callbackError) {
          const account = await sessionResponse.json()
          window.location.hash = account.perfil === 'aluno' ? '/meus-treinos' : '/alunos'
          return
        }
        if (!sessionResponse.ok && sessionResponse.status !== 401) throw new Error('unavailable')
        setStatus('ready')
      } catch (error) {
        if (error.name !== 'AbortError') setStatus('error')
      }
    }
    checkAccess()
    return () => controller.abort()
  }, [attempt])

  return (
    <main className="auth-layout">
      <aside className="auth-story">
        <a className="brand" href="#/" aria-label="Power System — início"><span className="brand-mark" aria-hidden="true"><i /><i /><i /></span>POWER<span className="brand-light">SYSTEM</span></a>
        <div className="auth-story-copy"><p className="eyebrow">SEU PLANEJAMENTO. SUA EVOLUÇÃO.</p><h1>O PRÓXIMO<br />PASSO É<br /><span>EVOLUIR.</span></h1><p>Um espaço para organizar o trabalho de quem treina para ir mais longe.</p></div>
        <p className="auth-story-footer">AGACHAMENTO / SUPINO / LEVANTAMENTO TERRA</p>
      </aside>
      <section className="auth-form-panel" aria-labelledby="auth-title">
        <a className="auth-back" href="#/">← Voltar ao início</a>
        <div className="auth-content">
          <p className="eyebrow">ACESSE O POWER SYSTEM</p>
          <h2 id="auth-title">{registering ? 'Sua conta. Seu próximo passo.' : 'Bom ter você de volta.'}</h2>
          <p className="auth-intro">{registering ? 'Escolha como você vai usar o sistema. Seu acesso será feito com a conta Google.' : 'Entre com sua conta Google para acessar sua área de treinador ou aluno.'}</p>
          <nav className="auth-tabs" aria-label="Acesso à conta">
            <a href="#/entrar" aria-current={!registering ? 'page' : undefined}>Entrar</a>
            <a href="#/cadastro" aria-current={registering ? 'page' : undefined}>Criar conta</a>
          </nav>
          {callbackError && <div className="auth-message auth-error" role="alert">{({ sessao: 'Sua sessão terminou. Entre novamente para continuar.', cadastro: 'Esta conta ainda não foi cadastrada. Treinadores podem criar uma conta; alunos devem usar o convite do treinador.', convite_email: 'Esta conta Google não corresponde ao cadastro vinculado ao convite. Peça um novo link ao treinador.', perfil: 'Esta conta já tem outro perfil ou vínculo. Abra o convite novamente e use a conta Google do aluno.', convite: 'O convite expirou, já foi usado ou foi substituído. Peça um novo link ao treinador.' })[callbackError] || 'Não foi possível concluir o acesso com Google. Tente novamente.'}</div>}
          {registering && <div className="profile-choice" role="group" aria-label="Tipo de cadastro">
            <button type="button" aria-pressed={profile === 'treinador'} onClick={() => setProfile('treinador')}><strong>Sou treinador</strong><span>Vou montar e gerenciar treinos.</span></button>
            <button type="button" aria-pressed={profile === 'aluno'} onClick={() => setProfile('aluno')}><strong>Sou aluno</strong><span>Vou consultar meus treinos.</span></button>
          </div>}
          {registering && profile === 'aluno' ? <div className="student-signup-note"><h3>Seu acesso começa com um convite.</h3><p>Seu treinador envia um link de convite. Abra esse link, entre com Google e depois preencha seu nome para concluir o cadastro.</p><p>Se já aceitou o convite, use a opção <a href="#/entrar">Entrar</a>.</p></div> : status === 'ready' ? (
            <a className="google-button" href={registering ? "/api/auth/google?cadastro=treinador" : "/api/auth/google"}><GoogleMark /><span>{registering ? 'Inscrever-se com o Google' : 'Fazer login com o Google'}</span></a>
          ) : (
            <button className="google-button" disabled><GoogleMark /><span>{status === 'loading' ? 'Verificando acesso…' : 'Continuar com Google'}</span></button>
          )}
          {(!registering || profile === "treinador") && <div aria-live="polite">
            {status === 'unconfigured' && <p className="auth-message">O login com Google ainda não foi ativado. O acesso estará disponível em breve.</p>}
            {status === 'error' && <div className="auth-message auth-error">Não foi possível conectar ao serviço. <button className="text-button" onClick={() => setAttempt((value) => value + 1)}>Tentar novamente</button></div>}
          </div>}
          <p className="auth-privacy">{registering && profile === 'treinador' ? 'No primeiro acesso, criamos seu perfil de treinador com seu nome e e-mail do Google.' : 'Seu acesso é feito pelo Google. Você não precisa criar outra senha.'} Sua senha do Google não é compartilhada com o Power System.</p>
          <div className="auth-switch">{registering ? 'Já tem uma conta?' : 'Ainda não tem conta?'} <a href={registering ? '#/entrar' : '#/cadastro'}>{registering ? 'Entrar' : 'Criar minha conta'} →</a></div>
        </div>
        <p className="auth-panel-footer">POWER SYSTEM · TREINAMENTO COM DIREÇÃO</p>
      </section>
    </main>
  )
}
