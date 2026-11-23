import {readApiResponse,errorMessage} from '../components/apiErrors.js'
import { useEffect, useState } from 'react'

export default function CompleteStudentSignupPage() {
  const [name, setName] = useState('')
  const [weight, setWeight] = useState('')
  const [coach, setCoach] = useState('')
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setStatus('loading')
      setError('')
      try {
        const response = await fetch('/api/auth/cadastro-aluno', { signal: controller.signal, cache: 'no-store' })
        if ([401, 404].includes(response.status)) { setStatus('expired'); return }
        const result = await readApiResponse(response,'Não foi possível carregar seu cadastro. Tente novamente.')
        setCoach(result.treinador)
        setStatus('ready')
      } catch (failure) { if (failure.name !== 'AbortError') { setError(errorMessage(failure)); setStatus('error') } }
    }
    load()
    return () => controller.abort()
  }, [attempt])

  async function confirm(event) {
    event.preventDefault()
    if(!name.trim()||name.trim().length>120){setError('Informe seu nome, com até 120 caracteres.');return}
    if(weight!==''&&(!Number.isFinite(Number(weight))||Number(weight)<1||Number(weight)>500)){setError('Informe um peso entre 1 e 500 kg ou deixe o campo vazio.');return}
    setSaving(true)
    setError('')
    try {
      const response = await fetch('/api/auth/cadastro-aluno', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Power-System-Request': '1' }, body: JSON.stringify({ nome: name, peso: weight === '' ? null : Number(weight) }) })
      if ([401, 404].includes(response.status)) { setStatus('expired'); setSaving(false); return }
      await readApiResponse(response,'Não foi possível concluir seu cadastro. Revise os campos e tente novamente.')
      window.location.hash = '/meus-treinos'
    } catch (failure) { setError(errorMessage(failure)); setSaving(false) }
  }

  return <main className="invitation-page"><a className="brand" href="#/">POWER<span className="brand-light">SYSTEM</span></a><section className="invitation-card" aria-labelledby="complete-signup-title">
    <p className="eyebrow">CONCLUA SEU CADASTRO</p><h1 id="complete-signup-title">Como podemos<br />chamar você?</h1>
    {status === 'loading' ? <p role="status">Carregando…</p> : status === 'expired' ? <div role="alert"><p>Seu cadastro expirou ou o convite não está mais disponível. Abra o link recebido e entre com Google novamente.</p></div> : status === 'error' ? <div role="alert"><p>{error}</p><button className="dashboard-action" onClick={() => setAttempt((value) => value + 1)}>Tentar novamente</button></div> : <>
      <p>Sua conta Google foi confirmada. Preencha o nome que <strong>{coach}</strong> verá na lista de alunos. O peso é opcional e pode ser informado depois, na área Peso.</p>
      <form className="self-enrollment-form" onSubmit={confirm}>
        <label htmlFor="signup-name">Seu nome</label><input id="signup-name" name="nome" autoComplete="name" value={name} onChange={(event) => setName(event.target.value)} required maxLength={120} disabled={saving} autoFocus />
        <label htmlFor="signup-weight">Peso corporal atual (kg, opcional)</label><input id="signup-weight" type="number" inputMode="decimal" min="1" max="500" step="0.01" value={weight} onChange={(event) => setWeight(event.target.value)} disabled={saving} />
        <p className="signup-help">O DOTS ficará disponível depois de informar peso, gênero no perfil e registrar os três movimentos: Agachamento, Supino e Terra.</p>
        {error && <div className="auth-message auth-error" role="alert">{error}</div>}
        <button className="dashboard-action signup-confirm" disabled={saving}>{saving ? 'Confirmando…' : 'Confirmar e entrar'}</button>
      </form>
    </>}
  </section></main>
}
