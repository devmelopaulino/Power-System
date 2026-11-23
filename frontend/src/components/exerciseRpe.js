export const isMainExercise = exercise => ['agachamento','supino','terra'].includes(exercise.movimento)
export const prescribedMaximum = exercise => Math.max(0,...exercise.series.map(row=>row.cargaPrevista))
export const executedMaximum = rows => rows.some(row=>row.carga!=null)?Math.max(...rows.filter(row=>row.carga!=null).map(row=>Number(String(row.carga).replace(',','.')))):null
export function executionRows(exercise,hasChanges){return exercise.series.map(row=>hasChanges?{...row}:{...row,repeticoes:row.repeticoesPrevistas,carga:row.cargaPrevista})}
export function applyExerciseRpe(exercise,hasChanges,action={mode:'keep'}){
 const rows=executionRows(exercise,hasChanges),maximum=executedMaximum(rows)
 if(action.mode==='set'&&(!Number.isFinite(Number(action.value))||Number(action.value)<1||Number(action.value)>10))throw new Error(`Informe um RPE entre 1 e 10 para ${exercise.nome}.`)
 return {...exercise,series:rows.map(row=>({...row,rpe:row.carga==null||action.mode==='clear'?null:action.mode==='set'&&row.carga===maximum?Number(action.value):row.rpe}))}
}
export function reportedRpe(exercise){const maximum=executedMaximum(exercise.series);return [...new Set(exercise.series.filter(row=>row.carga!=null&&String(row.carga).trim()!==''&&Number(String(row.carga).replace(',','.'))===maximum).map(row=>row.rpe).filter(value=>value!=null))]}
