import {useEffect,useRef,useState} from 'react'
import {readPrescriptionDraft,writePrescriptionDraft,draftMatches} from './prescriptionDrafts.js'

export default function usePrescriptionDraft({storageKey,slot,original,autoResume}){
 const initial=useRef(null)
 if(!initial.current){let draft=null,error='',blocked=false;try{if(typeof window!=='undefined')draft=readPrescriptionDraft(window.localStorage,storageKey)}catch(failure){error=failure.message;blocked=failure.name==='InvalidPrescriptionDraft'}
  const resume=!!(autoResume&&draft&&draftMatches(draft,original))
  initial.current={session:resume?draft.session:original,pending:resume?null:draft,dirty:resume,error,blocked,resumed:resume}
 }
 const [session,setSessionState]=useState(initial.current.session),[dirty,setDirty]=useState(initial.current.dirty),[pending,setPending]=useState(initial.current.pending)
 const [status,setStatus]=useState(initial.current.resumed?'Rascunho recuperado.':initial.current.error),[storageError,setStorageError]=useState(!!initial.current.error)
 const [blockedDraft,setBlockedDraft]=useState(initial.current.blocked)
 const saved=useRef(false),current=useRef(null)
 current.current={session,dirty,pending,blockedDraft}
 function persist(){const state=current.current;if(!saved.current&&state?.dirty&&!state.pending&&!state.blockedDraft)writePrescriptionDraft(window.localStorage,storageKey,state.session,slot)}
 useEffect(()=>{
  if(!dirty||pending||blockedDraft||saved.current)return
  setStatus('Salvando rascunho…')
  const timer=setTimeout(()=>{try{persist();setStorageError(false);setStatus('Rascunho salvo neste navegador às '+new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})+'.')}catch{setStorageError(true);setStatus('Não foi possível guardar o rascunho. Mantenha a página aberta e salve a sessão.')}},300)
  return ()=>clearTimeout(timer)
 },[session,dirty,pending,blockedDraft,storageKey,slot])
 useEffect(()=>{
  const pagehide=()=>{try{persist()}catch{}}
  const leaving=event=>{try{persist()}catch{event.preventDefault();event.returnValue=''}}
  const navigate=event=>{if(event.target?.closest?.('a[href]')){try{persist()}catch{event.preventDefault();event.stopPropagation();setStorageError(true);setStatus('Não foi possível guardar o rascunho. Salve a sessão antes de sair.')}}}
  document.addEventListener('click',navigate,true)
  window.addEventListener('beforeunload',leaving);window.addEventListener('pagehide',pagehide)
  return ()=>{pagehide();document.removeEventListener('click',navigate,true);window.removeEventListener('beforeunload',leaving);window.removeEventListener('pagehide',pagehide)}
 },[storageKey,slot])
 function setSession(value){setDirty(true);setSessionState(value)}
 function recover(freshOriginal=original){if(!pending||!draftMatches(pending,freshOriginal))return;setSessionState(pending.session);setDirty(true);setPending(null);setStatus('Rascunho recuperado.');setStorageError(false)}
 function discard(fresh=original){try{window.localStorage.removeItem(storageKey)}catch{setStorageError(true);setStatus('Não foi possível remover o rascunho deste navegador.');return false}current.current={session:fresh,dirty:false,pending:null};setSessionState(fresh);setDirty(false);setPending(null);setStorageError(false);setBlockedDraft(false);setStatus('Rascunho descartado.');return true}
 function finish(){saved.current=true;try{window.localStorage.removeItem(storageKey)}catch{};setDirty(false)}
 return {session,setSession,pending,blockedDraft,recover,discard,finish,status,storageError,dirty,persist}
}
