import {readApiResponse,errorMessage} from '../components/apiErrors.js'
import { useEffect, useRef, useState } from 'react'
import AccountHeader from '../components/AccountHeader.jsx'

const formatLoad = (value) => value == null ? '—' : `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 }).format(value)} kg`

function InvitationDialog({ invitation, onClose, inviteField, copyMessage, onCopy }) {
  const dialog = useRef(null)
  useEffect(() => {
    dialog.current?.showModal()
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = overflow }
  }, [])
  return <dialog ref={dialog} className="invite-dialog" aria-labelledby="invite-dialog-title" onClose={onClose} onClick={(event) => { if (event.target === event.currentTarget) dialog.current.close() }}>
    <div className="invite-result-heading"><h2 id="invite-dialog-title">{invitation.nome ? `Convite para ${invitation.nome}` : 'Convidar aluno'}</h2><button type="button" className="invite-dialog-close" aria-label="Fechar convite" onClick={() => dialog.current.close()} autoFocus>✕</button></div>
    {invitation.pending ? <p role="status">Gerando link de convite…</p> : invitation.erro ? <p className="auth-message auth-error" role="alert">{invitation.erro}</p> : <>
      <p>Compartilhe este link com o aluno. Ele vale por {invitation.expiraEmDias} dias.</p>
      <label className="sr-only" htmlFor="invite-link">Link de convite</label><div className="invite-link-row"><input id="invite-link" ref={inviteField} value={invitation.convite} readOnly onFocus={(event) => event.target.select()} /><button className="dashboard-action" onClick={onCopy}>Copiar link</button></div>
      <p className="invite-copy-status" aria-live="polite">{copyMessage}</p>
    </>}
  </dialog>
}

export default function StudentsPage() {
  const [coach, setCoach] = useState(null)
  const [students, setStudents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [attempt, setAttempt] = useState(0)
  const [busyInvite, setBusyInvite] = useState(null)
  const [invitation, setInvitation] = useState(null)
  const [copyMessage, setCopyMessage] = useState('')
  const inviteField = useRef(null)

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError('')
      try {
        const me = await fetch('/api/auth/me', { signal: controller.signal, cache: 'no-store' })
        if (me.status === 401) { window.location.hash = '/entrar?erro=sessao'; return }
        const profile = await readApiResponse(me,'Não foi possível carregar sua área. Tente novamente.')
        if (profile.perfil === 'aluno') { window.location.hash = '/meus-treinos'; return }
        if (profile.perfil !== 'treinador') throw new Error('Não foi possível identificar sua área. Tente novamente.')
        const response = await fetch('/api/alunos', { signal: controller.signal, cache: 'no-store' })
        if (response.status === 401) { window.location.hash = '/entrar?erro=sessao'; return }
        const list = await readApiResponse(response,'Não foi possível carregar os alunos. Tente novamente.')
        if (!Array.isArray(list)) throw new Error('Não foi possível carregar os alunos.')
        if (list.some((student) => !Object.hasOwn(student, 'agachamento') || !Object.hasOwn(student, 'total'))) {
          throw new Error('Os indicadores dos alunos estão temporariamente indisponíveis. Atualize a lista; se o problema continuar, fale com o responsável pelo sistema.')
        }
        setCoach(profile)
        setStudents(list)
      } catch (failure) {
        if (failure.name !== 'AbortError') setError(errorMessage(failure))
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [attempt])

  async function post(path, body) {
    const response = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Power-System-Request': '1' }, body: JSON.stringify(body) })
    if (response.status === 401) { window.location.hash = '/entrar?erro=sessao'; throw new Error('Sua sessão terminou.') }
    return readApiResponse(response,'Não foi possível gerar o convite. Tente novamente.')
  }
  async function openInvitation(student = null) {
    setBusyInvite(student?.id ?? 'new')
    setCopyMessage('')
    setInvitation({ nome: student?.nome ?? null, pending: true })
    try {
      const result = await post(student ? `/api/alunos/${student.id}/convite` : '/api/convites', {})
      setInvitation((current) => current ? { ...result, nome: student?.nome ?? null } : null)
    } catch (failure) {
      setInvitation((current) => current ? { ...current, pending: false, erro: errorMessage(failure) } : null)
    } finally { setBusyInvite(null) }
  }
  async function copyInvite() {
    try { await navigator.clipboard.writeText(invitation.convite); setCopyMessage('Link copiado.') }
    catch { inviteField.current?.select(); setCopyMessage('Copie o link selecionado com Ctrl+C.') }
  }

  return <div className="site-shell dashboard">
    <AccountHeader account={coach} onError={setError} />
    <main className="dashboard-main">
      <p className="eyebrow">ÁREA DO TREINADOR</p>
      <div className="dashboard-heading"><div><h1>Meus alunos</h1><p>Envie o convite. O aluno entra com Google e confirma o próprio nome.</p></div><div className="dashboard-heading-actions"><button className="invite-table-button" onClick={() => setAttempt((value) => value + 1)} disabled={loading}>Atualizar lista</button><button className="dashboard-action" onClick={() => openInvitation()} disabled={!coach || busyInvite !== null}>{busyInvite === 'new' ? 'Gerando…' : '+ Convidar aluno'}</button></div></div>
      {error && <div className="auth-message auth-error" role="alert">{error} <button className="text-button" onClick={() => setAttempt((value) => value + 1)}>Atualizar lista</button></div>}
      {invitation && <InvitationDialog invitation={invitation} onClose={() => setInvitation(null)} inviteField={inviteField} copyMessage={copyMessage} onCopy={copyInvite} />}
      {loading ? <p className="table-state" role="status">Carregando sua área…</p> : !error && <div className="students-table-wrapper"><table className="students-table"><caption className="sr-only">Alunos do treinador conectado</caption><thead><tr><th scope="col">Nome do aluno</th><th scope="col">Agachamento</th><th scope="col">Supino</th><th scope="col">Terra</th><th scope="col">Total</th><th scope="col">Acesso</th></tr></thead><tbody>{students.length ? students.map((student) => <tr key={student.id}><td><a className="student-profile-link" href={`#/alunos/${student.id}`}>{student.nome} <span aria-hidden="true">↗</span></a>{student.dadosIncompletos&&<span className="student-data-warning" title="As máximas consideram apenas sessões legíveis">Histórico incompleto · {student.sessoesInvalidas} sessão(ões)</span>}</td><td>{formatLoad(student.agachamento)}</td><td>{formatLoad(student.supino)}</td><td>{formatLoad(student.terra)}</td><td className="student-total">{formatLoad(student.total)}</td><td>{student.acessoAtivo ? <span className="access-badge">Ativo</span> : <button className="invite-table-button" disabled={busyInvite !== null} onClick={() => openInvitation(student)}>{busyInvite === student.id ? 'Gerando…' : 'Gerar novo convite'}</button>}</td></tr>) : <tr><td colSpan="6" className="table-state"><strong>Nenhum aluno cadastrado.</strong><span>Use “Convidar aluno”. Ele aparecerá aqui depois de concluir o cadastro.</span></td></tr>}</tbody></table></div>}
      <p className="dashboard-footnote">Gere um link para cada novo aluno. Convites são de uso único e valem por 7 dias. O sistema não envia e-mails automaticamente.</p>
    </main>
  </div>
}
