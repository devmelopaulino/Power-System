import SquatAnimation from '../components/SquatAnimation.jsx'

const lifts = [
  { number: '01', name: 'Agachamento', english: 'Squat', description: 'A base de um treino de força bem estruturado.' },
  { number: '02', name: 'Supino', english: 'Bench press', description: 'Consistência e precisão em cada repetição.' },
  { number: '03', name: 'Levantamento terra', english: 'Deadlift', description: 'Força construída, sessão após sessão.' },
]

export default function HomePage() {
  return (
    <div className="site-shell">
      <a className="skip-link" href="#conteudo">Pular para o conteúdo</a>
      <header className="site-header">
        <a className="brand" href="#inicio" aria-label="Power System — início">
          <span className="brand-mark" aria-hidden="true"><i /><i /><i /></span>
          POWER<span className="brand-light">SYSTEM</span>
        </a>
        <nav aria-label="Navegação principal">
          <a href="#projeto">O projeto</a>
          <a href="#movimentos">Os movimentos <span aria-hidden="true">↗</span></a>
          <a className="auth-nav-link" href="#/entrar">Entrar <span aria-hidden="true">↗</span></a>
        </nav>
      </header>

      <main id="conteudo">
        <section className="hero" id="inicio" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow"><span /> PLANEJAMENTO. CONSISTÊNCIA. EVOLUÇÃO.</p>
            <h1 id="hero-title">FORÇA COM<br /><span>DIREÇÃO.</span></h1>
            <p className="hero-description">Sistema para gerenciamento de treinamento de <strong>powerlifting</strong>.</p>
            <p className="hero-support">Uma proposta para organizar a preparação, registrar o trabalho e acompanhar a evolução nos três grandes movimentos.</p>
            <a className="primary-link" href="#projeto">Conheça o projeto <span aria-hidden="true">↗</span></a>
            <a className="register-link" href="#/cadastro">Criar minha conta →</a>
          </div>
          <div className="hero-art hero-art-squat">
            <div className="art-topline"><span>POWER SYSTEM</span><span>EST. 2026</span></div>
            <div className="art-grid" />
            <div className="art-ring ring-one" /><div className="art-ring ring-two" />
            <SquatAnimation />
            <div className="art-bottomline"><span>SQUAT / BENCH / DEADLIFT</span><span>01 — 03</span></div>
          </div>
        </section>

        <section className="project-section" id="projeto" aria-labelledby="project-title">
          <div>
            <p className="eyebrow">O PROJETO</p>
            <h2 id="project-title">Cada sessão faz parte<br />de algo maior.</h2>
          </div>
          <div className="project-copy">
            <p>O Power System nasce com um objetivo: tornar o gerenciamento do treinamento de powerlifting mais organizado e fácil de acompanhar.</p>
            <p>A proposta é reunir o planejamento de treinos, o registro de séries, repetições e cargas e o acompanhamento da evolução em um só lugar.</p>
            <div className="development-note"><span className="status-dot" /><span>Em desenvolvimento — esta é a apresentação do projeto. As ferramentas de treinamento serão adicionadas nas próximas etapas.</span></div>
          </div>
        </section>

        <section className="lifts-section" id="movimentos" aria-labelledby="lifts-title">
          <div className="section-heading">
            <div><p className="eyebrow">A ESSÊNCIA DO POWERLIFTING</p><h2 id="lifts-title">Três movimentos.<br />Um propósito: evoluir.</h2></div>
            <p>Agachamento, supino e levantamento terra.<br />O ponto de partida da nossa proposta.</p>
          </div>
          <div className="lift-grid">
            {lifts.map((lift) => (
              <article className="lift-card" key={lift.number}>
                <div className="lift-top"><span>{lift.number}</span><span className="lift-cross" aria-hidden="true">+</span></div>
                <p className="lift-english">{lift.english}</p>
                <h3>{lift.name}</h3>
                <p className="lift-description">{lift.description}</p>
              </article>
            ))}
          </div>
        </section>
      </main>

      <footer className="site-footer"><span>POWER SYSTEM</span><p>Planeje o trabalho. Construa sua força.</p><a href="#inicio">Voltar ao topo ↑</a></footer>
    </div>
  )
}
