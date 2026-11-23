import {readApiResponse,errorMessage} from './apiErrors.js'
import {useState} from 'react'
const actions={registro_inicial:'Histórico anterior preservado',criar:'Prescrição criada',editar_prescricao:'Prescrição editada',concluir:'Treino concluído',corrigir_execucao:'Execução corrigida',cancelar:'Prescrição cancelada',anular:'Execução anulada',recuperar:'Dados da sessão recuperados'}
const formatDate=value=>value?new Date(value+'T12:00:00').toLocaleDateString('pt-BR'):'Não registrada'
export function auditDifferences(before,after){
 if(!before)return ['Registro inicial da sessão.']
 const changes=[]
 for(const [key,label] of [['data_prevista','Data prevista'],['data_realizada','Data realizada'],['situacao','Situação'],['titulo','Nome da sessão']])if(before[key]!==after[key])changes.push(`${label}: ${key.startsWith('data_')?formatDate(before[key]):before[key]??'—'} → ${key.startsWith('data_')?formatDate(after[key]):after[key]??'—'}`)
 if(before.concluido!==after.concluido)changes.push(after.concluido?'Conclusão registrada.':'Conclusão removida.')
 if(before.observacoes!==after.observacoes)changes.push('Observações do treinador alteradas.')
 if(JSON.stringify(before.prescricao)!==JSON.stringify(after.prescricao))changes.push('Configuração da prescrição alterada.')
 const old=Array.isArray(before.exercicios)?before.exercicios:[],current=Array.isArray(after.exercicios)?after.exercicios:[]
 for(let i=0;i<Math.max(old.length,current.length);i++){
  const a=old[i],b=current[i]
  if(!a||!b){changes.push(`${a?'Removido':'Adicionado'}: ${(a||b).nome}`);continue}
  if(a.nome!==b.nome||a.movimento!==b.movimento)changes.push(`Exercício: ${a.nome} → ${b.nome}`)
  if(a.rpePrevisto!==b.rpePrevisto)changes.push(`${b.nome}, RPE previsto: ${a.rpePrevisto??'não informado'} → ${b.rpePrevisto??'não informado'}`)
  const aRows=Array.isArray(a.series)?a.series:[],bRows=Array.isArray(b.series)?b.series:[]
  for(let j=0;j<Math.max(aRows.length,bRows.length);j++){
   const x=aRows[j],y=bRows[j],prefix=`${b.nome}, série ${j+1}`
   if(!x||!y){changes.push(`${prefix}: ${x?'removida':'adicionada'}`);continue}
   if(x.cargaPrevista!==y.cargaPrevista||x.repeticoesPrevistas!==y.repeticoesPrevistas)changes.push(`${prefix}, prescrição: ${x.repeticoesPrevistas} × ${x.cargaPrevista} kg → ${y.repeticoesPrevistas} × ${y.cargaPrevista} kg`)
   const result=row=>row.carga==null?'não realizada':`${row.repeticoes} × ${row.carga} kg · RPE ${row.rpe??'não informado'}`
   if(x.carga!==y.carga||x.repeticoes!==y.repeticoes||x.rpe!==y.rpe)changes.push(`${prefix}, execução: ${result(x)} → ${result(y)}`)
  }
 }
 return changes.length?changes:['Revisão salva sem alteração de cargas ou datas.']
}
export default function SessionAudit({sessionId,studentId,studentView}){
 const [history,setHistory]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false)
 async function load(){
  if(busy)return;setBusy(true);setError('')
  try{const response=await fetch(studentView?`/api/auth/treinos/${sessionId}/historico`:`/api/alunos/${studentId}/treinos/${sessionId}/historico`,{cache:'no-store'});if(response.status===401)window.dispatchEvent(new Event('power-system-session-expired'));setHistory(await readApiResponse(response,'Não foi possível carregar o histórico. Tente novamente.'))}catch(failure){setError(errorMessage(failure))}finally{setBusy(false)}
 }
 return <details className="session-audit" onToggle={event=>{if(event.currentTarget.open && !history && !error)load()}}><summary>Histórico de alterações</summary>
 {busy&&<p role="status">Carregando histórico…</p>}{error&&<p role="alert">{error} <button className="athlete-button" onClick={load}>Tentar novamente</button></p>}
 {history&&<ol>{history.map(event=><li key={event.id}><strong>{actions[event.acao]||event.acao}</strong><p>{event.autor} ({({aluno:'Aluno',treinador:'Treinador',sistema:'Sistema'})[event.perfil]||event.perfil}) · {new Date(event.data).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})}</p><p>{event.motivo}</p><details><summary>Ver alterações</summary><ul>{auditDifferences(event.antes,event.depois).map((text,index)=><li key={index}>{text}</li>)}</ul></details></li>)}</ol>}
 </details>
}
