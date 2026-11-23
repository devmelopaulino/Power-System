export function executionNumberError(value,kind) {
 const raw=String(value??'').trim(),isReps=kind==='repeticoes'
 if(!raw)return isReps?'Informe as repetições.':'Informe a carga; use 0 apenas se não houve carga externa.'
 if(!/^-?\d+(?:[.,]\d+)?$/.test(raw))return 'Digite um número válido.'
 const number=Number(raw.replace(',','.'))
 if(!Number.isFinite(number)||number<(isReps?1:0)||number>(isReps?100:1500))return isReps?'Use de 1 a 100 repetições.':'Use uma carga de 0 a 1.500 kg.'
 if(isReps&&!Number.isInteger(number))return 'As repetições devem ser um número inteiro.'
 return ''
}
export function validatedExecution(exercise) {
 return {...exercise,series:exercise.series.map((row,index)=>{
  if(row.carga==null)return {...row,carga:null,repeticoes:null,rpe:null}
  for(const key of ['carga','repeticoes']){const error=executionNumberError(row[key],key);if(error)throw new Error(`${exercise.nome}, série ${index+1}: ${error}`)}
  return {...row,carga:Number(String(row.carga).replace(',','.')),repeticoes:Number(row.repeticoes)}
 })}
}
export function matchesPrescription(row) {
 return !executionNumberError(row.carga,'carga')&&!executionNumberError(row.repeticoes,'repeticoes')
  &&Number(String(row.carga).replace(',','.'))===row.cargaPrevista&&Number(row.repeticoes)===row.repeticoesPrevistas
}
