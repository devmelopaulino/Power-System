import assert from 'node:assert/strict'
import {renderToStaticMarkup} from 'react-dom/server'
import {duplicatePrescription,draftKey,writePrescriptionDraft,readPrescriptionDraft,draftMatches,listPrescriptionDrafts} from '../src/components/prescriptionDrafts.js'
import {SessionDialog,TrainingEditor} from '../src/pages/StudentProfilePage.jsx'
import {trainingToday} from '../src/components/trainingDate.js'
import {applyExerciseRpe,reportedRpe} from '../src/components/exerciseRpe.js'
import {chartPointKey,selectionIndex} from '../src/components/chartSelection.js'
import {calendarDay} from '../src/components/sessionDates.js'
import {auditDifferences} from '../src/components/SessionAudit.jsx'
import {initializeExecution} from '../src/components/executionDraft.js'

const planned={repeticoesPrevistas:5,cargaPrevista:100,carga:null,repeticoes:null,rpe:null}
const session={id:1,versao:2,dataTreino:'2026-11-21',dataPrevista:'2026-11-23',dataRealizada:'2026-11-21',situacao:'ativa',titulo:'Supino',concluido:true,estadoExecucao:'parcial',seriesRealizadas:1,seriesPrescritas:2,prescricao:{tipoDia:'treino',rpePrevisto:8},observacoes:'',video:'',exercicios:[{nome:'Supino',movimento:'supino',series:[{...planned,carga:95,repeticoes:4,rpe:8},planned]}]}
const html=renderToStaticMarkup(<SessionDialog entry={{sessao:session,status:'parcial'}} editable onClose={()=>{}} />)
assert.match(html,/4 × 95 kg/,'student summary shows actual load before editing')
assert.match(html,/Não realizada/,'student summary shows skipped series')
assert.match(html,/1 de 2 séries realizadas/)
assert.match(html,/Parcial/)
assert.match(html,/Corrigir registro/)
assert.match(html,/23\/11\/2026/,'summary keeps planned date')
assert.match(html,/21\/11\/2026/,'summary shows performed date')
assert.doesNotMatch(html,/Confirmar conclusão/,'review does not immediately enter editing')
assert.strictEqual(initializeExecution(session,true),session,'repeated toggle preserves existing execution')
assert.equal(initializeExecution(session,true).exercicios[0].series[1].carga,null,'skipped series remains skipped')
const fresh={...session,concluido:false,exercicios:[{...session.exercicios[0],series:[planned]}]}
const initialized=initializeExecution(fresh,false)
assert.equal(initialized.exercicios[0].series[0].carga,100)
assert.equal(initialized.exercicios[0].series[0].repeticoes,5)
assert.equal(fresh.exercicios[0].series[0].carga,null,'initialization does not mutate original prescription')
assert.equal(trainingToday(new Date('2026-11-22T02:59:59Z')),'2026-11-21')
assert.equal(trainingToday(new Date('2026-11-22T03:00:00Z')),'2026-11-22')
const annulledHtml=renderToStaticMarkup(<SessionDialog entry={{sessao:{...session,situacao:'anulada'},status:'anulada'}} editable onClose={()=>{}} />)
assert.match(annulledHtml,/Execução anulada/)
assert.doesNotMatch(annulledHtml,/Corrigir registro|Concluir treino/,'annulled execution cannot be resubmitted')
const auditChanges=auditDifferences({data_prevista:'2026-11-23',data_realizada:null,exercicios:[]},{data_prevista:'2026-11-23',data_realizada:'2026-11-21',exercicios:[]})
assert.ok(auditChanges.some(text=>text.includes('Data realizada')&&text.includes('21/11/2026')))
assert.equal(calendarDay(session,'prevista'),'2026-11-23')
assert.equal(calendarDay(session,'realizada'),'2026-11-21')
assert.equal(calendarDay({...session,dataRealizada:null},'realizada'),'2026-11-23')
const coachSummary=renderToStaticMarkup(<SessionDialog entry={{sessao:session,status:'parcial'}} studentId={1} onClose={()=>{}} />)
assert.match(coachSummary,/Anular execução/)
assert.doesNotMatch(coachSummary,/Cancelar prescrição/)
const plan={...session,concluido:false,dataRealizada:null,exercicios:[{...session.exercicios[0],series:[planned]}]}
const coachPlan=renderToStaticMarkup(<SessionDialog entry={{sessao:plan,status:'agendado'}} studentId={1} onClose={()=>{}} />)
assert.match(coachPlan,/Cancelar prescrição/)
assert.doesNotMatch(coachPlan,/Anular execução/)
const bench={nome:'Supino',movimento:'supino',series:[{...planned,carga:80,repeticoes:5,rpe:7},{...planned,cargaPrevista:110,carga:null,repeticoes:null,rpe:null}]}
const benchSet=applyExerciseRpe(bench,true,{mode:'set',value:8.5})
assert.equal(benchSet.series[0].rpe,8.5,'effort follows the heaviest executed set, even when planned top was skipped')
assert.equal(benchSet.series[1].rpe,null)
assert.deepEqual(reportedRpe(benchSet),[8.5])
assert.ok(applyExerciseRpe(bench,true,{mode:'clear'}).series.every(row=>row.rpe===null),'explicit removal clears old values')
assert.equal(applyExerciseRpe(bench,true,{mode:'keep'}).series[0].rpe,7)
const invalidSummary=renderToStaticMarkup(<SessionDialog entry={{sessao:{id:9,titulo:'Sessão indisponível',dataTreino:'2026-11-21',versao:2,erroDados:true}}} editable onClose={()=>{}} />)
assert.match(invalidSummary,/dados indisponíveis/)
assert.doesNotMatch(invalidSummary,/Concluir treino/)
const oldPoints=[{data:'2026-11-20',valor:80},{data:'2026-11-21',valor:90}]
const selection={metric:'supino',key:chartPointKey(oldPoints[1])}
assert.equal(selectionIndex([{data:'2026-11-19',valor:70},...oldPoints.map(point=>({...point,valor:point.valor+1}))],'supino',selection),2,'selection follows record when points are refreshed or inserted')
assert.equal(selectionIndex(oldPoints,'terra',selection),-1)
assert.equal(selectionIndex(oldPoints.slice(0,1),'supino',selection),-1)
assert.notEqual(chartPointKey({id:1,data:'2026-11-21'}),chartPointKey({id:2,data:'2026-11-21'}),'same-day weigh-ins retain distinct identity')
const sourceEditor={...session,video:'https://example.invalid/executado',motivoAlteracao:'Correção anterior',situacao:'anulada',prescricao:{tipoDia:'treino',rpePrevisto:8},exercicios:[{nome:'Supino',movimento:'supino',rpePrevisto:8,series:[{...planned,carga:95,repeticoes:4,rpe:9,quantidade:3,execucoes:[{carga:95,repeticoes:4,rpe:9}]}]}]}
const copied=duplicatePrescription(sourceEditor)
assert.equal(copied.id,null)
assert.equal(copied.versao,null)
assert.equal(copied.dataTreino,'','copy forces a new date choice')
assert.equal(copied.dataRealizada,null)
assert.equal(copied.concluido,false)
assert.equal(copied.situacao,'ativa')
assert.equal(copied.video,'')
assert.equal(copied.motivoAlteracao,null)
assert.equal(copied.exercicios[0].rpePrevisto,8)
assert.equal(copied.exercicios[0].series[0].quantidade,3)
assert.equal(copied.exercicios[0].series[0].cargaPrevista,100)
assert.equal(copied.exercicios[0].series[0].repeticoesPrevistas,5)
assert.equal(copied.exercicios[0].series[0].carga,null)
assert.equal(copied.exercicios[0].series[0].rpe,null)
assert.deepEqual(copied.exercicios[0].series[0].execucoes,[])
assert.equal(sourceEditor.exercicios[0].series[0].carga,95,'copy never mutates original execution')
const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key),key:index=>[...values.keys()][index],get length(){return values.size}}
const existingDraftKey=draftKey(1,7,1)
writePrescriptionDraft(storage,existingDraftKey,sourceEditor)
const stored=readPrescriptionDraft(storage,existingDraftKey)
assert.equal(stored.session.exercicios[0].series[0].quantidade,3)
assert.ok(draftMatches(stored,{id:1,versao:2}))
assert.ok(!draftMatches(stored,{id:1,versao:3}),'stale draft cannot be applied to a newer server version')
assert.ok(!draftMatches(stored,{id:2,versao:2}),'draft identity must match the session as well as its version')
assert.equal(readPrescriptionDraft(storage,draftKey(2,7,1)),null,'coach drafts are isolated')
assert.equal(readPrescriptionDraft(storage,draftKey(1,8,1)),null,'student drafts are isolated')
writePrescriptionDraft(storage,draftKey(1,7,null,'copy-a'),copied,'copy-a')
writePrescriptionDraft(storage,draftKey(1,7,null,'copy-b'),{...copied,titulo:'Outra sessão'},'copy-b')
assert.equal(listPrescriptionDrafts(storage,1,7).length,3,'new copies never overwrite another draft')
assert.equal(listPrescriptionDrafts(storage,2,7).length,0)
storage.setItem('broken','null')
assert.throws(()=>readPrescriptionDraft(storage,'broken'),/rascunho salvo está indisponível/)
storage.setItem('malformed',JSON.stringify({schema:1,session:{titulo:'X',prescricao:{},exercicios:[{nome:'X',series:null}]}}))
assert.throws(()=>readPrescriptionDraft(storage,'malformed'),/rascunho salvo está indisponível/)
const editorHtml=renderToStaticMarkup(<TrainingEditor data={{calendario:[]}} studentId={7} coachId={1} onSaved={()=>{}} query="" />)
assert.match(editorHtml,/Duplicar sessão existente/)
assert.match(editorHtml,/Rascunhos deste aluno/)
console.log('OK: review shows actual and skipped series; toggling adjustments preserves execution.')

