export const plannedDay = session => session.dataPrevista || session.dataTreino
export const calendarDay = (session, basis = 'realizada') => basis === 'prevista' ? plannedDay(session) : session.dataRealizada || plannedDay(session)
