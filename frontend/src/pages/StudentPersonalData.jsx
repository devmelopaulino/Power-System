import {errorMessage} from '../components/apiErrors.js'
import {reliableMutation} from '../components/reliableWrites.js'
import { useEffect,useState } from 'react'

export default function StudentPersonalData({data,account,onChanged}) {
  const formKey=`power-system-personal-form:${account.id}`
  const [fields,setFields]=useState(()=>{try{const recovered=JSON.parse(sessionStorage.getItem(formKey));if(recovered)return recovered}catch{};return {nome:data.aluno.nome,foto:data.aluno.foto||'',genero:data.perfil.categoria||''}})
  const [busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('')
  useEffect(()=>{const preserve=()=>{try{sessionStorage.setItem(formKey,JSON.stringify(fields))}catch{}};window.addEventListener('power-system-before-login',preserve);return()=>window.removeEventListener('power-system-before-login',preserve)},[fields,formKey])
  useEffect(()=>{const confirmed=event=>{if(event.detail.path!=='/api/auth/perfil')return;const payload={...fields,foto:fields.foto.trim()||null,genero:fields.genero||null};if(JSON.stringify(payload)===event.detail.body){try{sessionStorage.removeItem(formKey)}catch{}}setMessage('Perfil atualizado.');onChanged()};window.addEventListener('power-system-write-confirmed',confirmed);return()=>window.removeEventListener('power-system-write-confirmed',confirmed)},[fields,formKey,onChanged])
  async function save(event){
    event.preventDefault();setBusy(true);setError('');setMessage('')
    try {
      await reliableMutation('/api/auth/perfil',{...fields,foto:fields.foto.trim()||null,genero:fields.genero||null})
      try{sessionStorage.removeItem(formKey)}catch{};setMessage('Perfil atualizado.');onChanged()
    }catch(failure){setError(errorMessage(failure))}finally{setBusy(false)}
  }
  return <div className="training-editor"><section className="athlete-panel"><p className="eyebrow">MEUS DADOS</p><h2>Meu perfil</h2>
    {error&&<p role="alert" className="auth-message auth-error">{error}</p>}{message&&<p role="status" className="editor-success">{message}</p>}
    <form onSubmit={save}><fieldset disabled={busy} className="student-profile-fields"><div className="editor-grid">
      <label>Nome<input required maxLength={120} autoComplete="name" value={fields.nome} onChange={event=>setFields({...fields,nome:event.target.value})}/></label>
      <label>E-mail da conta Google<input readOnly type="email" value={account.email||''}/></label>
      <label>Gênero<select value={fields.genero} onChange={event=>setFields({...fields,genero:event.target.value})}><option value="">Não informado</option><option value="masculino">Masculino</option><option value="feminino">Feminino</option></select></label>
    </div><button className="dashboard-action">{busy?'Salvando…':'Salvar perfil'}</button></fieldset></form>
  </section></div>
}
