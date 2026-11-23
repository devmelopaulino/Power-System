import { useEffect, useRef, useState } from 'react'

// A animação é executada pelo próprio SVG; o React controla apenas a pausa.
const timing = {
  dur: '4s',
  repeatCount: 'indefinite',
  keyTimes: '0;0.12;0.5;0.88;1',
  calcMode: 'spline',
  keySplines: '0.4 0 0.6 1;0.4 0 0.6 1;0.4 0 0.6 1;0.4 0 0.6 1',
}

function Leg({ standing, squatting, color, width }) {
  return (
    <path d={standing} stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" fill="none">
      <animate {...timing} attributeName="d" values={`${standing};${standing};${squatting};${standing};${standing}`} />
    </path>
  )
}

export default function SquatAnimation() {
  const drawing = useRef(null)
  const [paused, setPaused] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)

  useEffect(() => {
    if (paused) drawing.current.pauseAnimations()
    else drawing.current.unpauseAnimations()
  }, [paused])

  return (
    <div className="squat-animation">
      <svg ref={drawing} className="squat-drawing" viewBox="0 0 800 600" role="img" aria-labelledby="squat-title squat-description">
        <title id="squat-title">Agachamento com barra</title>
        <desc id="squat-description">Um atleta desenhado de frente flexiona os joelhos para fora, desce com a barra nos ombros e volta a ficar em pé. Os pés permanecem no chão.</desc>
        <ellipse cx="400" cy="552" rx="202" ry="13" fill="#acacb5" opacity=".14" />
        <path d="M120 552 H680" stroke="#686870" strokeWidth="1" opacity=".5" />

        {/* Na vista frontal, as coxas encurtam em perspectiva na descida.
            Os joelhos acompanham os pés e ficam abaixo do quadril na imagem. */}
        <Leg standing="M374 370 L339 446 L318 523" squatting="M374 465 L318 478 L318 523" color="#b57a45" width="41" />
        <Leg standing="M426 370 L461 446 L482 523" squatting="M426 465 L482 478 L482 523" color="#b57a45" width="41" />
        <Leg standing="M374 370 L352 417" squatting="M374 465 L342 472" color="#19191d" width="47" />
        <Leg standing="M426 370 L448 417" squatting="M426 465 L458 472" color="#19191d" width="47" />
        <Leg standing="M329 483 L318 523" squatting="M318 496 L318 523" color="#e7e7eb" width="38" />
        <Leg standing="M471 483 L482 523" squatting="M482 496 L482 523" color="#e7e7eb" width="38" />
        <path d="M305 522 H337 L337 549 H275 Q272 528 305 528 Z" fill="#e7e7eb" />
        <path d="M463 522 H495 L495 528 Q528 528 525 549 H463 Z" fill="#e7e7eb" />
        <path d="M275 549 H337 M463 549 H525" stroke="#bcbcc5" strokeWidth="6" />

        <g className="squat-upper">
          <animateTransform {...timing} attributeName="transform" type="translate" values="0 0;0 0;0 95;0 0;0 0" />
          <path d="M345 242 Q304 296 278 274 Q263 258 266 224 M455 242 Q496 296 522 274 Q537 258 534 224" fill="none" stroke="#b57a45" strokeWidth="28" strokeLinecap="round" />
          <path d="M61 222 H739" stroke="#9999a3" strokeWidth="15" />
          <path d="M82 218 H718" stroke="#d9d9e0" strokeWidth="3" />
          <rect x="110" y="154" width="104" height="138" rx="3" fill="#8d1427" />
          <rect x="121" y="150" width="83" height="146" rx="2" fill="#e51d36" />
          <rect x="100" y="166" width="10" height="115" rx="2" fill="#dddde4" />
          <rect x="586" y="154" width="104" height="138" rx="3" fill="#8d1427" />
          <rect x="596" y="150" width="83" height="146" rx="2" fill="#e51d36" />
          <rect x="690" y="166" width="10" height="115" rx="2" fill="#dddde4" />
          <path d="M90 200 V245 M710 200 V245" stroke="#2e2e35" strokeWidth="10" strokeLinecap="round" />
          <path d="M326 239 Q341 209 374 213 H426 Q459 209 474 239 L454 255 L442 244 L440 367 Q400 388 360 367 L358 244 L346 255 Z" fill="#34343c" />
          <path d="M363 218 L375 216 Q383 264 400 264 Q417 264 425 216 L437 218 L439 373 Q400 389 361 373 Z" fill="#111114" />
          <rect x="366" y="333" width="68" height="17" rx="3" fill="#4c4c55" />
          <rect x="391" y="336" width="18" height="11" rx="1" fill="none" stroke="#c9c9d1" strokeWidth="3" />
          <path d="M381 199 H419 V224 Q400 247 381 224 Z" fill="#a56c3b" />
          <path d="M368 137 Q400 121 432 137 V181 Q431 214 400 221 Q369 214 368 181 Z" fill="#b57a45" />
          <path d="M368 140 V119 Q373 106 381 117 Q387 104 393 116 Q401 102 408 116 Q416 105 422 117 Q432 109 432 123 V142 Z" fill="#111114" />
          <path d="M368 145 H432 V160 H368 Z" fill="#dddde4" />
          <path d="M373 151 H426" stroke="#e51d36" strokeWidth="5" />
          <circle cx="386" cy="176" r="4" fill="#111114" /><circle cx="414" cy="176" r="4" fill="#111114" />
          <path d="M394 198 Q400 203 406 198" fill="none" stroke="#663d26" strokeWidth="3" strokeLinecap="round" />
          <path d="M259 218 H277 M523 218 H541" stroke="#b57a45" strokeWidth="13" strokeLinecap="round" />
          <path d="M264 214 V223 M273 214 V223 M527 214 V223 M536 214 V223" stroke="#9d6538" strokeWidth="2" />
        </g>
      </svg>
      <button className="animation-toggle" onClick={() => setPaused((value) => !value)} aria-pressed={paused} aria-label={paused ? 'Reproduzir animação de agachamento' : 'Pausar animação de agachamento'}>
        {paused ? '▶ Reproduzir animação' : 'Ⅱ Pausar animação'}
      </button>
    </div>
  )
}
