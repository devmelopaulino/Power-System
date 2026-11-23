import {executionRows,executedMaximum} from './exerciseRpe.js'
const num=value=>new Intl.NumberFormat('pt-BR',{maximumFractionDigits:1}).format(value)
export default function ExerciseRpePicker({exercise,hasChanges,action={mode:'keep'},onChange,disabled}){
 const maximum=executedMaximum(executionRows(exercise,hasChanges))
 return <fieldset className="rpe-picker"><legend>RPE real — {exercise.nome}</legend><p className="athlete-note">{maximum==null?'Nenhuma série realizada neste exercício.':`Esforço das séries realizadas com ${num(maximum)} kg.`}</p><div>
 {Array.from({length:15},(_,index)=>3+index*.5).map(value=><button type="button" key={value} disabled={disabled||maximum==null} aria-pressed={action.mode==='set'&&Number(action.value)===value} onClick={()=>onChange({mode:'set',value})}>{num(value)}</button>)}
 <button type="button" disabled={disabled} aria-pressed={action.mode==='keep'} onClick={()=>onChange({mode:'keep'})}>Manter registrado</button>
 <button type="button" disabled={disabled} aria-pressed={action.mode==='clear'} onClick={()=>onChange({mode:'clear'})}>Não informar / remover RPE</button>
 </div><label>Outro valor (1 a 10)<input type="number" min="1" max="10" step="0.5" disabled={disabled||maximum==null} value={action.mode==='set'?action.value:''} onChange={event=>onChange(event.target.value===''?{mode:'clear'}:{mode:'set',value:Number(event.target.value)})}/></label>
 {action.mode==='clear'&&<p role="status" className="athlete-note">Ao salvar, os RPEs registrados neste exercício serão removidos.</p>}
 <details><summary>Como avaliar o RPE?</summary><p>10: nenhuma repetição sobrando. 9: mais uma. 8: mais duas. 7: mais três.</p></details></fieldset>
}
