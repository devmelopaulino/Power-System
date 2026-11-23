// Initialize execution once; toggling the adjustment UI must never restore skipped sets.
export function initializeExecution(session, initialized) {
  if (initialized) return session
  return {...session,exercicios:session.exercicios.map(exercise=>({...exercise,series:exercise.series.map(row=>row.carga!=null?row:{...row,carga:row.cargaPrevista,repeticoes:row.repeticoesPrevistas})}))}
}