async function testReliableWrites(){
 const {setWriteAccount,reliableMutation,pendingWrites,confirmPendingWrite}=await import('../src/components/reliableWrites.js')
 const original={window:globalThis.window,localStorage:globalThis.localStorage,sessionStorage:globalThis.sessionStorage,fetch:globalThis.fetch}
 const memory=()=>{const rows=new Map();return {getItem:key=>rows.get(key)??null,setItem:(key,value)=>rows.set(key,value),removeItem:key=>rows.delete(key),key:index=>[...rows.keys()][index],get length(){return rows.size}}}
 try{
  globalThis.window=new EventTarget();window.location={hash:'#/meu-peso'}
  globalThis.localStorage=memory();globalThis.sessionStorage=memory()
  const account={id:9,perfil:'aluno'},body={operacaoId:'test-operation-001',peso:83,data:'2026-11-23'}
  setWriteAccount(account)
  let requests=[]
  globalThis.fetch=async(path,options)=>{requests.push(options);throw new TypeError('response lost')}
  await assert.rejects(reliableMutation('/api/auth/pesagens',body),/preservada/)
  assert.equal(pendingWrites(account).length,1)
  await assert.rejects(reliableMutation('/api/auth/pesagens',{...body,peso:84}),/anterior/)
  assert.equal(requests.length,1,'different payload cannot overwrite uncertain write')
  globalThis.fetch=async(path,options)=>{requests.push(options);return new Response(JSON.stringify({ok:true}),{status:200})}
  await confirmPendingWrite(pendingWrites(account)[0])
  assert.equal(requests[1].headers['Idempotency-Key'],requests[0].headers['Idempotency-Key'])
  assert.equal(requests[1].body,requests[0].body)
  assert.equal(pendingWrites(account).length,0)
  globalThis.fetch=async()=>new Response(JSON.stringify({erro:'expired'}),{status:401})
  await assert.rejects(reliableMutation('/api/auth/pesagens',{...body,operacaoId:'test-operation-002'}),/expirou/)
  const expired=pendingWrites(account)[0]
  assert.equal(expired.state,'login');assert.equal(window.location.hash,'#/meu-peso')
  setWriteAccount({id:10,perfil:'aluno'})
  await assert.rejects(confirmPendingWrite(expired),/mesma conta/)
  assert.equal(pendingWrites({id:10,perfil:'aluno'}).length,0)
  setWriteAccount(account)
  globalThis.fetch=async()=>new Response(JSON.stringify({erro:'unavailable'}),{status:503})
  await assert.rejects(confirmPendingWrite(expired),/preservados/)
  assert.equal(pendingWrites(account)[0].state,'uncertain')
  globalThis.fetch=async()=>new Response(JSON.stringify({erro:'Revise os dados'}),{status:400})
  await assert.rejects(confirmPendingWrite(expired),/Revise/)
  assert.equal(pendingWrites(account).length,0)
  console.log('OK: lost responses preserve payload/key; retries, expired login and account isolation are safe.')
 }finally{Object.assign(globalThis,original);setWriteAccount(null)}
}
testReliableWrites().catch(error=>{console.error(error);process.exitCode=1})

