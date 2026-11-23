export function trainingToday(instant = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(instant)
  const value = type => parts.find(part=>part.type===type).value
  return `${value('year')}-${value('month')}-${value('day')}`
}
