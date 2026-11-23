const movements = {agachamento:'Agachamento',supino:'Supino',terra:'Terra'}
export function metricAvailability(profile={},kpis={}) {
 const missing=Object.keys(movements).filter(key=>kpis[key]?.valor==null).map(key=>movements[key])
 const total=kpis.total==null?(missing.length?`Falta registrar ${missing.join(', ')} para calcular o Total.`:'Total indisponível. Atualize os dados para tentar novamente.') : ''
 const requirements=[]
 if(!(profile.peso>0))requirements.push('registrar o peso corporal')
 if(!['masculino','feminino'].includes(profile.categoria))requirements.push('informar o gênero nos dados do perfil')
 if(kpis.total==null)requirements.push(missing.length?`registrar ${missing.join(', ')} para completar o Total`:'completar o Total')
 if(kpis.total!=null&&kpis.total<=0)requirements.push('registrar um Total maior que zero')
 const dots=profile.dots==null?(requirements.length?`Para calcular DOTS: ${requirements.join('; ')}.`:'DOTS indisponível. Atualize os dados para tentar novamente.') : ''
 return {total,dots}
}
