import ExecutionNumberField from '../components/ExecutionNumberField.jsx'
import {validatedExecution,matchesPrescription} from '../components/executionNumbers.js'
import {metricAvailability} from '../components/metricAvailability.js'
import {readApiResponse,errorMessage} from '../components/apiErrors.js'
import { useEffect, useRef, useState } from 'react'
import { initializeExecution } from '../components/executionDraft.js'
import { trainingToday } from '../components/trainingDate.js'
import { calendarDay } from '../components/sessionDates.js'
import SessionAudit from '../components/SessionAudit.jsx'
import ExerciseRpePicker from '../components/ExerciseRpePicker.jsx'
import {isMainExercise,prescribedMaximum,reportedRpe,applyExerciseRpe} from '../components/exerciseRpe.js'
import usePrescriptionDraft from '../components/usePrescriptionDraft.js'
import {draftKey,draftMatches,listPrescriptionDrafts,writePrescriptionDraft,duplicatePrescription} from '../components/prescriptionDrafts.js'
import {reliableMutation,rememberReturn} from '../components/reliableWrites.js'
import AccountHeader from '../components/AccountHeader.jsx'
import StudentPersonalData from './StudentPersonalData.jsx'
import AthleteData from '../components/AthleteData.jsx'
import ProgressChart from '../components/ProgressChart.jsx'
import RecentRecordPicker from '../components/RecentRecordPicker.jsx'
import './StudentProfilePage.css'

const labels = { agachamento: 'Agachamento', supino: 'Supino', terra: 'Terra', total: 'Total SBD', volume: 'Volume semanal', peso: 'Peso corporal', dots: 'DOTS' }
const number = (value, digits = 1) => value == null ? '—' : new Intl.NumberFormat('pt-BR', { maximumFractionDigits: digits }).format(value)
const date = (value) => new Date(`${value}T12:00:00`)
const dayLabel = (value) => date(value).toLocaleDateString('pt-BR')
const isoDay = (value) => `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`
const todayLocal = trainingToday
const initialSet = () => ({ repeticoesPrevistas: 5, cargaPrevista: 0, repeticoes: null, carga: null, rpe: null })
const initialExercise = () => ({ nome: 'Agachamento', movimento: 'agachamento', series: [initialSet()] })
const emptySession = () => ({ id: null, dataTreino: todayLocal(), titulo: '', concluido: false, operacaoId:crypto.randomUUID(), exercicios: [initialExercise()], observacoes: '', video: '', prescricao: { tipoDia: 'treino', aquecimento: '', cargaMaximaDia: null, rpePrevisto: null } })

