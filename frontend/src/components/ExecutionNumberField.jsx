import {useId} from 'react'
import {executionNumberError} from './executionNumbers.js'
export default function ExecutionNumberField({value,kind,label,disabled,onChange}) {
 const id=useId(),error=executionNumberError(value,kind)
 return <label>{label}<input type="text" inputMode={kind==='repeticoes'?'numeric':'decimal'} disabled={disabled} value={value??''} onChange={event=>onChange(event.target.value)} aria-invalid={!!error} aria-describedby={error?id:undefined}/>{error&&<small id={id} className="field-error" role="status">{error}</small>}</label>
}
