import {readApiResponse,errorMessage} from './apiErrors.js'
import { useEffect, useRef, useState } from 'react'
import { trainingToday } from './trainingDate.js'
import {reliableMutation} from './reliableWrites.js'
import ProgressChart from './ProgressChart.jsx'
import RecentRecordPicker from './RecentRecordPicker.jsx'

const today=trainingToday
const num=(n)=>n==null?'—':new Intl.NumberFormat('pt-BR',{maximumFractionDigits:2}).format(n)
const signed=(n)=>n==null?'—':(n>0?'+':'')+num(n)
const dayText=(d)=>new Date(d+'T12:00:00').toLocaleDateString('pt-BR')
const origins={onboarding:'Cadastro inicial',treino:'Treino',descanso:'Descanso',manual:'Atualização do aluno',treinador:'Ajuste do treinador',legado:'Registro anterior'}

export default function AthleteData({studentId,editable=false,accountId,onChanged=()=>{}}){
  const [data,setData]=useState(null),[error,setError]=useState(''),[message,setMessage]=useState('')
  const formKey=`power-system-weight-form:${accountId}`
  const recovered=useRef(null)
  if(recovered.current===null){try{recovered.current=editable?JSON.parse(sessionStorage.getItem(formKey))||{}:{}}catch{recovered.current={}}}
  const weightOperation=useRef(recovered.current.operacaoId||crypto.randomUUID())
  const [weight,setWeight]=useState(recovered.current.weight||''),[day,setDay]=useState(recovered.current.day||today()),[source,setSource]=useState(recovered.current.source||'manual')
  const [settings,setSettings]=useState(null),[correction,setCorrection]=useState(null),[deleting,setDeleting]=useState(false)
  const [choosingWeight,setChoosingWeight]=useState(false)
  const correctionArea=useRef(null)
  function selectWeight(entry){setCorrection({id:entry.id,data:entry.data,peso:entry.peso});setDeleting(false);setChoosingWeight(false);requestAnimationFrame(()=>correctionArea.current?.scrollIntoView({behavior:'smooth',block:'start'}))}
  const [busy,setBusy]=useState(false),[revision,setRevision]=useState(0),[period,setPeriod]=useState('365'),[trend,setTrend]=useState(true)
  useEffect(()=>{
    const controller=new AbortController();let pending=false
    async function load(){
      if(pending)return;pending=true
      try{
        const r=await fetch(editable?'/api/auth/dados-atleta':'/api/alunos/'+studentId+'/dados-atleta',{cache:'no-store',signal:controller.signal})
        if(r.status===401){window.dispatchEvent(new Event('power-system-session-expired'));throw new Error('Sua sessão expirou. Seus dados continuam preservados na tela.')}
        const result=await readApiResponse(r,'Não foi possível carregar os dados do atleta. Tente novamente.');setData(result);setError('')
        setSettings(current=>current??{genero:result.genero||'',categoriaPesoAlvo:result.categoriaPesoAlvo??''})
      }catch(e){if(e.name!=='AbortError')setError(errorMessage(e))}finally{pending=false}
    }
    load();const timer=setInterval(load,15000);window.addEventListener('focus',load)
    return()=>{controller.abort();clearInterval(timer);window.removeEventListener('focus',load)}
  },[studentId,editable,revision])
  useEffect(()=>{const confirmed=event=>{if(event.detail.path==='/api/auth/pesagens'&&editable){if(event.detail.payload.operacaoId===weightOperation.current){if(Number(weight)===event.detail.payload.peso&&day===event.detail.payload.data){setWeight('');try{sessionStorage.removeItem(formKey)}catch{}}weightOperation.current=crypto.randomUUID()}setMessage('Peso confirmado.');setRevision(value=>value+1);onChanged()}else if(!editable&&event.detail.path.startsWith(`/api/alunos/${studentId}/`)){setRevision(value=>value+1);setMessage('Alteração confirmada.');onChanged()}};window.addEventListener('power-system-write-confirmed',confirmed);return()=>window.removeEventListener('power-system-write-confirmed',confirmed)},[studentId,editable,weight,day])
  useEffect(()=>{if(!editable)return;const preserve=()=>{try{sessionStorage.setItem(formKey,JSON.stringify({weight,day,source,operacaoId:weightOperation.current}))}catch{}};window.addEventListener('power-system-before-login',preserve);return()=>window.removeEventListener('power-system-before-login',preserve)},[editable,weight,day,source,formKey])
  async function mutate(path,body,success){
    setBusy(true);setError('');setMessage('')
    try{await reliableMutation(path,body);setMessage(success);setRevision(n=>n+1);onChanged();return true}
    catch(e){setError(errorMessage(e));return false}finally{setBusy(false)}
  }
  async function record(e){
    e.preventDefault()
    if(await mutate('/api/auth/pesagens',{operacaoId:weightOperation.current,peso:Number(weight),data:day,origem:!data?.atual?'onboarding':source},'Peso registrado.')){setWeight('');weightOperation.current=crypto.randomUUID();try{sessionStorage.removeItem(formKey)}catch{}}
  }
  async function saveSettings(e){
    e.preventDefault()
    await mutate('/api/alunos/'+studentId+'/dados-atleta',{genero:settings.genero||null,categoriaPesoAlvo:settings.categoriaPesoAlvo===''?null:Number(settings.categoriaPesoAlvo)},'Dados atualizados. O DOTS foi recalculado.')
  }
  async function correct(e,remove=false){
    e.preventDefault()
    if(await mutate('/api/alunos/'+studentId+'/pesagens/'+correction.id+'/'+(remove?'excluir':'editar'),remove?{}:{peso:Number(correction.peso),data:correction.data},remove?'Pesagem excluída dos cálculos.':'Pesagem corrigida.')){setCorrection(null);setDeleting(false)}
  }
  const cutoff=new Date(today()+'T12:00:00');cutoff.setDate(cutoff.getDate()-Number(period)+1)
  const points=(data?.pontos||[]).map(({registro,variacaoAnterior})=>({...registro,valor:registro.peso,variacaoAnterior})).filter(p=>new Date(p.data+'T12:00:00')>=cutoff)
  const margin=data?.atual&&data.categoriaPesoAlvo!=null?data.atual.peso-data.categoriaPesoAlvo:null
  return <section className="athlete-panel athlete-data-panel">
    <div className="athlete-section-heading"><div><p className="eyebrow">{editable?'PESO CORPORAL':'DADOS DO ATLETA'}</p><h2>Composição e evolução de peso</h2></div></div>
    {error&&<p role="alert" className="auth-message auth-error">{error} <button className="text-button" onClick={()=>setRevision(n=>n+1)}>Tentar novamente</button></p>}
    {message&&<p className="editor-success" role="status">{message}</p>}
    {!data?!error&&<p role="status">Carregando pesagens…</p>:<>
      <div className="weight-kpis"><article><span>Peso corporal atual</span><strong>{num(data.atual?.peso)} <small>kg</small></strong><p>{data.atual?dayText(data.atual.data):'Sem pesagem registrada'}</p></article><article><span>Peso inicial</span><strong>{num(data.inicial?.peso)} <small>kg</small></strong><p>{data.inicial?dayText(data.inicial.data)+' · '+origins[data.inicial.origem]:'Sem registro inicial'}</p></article><article><span>Variação total</span><strong>{signed(data.variacaoTotal)} <small>kg</small></strong><p>Desde o registro inicial</p></article></div>
      {!editable&&settings?<form className="athlete-settings" onSubmit={saveSettings}><div className="editor-grid"><label>Gênero<select value={settings.genero} onChange={e=>setSettings({...settings,genero:e.target.value})}><option value="">Não informado</option><option value="masculino">Masculino</option><option value="feminino">Feminino</option></select></label><label>Categoria de Peso Alvo (kg)<input type="number" min="1" max="500" step="0.1" placeholder="83" value={settings.categoriaPesoAlvo} onChange={e=>setSettings({...settings,categoriaPesoAlvo:e.target.value})}/></label></div><button className="athlete-button" disabled={busy}>Salvar gênero e categoria</button></form>:null}
      {data.categoriaPesoAlvo!=null&&<div className="weight-margin"><strong>Categoria: -{num(data.categoriaPesoAlvo)} kg</strong><span>{margin==null?'Aguardando pesagem':margin>0?'+'+num(margin)+' kg acima do limite':'Dentro do limite'+(margin<0?' · '+num(-margin)+' kg de margem':'')}</span></div>}
      <div className="weight-chart-heading"><h3>Evolução de peso corporal</h3><label><span className="sr-only">Período das pesagens</span><select value={period} onChange={e=>setPeriod(e.target.value)}><option value="30">30 dias</option><option value="90">3 meses</option><option value="180">6 meses</option><option value="365">1 ano</option></select></label></div>
      <div className="weight-chart-legend"><span>● Peso registrado</span><label><input type="checkbox" checked={trend} onChange={e=>setTrend(e.target.checked)}/> Tendência (média de 7 registros)</label>{data.categoriaPesoAlvo!=null&&<span>┄ Categoria alvo</span>}</div>
      <ProgressChart points={points} metric="peso" target={data.categoriaPesoAlvo} trend={trend} onSelect={!editable?selectWeight:undefined}/>
      {editable&&<form className="weight-checkin" onSubmit={record}><h3>Registrar peso</h3><div className="editor-grid"><label>Peso corporal (kg)<input type="number" min="1" max="500" step="0.01" required value={weight} onChange={e=>setWeight(e.target.value)}/></label><label>Data da pesagem<input type="date" required max={today()} value={day} onChange={e=>setDay(e.target.value)}/></label><label>Tipo de atualização<select value={source} onChange={e=>setSource(e.target.value)}><option value="manual">Atualização manual</option><option value="treino">Check-in de treino</option><option value="descanso">Check-in de descanso</option></select></label></div><button className="dashboard-action" disabled={busy}>{busy?'Registrando…':'Registrar peso'}</button></form>}
      {!editable&&<section className="weight-corrections" ref={correctionArea}><h3>Correção de pesagens</h3><button type="button" className="athlete-button" aria-expanded={choosingWeight} onClick={()=>setChoosingWeight(value=>!value)}>Editar pesagem existente</button>
        {choosingWeight&&<RecentRecordPicker label="Buscar pesagem" placeholder="Data, peso ou origem do registro" records={data.historico.map(entry=>({id:entry.id,date:entry.data,title:num(entry.peso)+' kg',subtitle:origins[entry.origem],search:entry.origem,reading:entry}))} onSelect={record=>selectWeight(record.reading)} disabled={busy}/>}
        {correction&&<p className="editing-record-label">Editando pesagem de {dayText(correction.data)}</p>}{correction&&<form onSubmit={correct}><div className="editor-grid"><label>Data<input type="date" max={today()} required value={correction.data} onChange={e=>setCorrection({...correction,data:e.target.value})}/></label><label>Peso (kg)<input type="number" min="1" max="500" step="0.01" required value={correction.peso} onChange={e=>setCorrection({...correction,peso:e.target.value})}/></label></div><div className="weight-correction-actions"><button className="dashboard-action" disabled={busy}>Salvar correção</button><button type="button" className="athlete-button" disabled={busy} onClick={()=>setDeleting(true)}>Excluir registro</button></div>{deleting&&<div className="weight-delete-confirm" role="alert"><p>Excluir esta pesagem? O peso atual, a variação e o DOTS serão recalculados.</p><button type="button" className="dashboard-action" disabled={busy} onClick={e=>correct(e,true)}>Confirmar exclusão</button> <button type="button" className="athlete-button" onClick={()=>setDeleting(false)}>Cancelar</button></div>}</form>}</section>}
    </>}
  </section>
}