async function api(path, body, signal) {
  if(body!==undefined)return reliableMutation(path,body)
  const response = await fetch(path, { cache: 'no-store', signal, ...(body !== undefined ? { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Power-System-Request': '1' }, body: JSON.stringify(body) } : {}) })
  if(response.status===401){window.dispatchEvent(new Event('power-system-session-expired'));const failure=new Error('Sua sessão terminou. Entre novamente; seus dados continuam preservados.');failure.status=401;throw failure}
  return readApiResponse(response)
}

function useLockedSessionDialog(){
  const dialog = useRef(null)
  useEffect(() => {
    const y=window.scrollY, body=document.body, root=document.documentElement
    const old={overflow:body.style.overflow,position:body.style.position,top:body.style.top,width:body.style.width,rootOverflow:root.style.overflow}
    body.style.overflow='hidden';body.style.position='fixed';body.style.top=`-${y}px`;body.style.width='100%';root.style.overflow='hidden'
    dialog.current?.showModal()
    return ()=>{body.style.overflow=old.overflow;body.style.position=old.position;body.style.top=old.top;body.style.width=old.width;root.style.overflow=old.rootOverflow;window.scrollTo(0,y)}
  }, [])
  return dialog
}

function UnavailableSessionDialog({entry,onClose,studentId,editable,onSaved}){
 const dialog=useLockedSessionDialog(), session=entry.sessao
 const [reason,setReason]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('')
 return <dialog ref={dialog} className={`session-dialog ${editable?'student-session':''}`} onClose={onClose} onClick={event=>{if(event.target===event.currentTarget)dialog.current.close()}}><div className="session-dialog-head"><h2>{session.titulo}</h2><button className="athlete-button" onClick={()=>dialog.current.close()}>Voltar</button></div><div className="session-dialog-body"><p role="alert" className="auth-message auth-error">Esta sessão tem dados indisponíveis. Ela foi preservada, mas não entra nos indicadores enquanto não for recuperada.</p><p>{dayLabel(session.dataTreino)}</p><SessionAudit sessionId={session.id} studentId={studentId} studentView={editable}/>
 {editable?<p>Seu treinador pode verificar o histórico e recuperar uma versão válida.</p>:<form className="session-management" onSubmit={async event=>{event.preventDefault();setBusy(true);setError('');try{await api(`/api/alunos/${studentId}/treinos/${session.id}/recuperar`,{versao:session.versao,motivo:reason});onSaved?.();dialog.current.close()}catch(failure){setError(errorMessage(failure))}finally{setBusy(false)}}}><h3>Recuperar dados do treino</h3><p>Restaura exercícios, prescrição e conclusão da última versão válida no histórico. Datas, situação atual e histórico serão preservados. Se não houver uma versão válida, nenhuma carga será inventada.</p><label>Motivo<textarea required minLength={3} maxLength={1000} value={reason} onChange={event=>setReason(event.target.value)}/></label>{error&&<p role="alert">{error}</p>}<button className="dashboard-action" disabled={busy}>{busy?'Recuperando…':'Recuperar última versão válida'}</button></form>}</div></dialog>
}

export function SessionDialog(props){useEffect(()=>{const confirmed=event=>{if(props.studentId&&event.detail.path.startsWith(`/api/alunos/${props.studentId}/treinos/${props.entry.sessao.id}/`)){props.onSaved?.();props.onClose()}};window.addEventListener('power-system-write-confirmed',confirmed);return()=>window.removeEventListener('power-system-write-confirmed',confirmed)},[props.studentId,props.entry.sessao.id]);return props.entry.sessao.erroDados?<UnavailableSessionDialog {...props}/>:<ValidSessionDialog {...props}/>}

function ValidSessionDialog({ entry, onClose, studentId, editable = false, onSaved }) {
  const dialog=useLockedSessionDialog()
  const draftKey=`power-system-execution-${entry.sessao.id}`
  const originalStamp=JSON.stringify(entry.sessao)
  const draft=useRef(null)
  if(draft.current===null){try{const value=JSON.parse(sessionStorage.getItem(draftKey));draft.current=value?.stamp===originalStamp?value:{}}catch{draft.current={}}}
  const [session, setSession] = useState(()=>editable && draft.current.session || entry.sessao)
  const [saving, setSaving] = useState(false)
  const [failure, setFailure] = useState('')
  const [conflict,setConflict]=useState(false)
  const [management,setManagement]=useState(false)
  const [managementReason,setManagementReason]=useState('')
  const [reason,setReason]=useState(()=>draft.current.reason??'')
  const correcting=!!session.dataRealizada || entry.sessao.exercicios.some(e=>e.series.some(row=>row.carga!=null))
  const [confirming,setConfirming]=useState(false)
  const confirmation=useRef(null)
  const saved=useRef(false)
  const [hasChanges,setHasChanges] = useState(()=>editable && draft.current.hasChanges!=null?draft.current.hasChanges:entry.sessao.exercicios.some(exercise=>exercise.series.some(row=>(entry.sessao.concluido && row.carga==null) || (row.carga!=null && (!matchesPrescription(row))))))
  const executionInitialized=useRef(draft.current.initialized??(session.concluido || session.exercicios.some(e=>e.series.some(row=>row.carga!=null))))
  const editExecution=editable && confirming && hasChanges
  const showExecution=session.concluido || session.exercicios.some(e=>e.series.some(row=>row.carga!=null)) || !editable
  const [rpeActions,setRpeActions]=useState(()=>editable?draft.current.rpeActions??{}:{})
  useEffect(()=>{if(editable && !saved.current){try{sessionStorage.setItem(draftKey,JSON.stringify({stamp:originalStamp,session,rpeActions,hasChanges,reason,initialized:executionInitialized.current}))}catch{}}},[session,rpeActions,hasChanges,reason,editable,draftKey,originalStamp])
  const canEdit = editable && (session.situacao??'ativa')==='ativa' && session.prescricao?.tipoDia!=='descanso'
  function changeSet(exerciseIndex,setIndex,patch) {
    setSession(previous=>({...previous,exercicios:previous.exercicios.map((exercise,index)=>index!==exerciseIndex?exercise:{...exercise,series:exercise.series.map((row,index)=>index!==setIndex?row:{...row,...patch})})}))
  }
  useEffect(()=>{const confirmed=event=>{if(event.detail.path===`/api/auth/treinos/${session.id}`&&event.detail.payload.versao===session.versao){saved.current=true;try{sessionStorage.removeItem(draftKey)}catch{};onSaved?.();dialog.current?.close()}};window.addEventListener('power-system-write-confirmed',confirmed);return()=>window.removeEventListener('power-system-write-confirmed',confirmed)},[session.id,session.versao])
  async function saveExecution() {
    setSaving(true); setFailure('')
    try {
      if(correcting && reason.trim().length<3)throw new Error('Informe o motivo da correção (pelo menos 3 caracteres).')
      const payload={...session,motivoAlteracao:reason.trim()||null,concluido:true,exercicios:session.exercicios.map((exercise,index)=>applyExerciseRpe(hasChanges?validatedExecution(exercise):exercise,hasChanges,isMainExercise(exercise)?rpeActions[index]:undefined))}
      await api(`/api/auth/treinos/${session.id}`,payload); saved.current=true;try{sessionStorage.removeItem(draftKey)}catch{}; onSaved?.(); dialog.current.close() }
    catch(error) { setFailure(errorMessage(error));setConflict(error.status===409) }
    finally { setSaving(false) }
  }
  return <dialog ref={dialog} className={`session-dialog ${editable?'student-session':''}`} onClose={onClose} onClick={(event) => { if (event.target === event.currentTarget) dialog.current.close() }}>
    <div className="session-dialog-head"><div><p className="eyebrow">RESUMO DA SESSÃO · {dayLabel(session.dataTreino)}</p><h2>{session.titulo}</h2></div><button autoFocus className="athlete-button" onClick={() => dialog.current.close()} aria-label="Voltar e fechar resumo">{editable?'Voltar':'✕'}</button></div>
    <div className="session-dialog-body">
    <span className={`session-status ${entry.status}`}>{entry.status === 'cancelada'?'Prescrição cancelada':entry.status === 'anulada'?'Execução anulada':entry.status === 'parcial' ? 'Parcial' : entry.status === 'concluido_alterado' ? 'Concluído com alterações' : entry.status === 'concluido' ? 'Concluído conforme prescrito' : entry.status === 'perdido' ? 'Não concluído' : entry.status === 'descanso' ? 'Descanso' : 'Agendado'}</span>
    <div className="session-dates"><span>Prevista: <strong>{dayLabel(session.dataPrevista||session.dataTreino)}</strong></span><span>Realizada: <strong>{session.dataRealizada?dayLabel(session.dataRealizada):'Ainda não realizada'}</strong></span></div>
    {['cancelada','anulada'].includes(session.situacao)&&<p className="athlete-note">{session.situacao==='anulada'?'Execução preservada no histórico e excluída dos indicadores.':'Prescrição preservada no histórico; não aparece entre os próximos treinos.'}</p>}
    {session.concluido && <p className="athlete-note">{session.seriesRealizadas} de {session.seriesPrescritas} séries realizadas</p>}
    {session.prescricao?.aquecimento && <section className="session-notes"><h3>Aquecimento</h3><p>{session.prescricao.aquecimento}</p></section>}
    {session.prescricao?.rpePrevisto!=null&&<p className="athlete-note">RPE previsto da sessão (registro anterior): {number(session.prescricao.rpePrevisto)}. Novas metas são definidas por exercício.</p>}
    {failure && <div className="auth-message auth-error" role="alert">{failure}{conflict&&<button className="athlete-button" disabled={saving} onClick={async()=>{try{const result=await api('/api/auth/perfil');const fresh=result.calendario.find(item=>item.sessao.id===session.id)?.sessao;if(!fresh)throw new Error('Sessão não encontrada.');setSession(fresh);setConfirming(false);setHasChanges(fresh.estadoExecucao!=='concluido'&&fresh.concluido);executionInitialized.current=fresh.concluido||fresh.exercicios.some(e=>e.series.some(row=>row.carga!=null));setRpeActions({});setConflict(false);setFailure('')}catch(error){setFailure(errorMessage(error))}}}>Recarregar sessão e descartar meus ajustes</button>}</div>}
    {canEdit && confirming && <section ref={confirmation} className="session-completion"><h3>Confirmar conclusão</h3>
      {!entry.sessao.concluido && <p className="athlete-note">{session.dataTreino>todayLocal()?'Você pode adiantar este treino. ':''}Ao confirmar, a sessão será registrada em {dayLabel(todayLocal())}.</p>}
      <label className="execution-check"><input type="checkbox" checked={hasChanges} disabled={saving} onChange={event=>{
        const checked=event.target.checked
        if(!checked && session.exercicios.some(e=>e.series.some(row=>row.carga==null || !matchesPrescription(row)))){setFailure('Há diferenças na execução. Seus ajustes foram mantidos. Para removê-los, use Restaurar ao prescrito.');return}
        setHasChanges(checked)
        if(checked && !executionInitialized.current) {setSession(previous=>initializeExecution(previous,false));executionInitialized.current=true;}
      }} />Houve mudanças na execução</label>
      {hasChanges && <button type="button" className="athlete-button" disabled={saving} onClick={()=>{setSession(previous=>({...previous,exercicios:previous.exercicios.map(e=>({...e,series:e.series.map(row=>({...row,carga:row.cargaPrevista,repeticoes:row.repeticoesPrevistas}))}))}));setHasChanges(false);setFailure('');executionInitialized.current=true}}>Restaurar execução ao prescrito</button>}
      {correcting&&<label className="session-correction-reason">Motivo da correção<textarea minLength={3} maxLength={1000} value={reason} onChange={event=>setReason(event.target.value)} placeholder="Explique o que estava incorreto" rows={3}/></label>}

    </section>}
    {session.exercicios.map((exercise,index)=><section className="session-exercise" key={index}><details open={index===0 || (confirming && (hasChanges||isMainExercise(exercise)))}><summary>{exercise.nome}</summary>{isMainExercise(exercise)&&<><div className="session-metrics"><div><span>Máxima prevista · {exercise.nome}</span><strong>{number(prescribedMaximum(exercise))} <small>kg</small></strong></div><div><span>RPE previsto deste exercício</span><strong>{number(exercise.rpePrevisto)}</strong></div><div><span>RPE real registrado</span><strong>{reportedRpe(exercise).length?reportedRpe(exercise).map(value=>number(value)).join(' / '):'Não relatado'}</strong></div></div>{canEdit&&confirming&&<ExerciseRpePicker exercise={exercise} hasChanges={hasChanges} action={rpeActions[index]} disabled={saving} onChange={action=>setRpeActions(previous=>({...previous,[index]:action}))}/>}</>}<div className="athlete-table-scroll"><table className={editExecution?'session-table-adjusting':undefined}><thead><tr><th>Série</th><th>Treino</th>{(showExecution || editExecution)&&<th>Execução</th>}</tr></thead><tbody>{(editExecution?exercise.series.map((set,i)=>({...set,count:1,index:i})):exercise.series.reduce((rows,set,i)=>{const last=rows.at(-1);if(last && last.repeticoesPrevistas===set.repeticoesPrevistas && last.cargaPrevista===set.cargaPrevista && (last.carga===set.carga && last.repeticoes===set.repeticoes))last.count++;else rows.push({...set,count:1,index:i});return rows},[])).map((set)=>{const setIndex=set.index;return <tr key={setIndex}><td>{setIndex+1}</td><td>{set.count>1?`${set.count} séries · `:''}{set.repeticoesPrevistas} × {number(set.cargaPrevista)} kg</td>
      {editExecution ? <td><div className="execution-controls"><label>Situação<select disabled={saving} value={set.carga==null?'nao':'sim'} onChange={event=>changeSet(index,setIndex,event.target.value==='nao'?{carga:null,repeticoes:null,rpe:null}:{carga:set.cargaPrevista,repeticoes:set.repeticoesPrevistas})}><option value="sim">Realizada</option><option value="nao">Não realizada</option></select></label>
        {set.carga!=null&&<div className="execution-adjust"><ExecutionNumberField label="Kg feitos" kind="carga" disabled={saving} value={set.carga} onChange={value=>changeSet(index,setIndex,{carga:value})}/><ExecutionNumberField label="Repetições" kind="repeticoes" disabled={saving} value={set.repeticoes} onChange={value=>changeSet(index,setIndex,{repeticoes:value})}/></div>}
      </div></td> : showExecution && <td>{set.carga==null?'Não realizada':set.carga===set.cargaPrevista && set.repeticoes===set.repeticoesPrevistas?<span className="execution-confirmed">Conforme prescrito</span>:<span className="execution-confirmed">{set.repeticoes} × {number(set.carga)} kg</span>}</td>}
    </tr>})}</tbody></table></div></details></section>)}

    <section className="session-notes"><details><summary>Observações do treinador</summary><p>{session.observacoes || 'Nenhuma observação registrada.'}</p>{session.video && <a href={session.video} target="_blank" rel="noopener noreferrer">Assistir ao vídeo ↗</a>}</details></section>
    <SessionAudit key={`${session.id}-${session.versao}`} sessionId={session.id} studentId={studentId} studentView={editable}/>
    {!editable && (session.situacao??'ativa')==='ativa' && <section className="session-management"><button type="button" className="athlete-button" aria-expanded={management} onClick={()=>setManagement(value=>!value)}>{session.exercicios.some(e=>e.series.some(row=>row.carga!=null))?'Anular execução':'Cancelar prescrição'}</button>
      {management&&<form onSubmit={async event=>{event.preventDefault();setSaving(true);setFailure('');try{const action=session.exercicios.some(e=>e.series.some(row=>row.carga!=null))?'anular':'cancelar';await api(`/api/alunos/${studentId}/treinos/${session.id}/${action}`,{versao:session.versao,motivo:managementReason});onSaved?.();dialog.current.close()}catch(error){setFailure(errorMessage(error))}finally{setSaving(false)}}}><p>O registro será mantido no histórico. {session.exercicios.some(e=>e.series.some(row=>row.carga!=null))?'A execução deixará de contar nos PRs, Total, DOTS e volume.':'O treino deixará de aparecer como agendado ou faltante.'}</p><label>Motivo obrigatório<textarea required minLength={3} maxLength={1000} value={managementReason} onChange={event=>setManagementReason(event.target.value)} rows={3}/></label><button className="dashboard-action" disabled={saving}>{saving?'Salvando…':session.exercicios.some(e=>e.series.some(row=>row.carga!=null))?'Confirmar anulação da execução':'Confirmar cancelamento da prescrição'}</button></form>}
    </section>}
    </div>
    {canEdit && <div className="session-actions"><button className="dashboard-action" disabled={saving} onClick={()=>{if(confirming)saveExecution();else{setConfirming(true);requestAnimationFrame(()=>confirmation.current?.scrollIntoView({block:'start',behavior:'smooth'}))}}}>{saving?'Salvando…':confirming?(session.dataTreino>todayLocal()?'Confirmar adiantamento':'Confirmar conclusão'):entry.sessao.concluido?'Corrigir registro':'Concluir treino'}</button></div>}
    {!editable && (session.situacao??'ativa')==='ativa' && <a className="dashboard-action" href={`#/alunos/${studentId}/treino?sessao=${session.id}`}>Editar sessão</a>}
  </dialog>
}

function UnavailableSessions({issues,studentId,studentView,onSaved}){const [selected,setSelected]=useState(null);return <><ul>{issues.map(issue=><li key={issue.id}><button className="athlete-button" onClick={()=>setSelected(issue)}>{dayLabel(issue.dataTreino)} · {issue.titulo} · Ver opções</button></li>)}</ul>{selected&&<SessionDialog entry={{sessao:selected,status:'indisponivel'}} studentId={studentId} editable={studentView} onSaved={onSaved} onClose={()=>setSelected(null)}/>}</>}

function TrainingCalendar({ entries, studentId, today, studentView = false, onSaved }) {
  const [calendarBasis,setCalendarBasis]=useState('realizada')
  const calendarEntries=entries.map(entry=>({...entry,sessao:{...entry.sessao,dataTreino:calendarDay(entry.sessao,calendarBasis)}}))
  const [month, setMonth] = useState(() => date(today.slice(0, 7) + '-01'))
  const [selected, setSelected] = useState(null)
  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const offset = (first.getDay() + 6) % 7
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  return <section className="athlete-panel calendar-panel">
    <div className="athlete-section-heading"><div><p className="eyebrow">CONSISTÊNCIA</p><h2>Calendário de treinos</h2></div><div className="calendar-controls"><button className="athlete-button" aria-label="Mês anterior" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}>←</button><strong aria-live="polite">{month.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })}</strong><button className="athlete-button" aria-label="Próximo mês" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}>→</button></div></div>
    <label className="calendar-basis">Organizar por<select value={calendarBasis} onChange={event=>setCalendarBasis(event.target.value)}><option value="realizada">Realização (agendados na data prevista)</option><option value="prevista">Planejamento original</option></select></label>
    <div className="calendar-legend"><span className="concluido">Concluído</span><span className="parcial">Parcial</span><span className="agendado">Agendado</span><span className="perdido">Não concluído</span><span>Descanso</span></div>
    <div className="training-calendar" role="group" aria-label="Sessões do mês">
      {['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'].map((day) => <div className="calendar-weekday" key={day}>{day}</div>)}
      {Array.from({ length: offset }, (_, index) => <div className="calendar-day outside" key={`blank-${index}`} />)}
      {Array.from({ length: days }, (_, index) => { const day = isoDay(new Date(month.getFullYear(), month.getMonth(), index + 1)); const sessions = calendarEntries.filter((entry) => entry.sessao.dataTreino === day); return <div key={day} className={`calendar-day ${day === today ? 'is-today' : ''}`}><span className="calendar-day-number">{index + 1}{day === today && <small>Hoje</small>}</span>{sessions.map((entry) => <div key={entry.sessao.id} className="calendar-entry"><button className={`calendar-session ${entry.status}`} title={entry.sessao.titulo} onClick={() => setSelected(entries.find(original=>original.sessao.id===entry.sessao.id)||entry)}><span aria-hidden="true">●</span><span>{entry.sessao.titulo}</span><span className="sr-only">{dayLabel(day)}, {entry.status}</span></button>{!studentView && (entry.sessao.situacao??'ativa')==='ativa' && <a className="calendar-edit" href={`#/alunos/${studentId}/treino?sessao=${entry.sessao.id}`} aria-label={`Editar ${entry.sessao.titulo} de ${dayLabel(day)}`} title="Editar sessão">✎</a>}</div>)}</div> })}
    </div>
    {!calendarEntries.some((entry) => entry.sessao.dataTreino.startsWith(isoDay(month).slice(0, 7))) && <p className="calendar-empty">Nenhum treino neste mês. {!studentView && <a href={`#/alunos/${studentId}/treino`}>Prescrever uma sessão →</a>}</p>}
    {selected && <SessionDialog entry={selected} onClose={() => setSelected(null)} studentId={studentId} editable={studentView} onSaved={onSaved} />}
  </section>
}

