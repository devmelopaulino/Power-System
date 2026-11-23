export const chartPointKey = point => point.id!=null?`id:${point.id}`:`date:${point.data}`
export const selectionIndex = (points,metric,selection) => !selection||selection.metric!==metric?-1:points.findIndex(point=>chartPointKey(point)===selection.key)
