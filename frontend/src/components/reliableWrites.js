import {apiError,readApiResponse} from './apiErrors.js'
let activeAccount=null
const confirmations=new Map()
const PREFIX='power-system-write:v1:'
const scopeOf=account=>`${account.perfil}:${account.id}`
const notify=()=>{if(typeof window!=='undefined')window.dispatchEvent(new Event('power-system-write-state'))}
export function setWriteAccount(account){activeAccount=account;notify()}
export function pendingWrites(account){if(!account)return [];const prefix=PREFIX+scopeOf(account)+':',rows=[];for(let i=0;i<localStorage.length;i++){const key=localStorage.key(i);if(!key?.startsWith(prefix))continue;try{const value=JSON.parse(localStorage.getItem(key));if(value&&value.path&&value.body)rows.push(value)}catch{}}return rows.sort((a,b)=>a.createdAt.localeCompare(b.createdAt))}
function store(record){localStorage.setItem(PREFIX+record.scope+':'+record.key,JSON.stringify(record));notify()}
function remove(record){localStorage.removeItem(PREFIX+record.scope+':'+record.key);notify()}
export const writeConfirmation=account=>account?confirmations.get(scopeOf(account))||'':''
export function clearWriteConfirmation(account){if(account)confirmations.delete(scopeOf(account));notify()}
export function rememberReturn(){window.dispatchEvent(new Event('power-system-before-login'));if(activeAccount)sessionStorage.setItem('power-system-return',JSON.stringify({scope:scopeOf(activeAccount),path:window.location.hash.slice(1)}))}
export function resumeReturn(account){try{const raw=sessionStorage.getItem('power-system-return');if(!raw)return;const value=JSON.parse(raw);sessionStorage.removeItem('power-system-return');if(value.scope===scopeOf(account)&&/^\/(alunos(?:\/\d+(?:\/(?:treino|dados))?)?|meus-treinos|meu-perfil|meu-peso|minha-evolucao)(?:\?.*)?$/.test(value.path))window.location.hash=value.path}catch{}}
async function accountForWrite(){if(activeAccount)return activeAccount;const response=await fetch('/api/auth/me',{cache:'no-store'});activeAccount=await readApiResponse(response,'Não foi possível verificar sua conta. Tente novamente.');return activeAccount}
export async function reliableMutation(path,body){
 const account=await accountForWrite(),scope=scopeOf(account),encoded=JSON.stringify(body)
 let rows;try{rows=pendingWrites(account)}catch{throw new Error('Não foi possível preservar a tentativa neste navegador. Nenhum dado foi enviado.')}
 const pending=rows.find(record=>record.path===path)
 if(pending&&pending.body!==encoded)throw new Error('Existe um salvamento anterior sem confirmação nesta tela. Confirme-o na área de salvamentos pendentes antes de enviar dados diferentes.')
 const record=pending||{key:body.operacaoId||crypto.randomUUID(),scope,path,body:encoded,createdAt:new Date().toISOString(),label:body.titulo||(/pesagens/.test(path)?'Registro de peso':/treinos/.test(path)?'Atualização de treino':'Dados do perfil'),returnPath:window.location.hash.slice(1),state:'sending'}
 try{store({...record,state:'sending'})}catch{throw new Error('Não foi possível preservar a tentativa neste navegador. Nenhum dado foi enviado.')}
 return sendRecord(record,false)
}
async function sendRecord(record,recovered){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000)
 let response,result
 try{response=await fetch(record.path,{method:'POST',headers:{'Content-Type':'application/json','X-Power-System-Request':'1','X-Power-System-Account':record.scope,'Idempotency-Key':record.key},body:record.body,signal:controller.signal});result=await response.json()}
 catch{store({...record,state:'uncertain'});throw new Error('Não foi possível confirmar o salvamento. A tentativa foi preservada: use Confirmar salvamento para verificar sem duplicar registros.')}
 finally{clearTimeout(timer)}
 if(response.status===401){window.dispatchEvent(new Event('power-system-session-expired'));store({...record,state:'login'});rememberReturn();const error=new Error('Sua sessão expirou. A tentativa foi preservada. Entre novamente para confirmar o salvamento.');error.status=401;throw error}
 if(response.status>=500){store({...record,state:'uncertain'});const error=new Error('O servidor não confirmou o salvamento. Seus dados foram preservados para uma nova tentativa segura.');error.status=response.status;throw error}
 if(!response.ok){remove(record);throw apiError(response.status,result.erro,'Não foi possível salvar. Revise os dados e tente novamente.')}
 remove(record)
 if(recovered){confirmations.set(record.scope,'Salvamento confirmado. O registro não foi duplicado.');notify()}
 if(recovered)window.dispatchEvent(new CustomEvent('power-system-write-confirmed',{detail:{...record,payload:JSON.parse(record.body),result}}))
 return result
}
export async function confirmPendingWrite(record){if(!activeAccount||record.scope!==scopeOf(activeAccount))throw new Error('Entre com a mesma conta que iniciou este salvamento.');return sendRecord(record,true)}