function StudentAgenda({entries,today,onSaved}) {
 const [basis,setBasis]=useState('realizada')
 const [mode,setMode]=useState('semana'),[offset,setOffset]=useState(0),[selected,setSelected]=useState(null)
 const start=date(today);start.setDate(start.getDate()-((start.getDay()+6)%7)+offset*7)
 const days=Array.from({length:7},(_,index)=>{const d=new Date(start);d.setDate(d.getDate()+index);return isoDay(d)})
 return <section className="student-agenda"><div className="agenda-heading"><h2>Sua agenda</h2><div className="agenda-toggle">{['semana','mês'].map(value=><button key={value} aria-pressed={mode===value} onClick={()=>setMode(value)}>{value==='semana'?'Semana':'Mês'}</button>)}</div></div>
 {mode==='mês'?<TrainingCalendar entries={entries} today={today} studentView onSaved={onSaved}/>:<div className="athlete-panel"><label className="calendar-basis">Organizar por<select value={basis} onChange={event=>setBasis(event.target.value)}><option value="realizada">Realização (agendados na data prevista)</option><option value="prevista">Planejamento original</option></select></label><div className="calendar-controls"><button className="athlete-button" aria-label="Semana anterior" onClick={()=>setOffset(value=>value-1)}>←</button><button className="athlete-button" onClick={()=>setOffset(0)}>Esta semana</button><button className="athlete-button" aria-label="Próxima semana" onClick={()=>setOffset(value=>value+1)}>→</button></div><p className="week-range">{dayLabel(days[0])} — {dayLabel(days[6])}</p><div className="week-agenda">{days.map(day=><div className={`week-day ${day===today?'today':''}`} key={day}><div><strong>{date(day).toLocaleDateString('pt-BR',{weekday:'short'})}</strong><span>{dayLabel(day)}</span></div><div>{entries.filter(entry=>calendarDay(entry.sessao,basis)===day).map(entry=><button className={`week-session ${entry.status}`} key={entry.sessao.id} onClick={()=>setSelected(entry)}><strong>{entry.sessao.titulo}</strong><span>{entry.status==='indisponivel'?'Dados indisponíveis':entry.status==='cancelada'?'Cancelada':entry.status==='anulada'?'Anulada':entry.status==='parcial'?'Parcial':entry.status==='concluido_alterado'?'✓ Concluído com alterações':entry.status==='concluido'?'✓ Concluído':entry.status==='perdido'?'Não concluído':entry.status==='descanso'?'Descanso':'Agendado'} →</span></button>)}{!entries.some(entry=>calendarDay(entry.sessao,basis)===day)&&<span className="athlete-note">Sem treino previsto</span>}</div></div>)}</div></div>}
 {selected&&<SessionDialog entry={selected} editable onSaved={onSaved} onClose={()=>setSelected(null)}/>}
 </section>
}

