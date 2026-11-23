export const draftPrefix=(coachId,studentId)=>`power-system-prescription:v1:${coachId}:${studentId}:`
export const draftKey=(coachId,studentId,sessionId,slot='default')=>draftPrefix(coachId,studentId)+(sessionId?`session:${sessionId}`:`new:${slot}`)
export function readPrescriptionDraft(storage,key){
 const raw=storage.getItem(key);if(!raw)return null
 let value;try{value=JSON.parse(raw)}catch{const error=new Error('O rascunho salvo está indisponível. Ele foi preservado no navegador.');error.name='InvalidPrescriptionDraft';throw error}
 if(!value||value.schema!==1||typeof value.savedAt!=='string'||!Number.isFinite(Date.parse(value.savedAt))||typeof value.slot!=='string'||!value.session||typeof value.session.titulo!=='string'||!Array.isArray(value.session.exercicios)||!value.session.prescricao||typeof value.session.prescricao!=='object'||!value.session.exercicios.every(exercise=>exercise&&typeof exercise.nome==='string'&&Array.isArray(exercise.series)&&exercise.series.every(row=>row&&typeof row==='object'))){const error=new Error('O rascunho salvo está indisponível. Ele foi preservado no navegador.');error.name='InvalidPrescriptionDraft';throw error}
 return value
}
export function writePrescriptionDraft(storage,key,session,slot='default'){
 const value={schema:1,savedAt:new Date().toISOString(),baseVersion:session.versao??null,slot,session:structuredClone(session)}
 storage.setItem(key,JSON.stringify(value));return value
}
export const draftMatches=(draft,session)=>draft.baseVersion===(session?.versao??null)&&(draft.session.id??null)===(session?.id??null)
export function listPrescriptionDrafts(storage,coachId,studentId){
 const prefix=draftPrefix(coachId,studentId),records=[]
 for(let index=0;index<storage.length;index++){const key=storage.key(index);if(!key?.startsWith(prefix))continue;try{const value=readPrescriptionDraft(storage,key);if(value)records.push({...value,key})}catch{}}
 return records.sort((a,b)=>b.savedAt.localeCompare(a.savedAt))
}
export function duplicatePrescription(source){
 return {id:null,versao:null,operacaoId:crypto.randomUUID(),dataTreino:'',dataPrevista:null,dataRealizada:null,situacao:'ativa',concluido:false,motivoAlteracao:null,
  titulo:`${source.titulo||'Treino'} · Cópia`.slice(0,120),
  observacoes:(source.observacoes||'').split('\n').filter(line=>!line.startsWith('Sessao originalmente prevista para ')).join('\n'),video:'',
  prescricao:{tipoDia:source.prescricao?.tipoDia==='descanso'?'descanso':'treino',aquecimento:'',cargaMaximaDia:null,rpePrevisto:source.prescricao?.rpePrevisto??null},
  exercicios:(source.exercicios||[]).map(exercise=>({nome:exercise.nome,movimento:exercise.movimento,rpePrevisto:exercise.rpePrevisto??null,
   series:exercise.series.map(row=>({repeticoesPrevistas:row.repeticoesPrevistas,cargaPrevista:row.cargaPrevista,quantidade:row.quantidade??1,repeticoes:null,carga:null,rpe:null,execucoes:[]}))}))}
}
