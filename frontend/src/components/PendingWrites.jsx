import {useEffect,useState} from 'react'
import {pendingWrites,confirmPendingWrite,rememberReturn,setWriteAccount,resumeReturn,writeConfirmation,clearWriteConfirmation} from './reliableWrites.js'
export default function PendingWrites({account}){
 const [records,setRecords]=useState([]),[busy,setBusy]=useState(null),[error,setError]=useState(''),[message,setMessage]=useState(''),[expired,setExpired]=useState(false),[offline,setOffline]=useState(typeof navigator!=='undefined'&&!navigator.onLine)
 useEffect(()=>{
  setWriteAccount(account);if(account)resumeReturn(account)
  const update=()=>{try{setRecords(pendingWrites(account));setMessage(writeConfirmation(account))}catch{setError('Não foi possível consultar os salvamentos pendentes.')}}
  const connectivity=()=>setOffline(!navigator.onLine),expiredSession=()=>setExpired(true)
  update();window.addEventListener('power-system-write-state',update);window.addEventListener('storage',update);window.addEventListener('online',connectivity);window.addEventListener('offline',connectivity);window.addEventListener('power-system-session-expired',expiredSession)
  return()=>{window.removeEventListener('power-system-write-state',update);window.removeEventListener('storage',update);window.removeEventListener('online',connectivity);window.removeEventListener('offline',connectivity);window.removeEventListener('power-system-session-expired',expiredSession)}
 },[account?.id,account?.perfil])
 async function confirm(record){setBusy(record.key);setError('');try{await confirmPendingWrite(record);setExpired(false)}catch(failure){setError(failure.message)}finally{setBusy(null)}}
 if(!account||!records.length&&!message&&!offline&&!expired)return null
 return <aside className="pending-writes" aria-label="Salvamentos">
  <h2>{records.length?'Salvamentos sem confirmação':'Conexão e salvamento'}</h2>
  {offline&&<p role="status">Você está sem conexão. Seus dados pendentes permanecem neste navegador.</p>}
  {expired&&<p role="alert">Sua sessão expirou. Seus dados continuam na tela. <a href="#/entrar?erro=sessao" onClick={rememberReturn}>Entrar novamente</a></p>}
  {message&&<p role="status" className="editor-success">{message} <button onClick={()=>clearWriteConfirmation(account)}>Fechar confirmação</button></p>}
  {error&&<p role="alert">{error}</p>}
  <ul>{records.map(record=><li key={record.key}>
   <strong>{record.label}</strong><span>{record.state==='login'?'É necessário entrar novamente.':record.state==='sending'?'Salvando; aguardando confirmação…':'Resultado ainda não confirmado.'}</span>
   {record.state==='login'&&<a className="athlete-button" href="#/entrar?erro=sessao" onClick={rememberReturn}>Entrar novamente</a>}
   <button className="athlete-button" disabled={!!busy||offline} onClick={()=>confirm(record)}>{busy===record.key?'Confirmando…':'Confirmar salvamento'}</button>
  </li>)}</ul>
 </aside>
}