function UpcomingWorkouts({entries,today,onSaved}) {
  const [selected,setSelected]=useState(null)
  const todays=entries.filter(entry=>entry.sessao.dataTreino===today && entry.status!=='descanso' && !['cancelada','anulada','indisponivel'].includes(entry.status))
  const next=entries.filter(entry=>entry.sessao.dataTreino>today && !entry.sessao.concluido && entry.status!=='descanso' && !['cancelada','anulada','indisponivel'].includes(entry.status)).sort((a,b)=>a.sessao.dataTreino.localeCompare(b.sessao.dataTreino)||a.sessao.id-b.sessao.id).slice(0,5)
  return <section className="athlete-panel"><p className="eyebrow">SEU PRÓXIMO PASSO</p><h2>Treino de hoje</h2><div className="today-workouts">{todays.length?todays.map(entry=><button className={`today-workout ${entry.sessao.estadoExecucao??(entry.sessao.concluido?'concluido':'')}`} key={entry.sessao.id} onClick={()=>setSelected(entry)}><span>{entry.sessao.estadoExecucao==='parcial'?'Parcial · hoje':entry.sessao.estadoExecucao==='concluido_alterado'?'✓ Concluído com alterações':entry.sessao.concluido?'✓ Concluído hoje':'Hoje · '+dayLabel(today)}</span><strong>{entry.sessao.titulo}</strong><span>{entry.sessao.concluido?'Ver resumo':'Abrir treino'} →</span></button>):<p className="athlete-note">Nenhum treino previsto para hoje. Veja sua próxima sessão abaixo.</p>}</div><h3>Próximos treinos</h3>
    {next.length?<div className="upcoming-workouts">{next.map(entry=><button key={entry.sessao.id} className="upcoming-workout" onClick={()=>setSelected(entry)}><span>{entry.sessao.dataTreino===today?'Hoje':dayLabel(entry.sessao.dataTreino)}</span><strong>{entry.sessao.titulo}</strong><span>Ver treino →</span></button>)}</div>:<p className="athlete-note">Nenhum próximo treino prescrito.</p>}
    {selected && <SessionDialog entry={selected} editable onSaved={onSaved} onClose={()=>setSelected(null)}/>}
  </section>
}