// Audit 12/34/38/40: missing metrics, decimal entry and actionable errors.
import {metricAvailability} from '../src/components/metricAvailability.js'
import {executionNumberError,validatedExecution,matchesPrescription} from '../src/components/executionNumbers.js'
import ExecutionNumberField from '../src/components/ExecutionNumberField.jsx'
import {apiError,readApiResponse,errorMessage} from '../src/components/apiErrors.js'
const allLifts={agachamento:{valor:160},supino:{valor:100},terra:{valor:200},total:460}
assert.match(metricAvailability({peso:83,categoria:'masculino'}, {...allLifts,total:null,terra:null}).total,/Terra/)
assert.doesNotMatch(metricAvailability({peso:83,categoria:'masculino'}, {...allLifts,total:null,terra:null}).total,/Supino/)
assert.match(metricAvailability({},allLifts).dots,/peso corporal/)
assert.match(metricAvailability({},allLifts).dots,/gênero/)
assert.match(metricAvailability({peso:83,categoria:'masculino'},allLifts).dots,/indisponível/,'unexpected missing DOTS still gets an actionable explanation')
assert.deepEqual(metricAvailability({peso:83,categoria:'masculino',dots:300},allLifts),{total:'',dots:''})
assert.match(metricAvailability({peso:83,categoria:'masculino'}, {...allLifts,total:0}).dots,/maior que zero/)
assert.ok(executionNumberError('','carga'),'empty load cannot become zero')
assert.equal(executionNumberError('0','carga'),'','explicit bodyweight load is valid')
assert.equal(executionNumberError('92,5','carga'),'','Brazilian decimal input works')
assert.ok(executionNumberError('3.5','repeticoes'),'fractional repetitions rejected')
for(const value of ['-1','1501','Infinity','1e3','abc'])assert.ok(executionNumberError(value,'carga'))
assert.ok(executionNumberError('101','repeticoes'))
assert.throws(()=>validatedExecution({nome:'Supino',series:[{...planned,carga:'',repeticoes:'3'}]}),/Supino, série 1.*carga/)
assert.throws(()=>validatedExecution({nome:'Supino',series:[{...planned,carga:'92,5',repeticoes:''}]}),/repetições/)
const rawExercise={nome:'Supino',series:[{...planned,carga:'92,5',repeticoes:'3'},planned]}
const normalized=validatedExecution(rawExercise)
assert.equal(normalized.series[0].carga,92.5)
assert.equal(normalized.series[0].repeticoes,3)
assert.equal(normalized.series[1].carga,null,'skipped stays skipped')
assert.equal(rawExercise.series[0].carga,'92,5','validation leaves editable input untouched')
assert.equal(applyExerciseRpe(normalized,true,{mode:'set',value:8}).series[0].rpe,8)
const emptyNumberHtml=renderToStaticMarkup(<ExecutionNumberField value="" kind="carga" label="Kg feitos" onChange={()=>{}}/>)
assert.match(emptyNumberHtml,/inputMode="decimal"/)
assert.match(emptyNumberHtml,/aria-invalid="true"/)
assert.match(emptyNumberHtml,/value=""/)
assert.match(apiError(403).message,/permissão/)
assert.match(apiError(404).message,/registro/)
assert.doesNotMatch(apiError(503,'SQL connection secret').message,/SQL|secret/)
assert.equal(apiError(409,'Recarregue a sessão.').message,'Recarregue a sessão.')
assert.match(errorMessage(new TypeError('Failed to fetch')),/conexão/)
async function testErrorResponses(){
 await assert.rejects(readApiResponse(new Response('<html>proxy failed</html>',{status:503})),/temporariamente indisponível/)
 await assert.rejects(readApiResponse(new Response('{invalid',{status:200})),/temporariamente indisponível/)
 await assert.rejects(readApiResponse(new Response(JSON.stringify({erro:'Repetições inválidas.'}),{status:400})),/Repetições inválidas/)
 console.log('OK: missing metrics, empty/decimal execution fields and actionable API failures.')
}
testErrorResponses().catch(error=>{console.error(error);process.exitCode=1})

assert.ok(matchesPrescription({...planned,carga:'100',repeticoes:'5'}),'numeric input strings still match prescription')
assert.ok(!matchesPrescription({...planned,carga:'',repeticoes:'5'}),'empty input never matches a prescribed zero')
assert.deepEqual(reportedRpe({series:[{carga:'92,5',rpe:8}]}),[8],'RPE summary accepts a decimal draft without discarding it')