const hasExecution = (set) => set.carga!=null || set.repeticoes!=null || set.rpe!=null || (set.execucoes||[]).some(row=>row.carga!=null||row.repeticoes!=null||row.rpe!=null)
const totalSeries = (exercise) => exercise.series.reduce((sum,row)=>sum+(row.quantidade??1),0)
const minimumQuantity = (row) => Math.max(1,(row.execucoes||[]).reduce((minimum,set,index)=>hasExecution(set)?index+1:minimum,1))
const newPrescribedSet = (template) => ({...initialSet(),repeticoesPrevistas:template?.repeticoesPrevistas??5,cargaPrevista:template?.cargaPrevista??0})
function editableSession(original) {
  const copy=structuredClone(original)
  const prescription=copy.prescricao||emptySession().prescricao
  const notes=copy.observacoes||''
  copy.observacoes=prescription.aquecimento && !notes.includes(prescription.aquecimento) ? [prescription.aquecimento,notes].filter(Boolean).join('\n\n') : notes
  copy.exercicios=copy.exercicios.map(exercise=>{
    const sizes=exercise.agrupamentos||exercise.series.map(()=>1)
    let offset=0
    const rows=sizes.map(quantidade=>{
      const execucoes=exercise.series.slice(offset,offset+quantidade);offset+=quantidade
      return {...execucoes[0],quantidade,execucoes}
    })
    return {...exercise,series:rows}
  })
  copy.prescricao={...prescription,aquecimento:''}
  return copy
}

export function TrainingEditor({ data, studentId, coachId, onSaved, query }) {
  const params=new URLSearchParams(query),sessionId=params.get('sessao'),slot=params.get('rascunho')||'default'
  const routed = data.calendario.find(entry=>String(entry.sessao.id)===sessionId)?.sessao
  const originalRef=useRef(null)
  if(!originalRef.current)originalRef.current=routed&&!routed.erroDados?editableSession(routed):emptySession()
  const original=originalRef.current
  const storageKey=draftKey(coachId,studentId,sessionId,slot)
  const draft=usePrescriptionDraft({storageKey,slot,original,autoResume:params.get('retomar')==='1'})
  const {session,setSession}=draft
  const existing=data.calendario.find(entry=>entry.sessao.id===session.id)?.sessao
  const [choosingCopy,setChoosingCopy]=useState(false),[choosingDraft,setChoosingDraft]=useState(false),[draftRecords,setDraftRecords]=useState([])
  function freshSlot(){return crypto.randomUUID()}
  function copySession(source){
    try{draft.persist();const nextSlot=freshSlot(),copy=duplicatePrescription(source);writePrescriptionDraft(window.localStorage,draftKey(coachId,studentId,null,nextSlot),copy,nextSlot);window.location.hash=`/alunos/${studentId}/treino?rascunho=${nextSlot}&retomar=1`}
    catch{setError('Não foi possível preparar a cópia neste navegador. Sua sessão original foi preservada.')}
  }
  function openDrafts(){try{draft.persist();setDraftRecords(listPrescriptionDrafts(window.localStorage,coachId,studentId));setChoosingDraft(value=>!value)}catch{setError('Não foi possível consultar os rascunhos neste navegador.')}}
  function openDraft(record){try{draft.persist();const destination=record.session.id?`sessao=${record.session.id}`:`rascunho=${encodeURIComponent(record.slot)}`;window.location.hash=`/alunos/${studentId}/treino?${destination}&retomar=1`;setChoosingDraft(false)}catch{setError('Não foi possível preservar sua edição atual. Salve antes de trocar de rascunho.')}}
  useEffect(()=>{const confirmed=event=>{const value=event.detail.payload;if(event.detail.path===`/api/alunos/${studentId}/treinos`&&(session.id?value.id===session.id&&value.versao===session.versao:value.operacaoId===session.operacaoId)){draft.finish();onSaved();window.location.hash=`/alunos/${studentId}`}};window.addEventListener('power-system-write-confirmed',confirmed);return()=>window.removeEventListener('power-system-write-confirmed',confirmed)},[studentId,session.id,session.versao,session.operacaoId])
  const lockedIdentity=!!existing?.exercicios?.some(exercise=>exercise.series.some(row=>row.carga!=null))
  const [conflict,setConflict]=useState(false)
  const [choosingSession, setChoosingSession] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  function editExercise(index, field, value) { setSession((current) => ({ ...current, exercicios: current.exercicios.map((exercise, i) => i === index ? { ...exercise, [field]: value } : exercise) })) }
  function editSet(exerciseIndex, setIndex, field, value) { editExercise(exerciseIndex, 'series', session.exercicios[exerciseIndex].series.map((set, index) => index === setIndex ? { ...set, [field]: value === '' ? null : Number(value) } : set)) }
  async function save(event, type) {
    event.preventDefault(); setBusy(true); setError(''); setMessage('')
    try {
      if(lockedIdentity && (session.motivoAlteracao||'').trim().length<3)throw new Error('Informe o motivo da alteração (pelo menos 3 caracteres).')
      const rest = session.prescricao.tipoDia === 'descanso'
      const payload = { ...session, exercicios: rest ? [] : session.exercicios.map(exercise=>({...exercise,agrupamentos:exercise.series.map(row=>row.quantidade??1),series:exercise.series.flatMap(row=>Array.from({length:row.quantidade??1},(_,index)=>({...initialSet(),...(row.execucoes?.[index]||{repeticoes:null,carga:null,rpe:null}),repeticoesPrevistas:row.repeticoesPrevistas,cargaPrevista:row.cargaPrevista})))})), prescricao: { ...session.prescricao, cargaMaximaDia: rest ? null : Math.max(0,...session.exercicios.flatMap(exercise=>exercise.series.map(row=>Number(row.cargaPrevista)||0))), rpePrevisto: rest ? null : session.prescricao.rpePrevisto } }
      await api(`/api/alunos/${studentId}/treinos`, payload)
      draft.finish()
      onSaved()
      window.location.hash = `/alunos/${studentId}`
    } catch (failure) { setError(errorMessage(failure));setConflict(failure.status===409) } finally { setBusy(false) }
  }
  if(existing?.erroDados)return <div role="alert" className="auth-message auth-error">Sessão indisponível. Volte ao perfil para consultar o histórico e as opções de recuperação.{draft.pending&&<button className="athlete-button" onClick={()=>copySession(draft.pending.session)}>Usar rascunho como nova sessão</button>}</div>
  if(existing && existing.situacao && existing.situacao!=='ativa')return <p role="alert" className="auth-message">Esta sessão foi cancelada ou anulada. Consulte o histórico no calendário. <button className="athlete-button" onClick={()=>copySession(draft.pending?.session||editableSession(existing))}>Usar prescrição como nova sessão</button></p>
  if(sessionId && !routed)return <div role="alert" className="auth-message auth-error">Sessão não encontrada. <a href={`#/alunos/${studentId}`}>Voltar ao perfil</a></div>
  return <div className="training-editor">
    {error && <div role="alert" className="auth-message auth-error">{error}{conflict&&<><button type="button" className="athlete-button" disabled={busy} onClick={async()=>{try{const latest=await api(`/api/alunos/${studentId}/perfil`);const fresh=latest.calendario.find(item=>item.sessao.id===session.id)?.sessao;if(!fresh)throw new Error('Sessão não encontrada.');if(draft.discard(editableSession(fresh))){setError('');setConflict(false)}}catch(failure){setError(errorMessage(failure))}}}>Recarregar sessão e descartar minha edição</button><button type="button" className="athlete-button" onClick={()=>copySession(session)}>Usar minha edição como nova sessão</button></>}</div>}{message && <p role="status" className="editor-success">{message}</p>}
    {draft.status&&<p role="status" className={draft.storageError?'auth-message auth-error':'athlete-note'}>{draft.status}</p>}
    {draft.blockedDraft&&<div className="auth-message auth-error">O rascunho salvo não pode ser lido. Ele não será sobrescrito. <button className="athlete-button" onClick={()=>draft.discard()}>Descartar rascunho indisponível</button></div>}
    {draft.pending&&<section className="prescription-draft-banner" role="status"><h3>Existe um rascunho salvo</h3><p>{draft.pending.session.titulo||'Sessão sem nome'} · {new Date(draft.pending.savedAt).toLocaleString('pt-BR')}</p>{draftMatches(draft.pending,routed)?<><p>Recupere para continuar ou descarte para usar os dados atuais.</p><button className="dashboard-action" onClick={()=>draft.recover(routed&&!routed.erroDados?editableSession(routed):original)}>Recuperar rascunho</button></>:<><p>Esta sessão foi alterada no servidor. O rascunho antigo foi preservado e não será aplicado sobre a versão atual.</p><button className="dashboard-action" onClick={()=>copySession(draft.pending.session)}>Usar rascunho como nova sessão</button></>} <button className="athlete-button" onClick={()=>draft.discard(routed&&!routed.erroDados?editableSession(routed):emptySession())}>Descartar rascunho</button></section>}
    <div className="session-mode-actions"><button type="button" className="athlete-button" disabled={busy} onClick={openDrafts}>Rascunhos deste aluno</button>{draft.dirty&&!draft.pending&&<button type="button" className="athlete-button" disabled={busy} onClick={()=>draft.discard(routed&&!routed.erroDados?editableSession(routed):emptySession())}>Descartar edição e voltar ao original</button>}</div>
    {choosingDraft&&<RecentRecordPicker label="Buscar rascunho" placeholder="Nome ou data" records={draftRecords.map(record=>({id:record.key,date:record.savedAt.slice(0,10),title:record.session.titulo||'Sessão sem nome',subtitle:record.session.id?'Edição de sessão existente':'Nova sessão',record}))} onSelect={item=>openDraft(item.record)} disabled={busy}/>}
    <form className="athlete-panel session-editor" onSubmit={(event) => save(event, 'treinos')}><fieldset className="prescription-fields" disabled={busy||!!draft.pending||draft.blockedDraft}><div className="athlete-section-heading"><div><p className="eyebrow">PLANILHA DO ALUNO</p><h2>{session.id ? 'Editar sessão' : 'Prescrever nova sessão'}</h2></div></div>
      <div className="session-mode-actions"><button type="button" className="athlete-button" aria-pressed={!session.id && !choosingSession} disabled={busy} onClick={() => {try{draft.persist();window.location.hash=`/alunos/${studentId}/treino?rascunho=${freshSlot()}`}catch{setError('Não foi possível preservar o rascunho. Salve antes de iniciar outra sessão.')}}}>+ Nova sessão</button><button type="button" className="athlete-button" aria-expanded={choosingSession} disabled={busy} onClick={() => setChoosingSession(value=>!value)}>Editar sessão existente</button><button type="button" className="athlete-button" aria-expanded={choosingCopy} onClick={()=>setChoosingCopy(value=>!value)}>Duplicar sessão existente</button>{session.titulo&&<button type="button" className="athlete-button" onClick={()=>copySession(session)}>Duplicar esta prescrição</button>}</div>
      {choosingCopy&&<RecentRecordPicker label="Escolher prescrição para copiar" placeholder="Data, exercício ou nome" records={data.calendario.filter(entry=>!entry.sessao.erroDados).map(({sessao})=>({id:sessao.id,date:sessao.dataPrevista||sessao.dataTreino,title:sessao.titulo,subtitle:'Copiar apenas a prescrição',session:sessao}))} onSelect={record=>copySession(editableSession(record.session))}/>}
      {slot!=='default'&&!session.id&&<p className="athlete-note">Nova prescrição independente. Escolha a data e revise antes de salvar. A sessão de origem não será alterada.</p>}
      {choosingSession && <RecentRecordPicker label="Buscar sessão existente" placeholder="Data, movimento, Volume, Força ou Deload" records={data.calendario.map(({sessao})=>({id:sessao.id,date:sessao.dataTreino,title:sessao.titulo,subtitle:sessao.erroDados?'Dados indisponíveis':sessao.prescricao?.tipoDia==='descanso'?'Descanso':sessao.exercicios.map(exercise=>exercise.nome).join(' · ')}))} onSelect={record=>{try{draft.persist();setChoosingSession(false);window.location.hash=`/alunos/${studentId}/treino?sessao=${record.id}`}catch{setError('Não foi possível preservar a edição atual. Salve antes de trocar de sessão.')}}} />}
      {lockedIdentity && <p className="athlete-note">Este treino já tem execução. Exercícios, quantidade de séries e data estão protegidos. Alterar a prescrição não modifica as cargas realizadas pelo aluno.</p>}
      {session.id && <p className="editing-record-label">Editando: {dayLabel(session.dataTreino)} · {session.titulo}</p>}
      <div className="editor-grid"><label>Nome da sessão<input required maxLength={120} placeholder="Treino A — Agachamento" value={session.titulo} onChange={(event) => setSession({ ...session, titulo: event.target.value })} /></label><label>Data<input type="date" disabled={lockedIdentity} required value={session.dataTreino} onChange={(event) => setSession({ ...session, dataTreino: event.target.value })} /></label></div>
      {lockedIdentity&&<label className="prescription-notes">Motivo da alteração da prescrição<textarea required minLength={3} maxLength={1000} rows={2} value={session.motivoAlteracao||''} onChange={event=>setSession({...session,motivoAlteracao:event.target.value})}/></label>}
      <label className="prescription-notes">Observações<textarea rows={4} maxLength={4000} value={session.observacoes} onChange={event=>setSession({...session,observacoes:event.target.value})} placeholder="Anotações gerais e orientações para este treino" /></label>
      {session.prescricao.tipoDia !== 'descanso' && <>
      {session.exercicios.map((exercise, exerciseIndex) => <fieldset className="exercise-editor" key={exerciseIndex}><legend>Exercício {exerciseIndex + 1}</legend><div className="editor-grid"><label>Exercício<input disabled={lockedIdentity} required value={exercise.nome} maxLength={120} onChange={(event) => editExercise(exerciseIndex, 'nome', event.target.value)} /></label><label>Movimento<select disabled={lockedIdentity} value={exercise.movimento} onChange={(event) => editExercise(exerciseIndex, 'movimento', event.target.value)}>{['agachamento', 'supino', 'terra', 'acessorio'].map((movement) => <option key={movement} value={movement}>{labels[movement] || 'Acessório'}</option>)}</select></label>{isMainExercise(exercise)&&<label>RPE previsto nas séries mais pesadas<input type="number" min="1" max="10" step="0.5" value={exercise.rpePrevisto??''} onChange={event=>editExercise(exerciseIndex,'rpePrevisto',event.target.value===''?null:Number(event.target.value))}/></label>}</div>
        <div className="athlete-table-scroll"><table className="sets-editor prescription-table"><thead><tr><th>Número da série</th><th>Número de séries</th><th>Repetições</th><th>Carga (kg)</th><th><span className="sr-only">Ações</span></th></tr></thead><tbody>{exercise.series.map((set,setIndex)=><tr key={setIndex}><td>{setIndex+1}</td><td><input type="number" disabled={lockedIdentity} required min={minimumQuantity(set)} max={30-totalSeries(exercise)+(set.quantidade??1)} step="1" aria-label={`Número de séries da linha ${setIndex+1} do exercício ${exerciseIndex+1}`} value={set.quantidade??1} onChange={event=>editSet(exerciseIndex,setIndex,'quantidade',event.target.value)} /></td><td><input type="number" required min="1" max="100" step="1" aria-label={`Repetições da linha ${setIndex+1} do exercício ${exerciseIndex+1}`} value={set.repeticoesPrevistas??''} onChange={event=>editSet(exerciseIndex,setIndex,'repeticoesPrevistas',event.target.value)} /></td><td><input type="number" required min="0" max="1500" step="0.25" aria-label={`Carga prevista da linha ${setIndex+1} do exercício ${exerciseIndex+1}`} value={set.cargaPrevista??''} onChange={event=>editSet(exerciseIndex,setIndex,'cargaPrevista',event.target.value)} /></td><td><button type="button" className="text-button" disabled={lockedIdentity||exercise.series.length===1||hasExecution(set)} onClick={()=>editExercise(exerciseIndex,'series',exercise.series.filter((_,index)=>index!==setIndex))} aria-label={`Remover série ${setIndex+1}`}>✕</button></td></tr>)}</tbody></table></div>
        <div className="exercise-actions"><button type="button" className="athlete-button" disabled={lockedIdentity||totalSeries(exercise) >= 30} onClick={() => editExercise(exerciseIndex, 'series', [...exercise.series, newPrescribedSet(exercise.series.at(-1))])}>+ Série</button><button type="button" className="text-button" disabled={lockedIdentity||session.exercicios.length === 1 || exercise.series.some(hasExecution)} onClick={() => setSession({ ...session, exercicios: session.exercicios.filter((_, index) => index !== exerciseIndex) })}>Remover exercício</button></div>
      </fieldset>)}
      <button type="button" className="athlete-button" disabled={lockedIdentity||session.exercicios.length >= 30} onClick={() => setSession({ ...session, exercicios: [...session.exercicios, initialExercise()] })}>+ Adicionar exercício</button>
      </>}
      <div className="editor-save"><a className="athlete-button" href={`#/alunos/${studentId}`}>Voltar ao perfil</a><button className="dashboard-action" disabled={busy}>{busy ? 'Salvando…' : 'Salvar sessão'}</button></div>
    </fieldset></form>
  </div>
}

export default function StudentProfilePage({ studentId, editor = false, athleteData = false, query = '', studentView = false, personal = false, bodyWeight = false, evolution = false }) {
  const [account, setAccount] = useState(null)
  const [data, setData] = useState(null)
  const [period, setPeriod] = useState('90')
  const [volume, setVolume] = useState('semana')
  const [metric, setMetric] = useState('agachamento')
  const [weightMetric, setWeightMetric] = useState('peso')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [notice,setNotice]=useState('')
  const refreshAfterSave=()=>{setRevision(value=>value+1);setNotice('Sessão atualizada. Consulte o resumo no calendário.')}
  const [photoFailed, setPhotoFailed] = useState(false)
  useEffect(() => {
    const confirmed=event=>{if(studentView?event.detail.path.startsWith('/api/auth/'):event.detail.path.startsWith(`/api/alunos/${studentId}/`))setRevision(value=>value+1)}
    window.addEventListener('power-system-write-confirmed',confirmed)
    const refresh = () => setRevision((value) => value + 1)
    const timer = setInterval(refresh, 30000)
    window.addEventListener('focus', refresh)
    return () => { clearInterval(timer); window.removeEventListener('focus', refresh);window.removeEventListener('power-system-write-confirmed',confirmed) }
  }, [])
  useEffect(() => {
    const controller = new AbortController()
    setLoading(true); setError('')
    Promise.all([api('/api/auth/me', undefined, controller.signal), api(`${studentView?'/api/auth/perfil':`/api/alunos/${studentId}/perfil`}?periodo=${period}&volume=${volume}`, undefined, controller.signal)])
      .then(([me, result]) => { if(studentView && me.perfil!=='aluno'){window.location.hash='/alunos';return} setAccount(me); setData(result); setPhotoFailed(false) })
      .catch((failure) => { if (failure.name !== 'AbortError') setError(errorMessage(failure)) })
      .finally(() => { if (!controller.signal.aborted) setLoading(false) })
    return () => controller.abort()
  }, [studentId, studentView, period, volume, revision])
  const chartMetric = metric === 'peso' ? weightMetric : metric
  const profile = data?.perfil
  const availability=metricAvailability(profile,data?.kpis)
  const blockText = profile?.statusBloco === 'ativo' ? `Semana ${profile.semanaAtual} de ${profile.semanas} — ${profile.bloco || 'Bloco de treino'}` : profile?.statusBloco === 'agendado' ? `Próximo bloco: ${profile.bloco || 'Treino'} · ${dayLabel(profile.inicioBloco)}` : profile?.statusBloco === 'finalizado' ? `${profile.bloco || 'Bloco'} finalizado` : 'Nenhum bloco em andamento'
  return <div className={`site-shell dashboard athlete-page ${studentView?'student-area':''}`}><AccountHeader account={account} onError={setError} /><main className="athlete-main">
    {!studentView && <nav className="athlete-breadcrumb" aria-label="Navegação"><a href="#/alunos">Meus alunos</a><span>/</span>{editor ? <><a href={`#/alunos/${studentId}`}>{data?.aluno.nome || 'Perfil'}</a><span>/</span><span>Prescrição</span></> : <span>Perfil do aluno</span>}</nav>}

    {error && <div role="alert" className="auth-message auth-error">{error}{data&&' Sua edição continua preservada.'}{/sessão/i.test(error)&&<a className="athlete-button" href="#/entrar?erro=sessao" onClick={rememberReturn}>Entrar novamente</a>} <button className="text-button" onClick={() => setRevision((value) => value + 1)}>Tentar novamente</button></div>}
    {!data && loading && <p role="status" className="table-state">Carregando o perfil do aluno…</p>}
    {notice && <p role="status" className="editor-success">{notice}</p>}
    {data?.dadosIncompletos&&<div role="alert" className="auth-message auth-error"><strong>Histórico incompleto: {data.sessoesInvalidas.length} sessão(ões) com dados indisponíveis.</strong><p>Os indicadores consideram apenas registros legíveis. Nenhuma sessão foi apagada.</p><UnavailableSessions issues={data.sessoesInvalidas} studentId={studentId} studentView={studentView} onSaved={refreshAfterSave}/></div>}
    {data && <>
      <header className="athlete-hero"><div className="athlete-identity"><div className="athlete-avatar">{data.aluno.foto && !photoFailed ? <img src={data.aluno.foto} alt={`Foto de ${data.aluno.nome}`} referrerPolicy="no-referrer" onError={() => setPhotoFailed(true)} /> : <span aria-label="Foto não cadastrada">{data.aluno.nome.split(' ').filter(Boolean).slice(0, 2).map((part) => part[0]).join('')}</span>}</div><div><p className="eyebrow">{studentView?'ÁREA DO ALUNO':editor ? 'PRESCRIÇÃO INDIVIDUAL' : 'PERFIL DO ATLETA'}</p><h1>{data.aluno.nome}</h1><p className={`athlete-block ${profile.statusBloco}`}><span aria-hidden="true">●</span>{blockText}</p></div></div><div className="athlete-hero-right"><div className="athlete-body-stats"><div><span>Peso corporal</span><strong>{number(profile.peso)} <small>kg</small></strong></div><div><span>DOTS · Total histórico</span><strong>{number(profile.dots, 2)} <small>pts</small></strong>{availability.dots&&<p className="metric-unavailable">{availability.dots} {studentView?<><a href="#/meu-perfil">Meu perfil</a> · <a href="#/meu-peso">Peso corporal</a></>:<a href={`#/alunos/${studentId}/dados`}>Ver dados do atleta</a>}</p>}</div></div>{!studentView && !editor && <a className="dashboard-action" href={`#/alunos/${studentId}/treino`}>Editar / Prescrever Treino <span aria-hidden="true">↗</span></a>}</div></header>
      {studentView ? <nav className="student-bottom-nav" aria-label="Minha área">{[
        ['Treinos','/meus-treinos','▤',!personal&&!bodyWeight&&!evolution],['Evolução','/minha-evolucao','↗',evolution],['Peso','/meu-peso','⚖',bodyWeight],['Perfil','/meu-perfil','○',personal]
      ].map(([title,path,icon,active])=><a key={path} href={`#${path}`} aria-current={active?'page':undefined}><span aria-hidden="true">{icon}</span>{title}</a>)}</nav> : <nav className="athlete-tabs" aria-label="Áreas do aluno"><a href={`#/alunos/${studentId}`} aria-current={!editor && !athleteData ? 'page' : undefined}>Panorama</a><a href={`#/alunos/${studentId}/dados`} aria-current={athleteData ? 'page' : undefined}>Dados do Atleta</a><a href={`#/alunos/${studentId}/treino`} aria-current={editor ? 'page' : undefined}>Prescrição</a></nav>}
      {studentView && bodyWeight ? <div className="training-editor"><AthleteData editable accountId={account.id} onChanged={()=>setRevision(value=>value+1)} /></div> : studentView && personal ? <StudentPersonalData data={data} account={account} onChanged={()=>setRevision(value=>value+1)} /> : athleteData ? <AthleteData studentId={studentId} onChanged={() => setRevision((value)=>value+1)} /> : editor ? <TrainingEditor key={`${studentId}-${query}`} data={data} studentId={studentId} coachId={account.id} query={query} onSaved={() => setRevision((value) => value + 1)} /> : <>
        {studentView && !evolution && <><UpcomingWorkouts entries={data.calendario} today={data.hoje} onSaved={refreshAfterSave}/><StudentAgenda entries={data.calendario} today={data.hoje} onSaved={refreshAfterSave}/></>}
        {(!studentView || evolution) && <><div className="athlete-overview-heading"><div><p className="eyebrow">DESEMPENHO</p><h2>Panorama geral</h2></div><label>Volume do período<select value={volume} onChange={(event) => setVolume(event.target.value)}><option value="semana">Semana atual</option><option value="mes">Mês atual</option></select></label></div>
        <section className="athlete-kpis" aria-label="Indicadores de força e volume">{['agachamento', 'supino', 'terra'].map((movement, index) => <article className="athlete-kpi" key={movement}><div className="kpi-top"><span>{labels[movement]} <small>PR</small></span><span className="kpi-index">0{index + 1}</span></div><strong>{number(data.kpis[movement]?.valor)} <small>kg</small></strong><p>{data.kpis[movement] ? `${data.kpis[movement].repeticoes} repetições · RPE ${number(data.kpis[movement].rpe)}` : 'Nenhum PR registrado'}</p></article>)}<article className="athlete-kpi total-kpi"><div className="kpi-top"><span>Total SBD</span><span>Σ</span></div><strong>{number(data.kpis.total)} <small>kg</small></strong><p>{availability.total||"Soma dos 3 PRs históricos"}</p></article><article className="athlete-kpi"><div className="kpi-top"><span>Volume total</span><span>↗</span></div><strong>{number(data.kpis.volume, 0)} <small>kg</small></strong><p className={data.kpis.variacao > 0 ? 'positive' : ''}>{data.kpis.variacao == null ? 'Sem base de comparação' : `${data.kpis.variacao > 0 ? '+' : ''}${number(data.kpis.variacao)}% vs. período anterior`}</p></article></section>
        <section className="athlete-panel progression-panel" aria-busy={loading}><div className="athlete-section-heading"><div><p className="eyebrow">EVOLUÇÃO AO LONGO DO TEMPO</p><h2>Progressão de carga e esforço</h2></div><label className="chart-period"><span className="sr-only">Período do gráfico</span><select value={period} onChange={(event) => setPeriod(event.target.value)}><option value="30">30 dias</option><option value="90">3 meses</option><option value="180">6 meses</option><option value="365">1 ano</option></select></label></div>
          {studentView && <label className="student-metric-select">Movimento / indicador<select value={metric} onChange={event=>setMetric(event.target.value)}>{['agachamento','supino','terra','total','volume','peso'].map(key=><option key={key} value={key}>{key==='peso'?'Peso corporal / DOTS':labels[key]}</option>)}</select></label>}
          <div className={`chart-tabs ${studentView?'coach-chart-tabs':''}`} role="group" aria-label="Métrica do gráfico">{['agachamento', 'supino', 'terra', 'total', 'volume', 'peso'].map((key) => <button key={key} aria-pressed={metric === key} className={metric === key ? 'active' : ''} onClick={() => setMetric(key)}>{key === 'peso' ? 'Peso corporal / DOTS' : labels[key]}</button>)}</div>
          <div className="chart-caption"><span><i />{labels[chartMetric]} <small>({chartMetric === 'dots' ? 'pontos' : 'kg'})</small></span>{metric === 'peso' && <label><span className="sr-only">Peso ou DOTS</span><select value={weightMetric} onChange={(event) => setWeightMetric(event.target.value)}><option value="peso">Peso corporal</option><option value="dots">DOTS</option></select></label>}</div>
          {chartMetric==='dots'&&availability.dots&&<p className="metric-unavailable" role="status">{availability.dots}</p>}{chartMetric==='total'&&availability.total&&<p className="metric-unavailable" role="status">{availability.total}</p>}<ProgressChart points={data.historico[chartMetric]} metric={chartMetric} referencePr={data.kpis[chartMetric]?.valor} />
        </section>
        </>}
        {!studentView && <TrainingCalendar entries={data.calendario} studentId={studentId} today={data.hoje} onSaved={refreshAfterSave}/> }
      </>}
    </>}
  </main></div>
}
