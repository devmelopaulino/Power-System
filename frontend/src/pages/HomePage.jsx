import './HomePage.css'

const features = [
  ['01', 'Prescrição organizada', 'Monte sessões com exercícios, séries, repetições, cargas e RPE previsto. Deixe as orientações junto do treino.'],
  ['02', 'Execução registrada', 'O aluno conclui o treino, informa o esforço e registra ajustes quando realiza algo diferente do planejado.'],
  ['03', 'Evolução visível', 'Acompanhe as maiores cargas, o Total histórico, o volume de treino e a pontuação DOTS de referência.'],
  ['04', 'Agenda de treinos', 'Consulte sessões previstas, concluídas e parciais no calendário. Abra cada treino para ver os detalhes.'],
  ['05', 'Peso corporal', 'Registre pesagens e acompanhe o histórico, a tendência e a distância até a meta de peso definida.'],
  ['06', 'Histórico preservado', 'Consulte as alterações das sessões. Correções e anulações mantêm um histórico do que foi modificado.'],
]

function TrainingPreview() {
  return <aside className="landing-preview" aria-label="Exemplo ilustrativo de uma prescrição">
    <div className="landing-preview-top"><span><i aria-hidden="true"/> VISÃO DO TREINO</span><span>Exemplo ilustrativo</span></div>
    <div className="landing-preview-title"><div><p>SESSÃO DE FORÇA</p><h2>Agachamento</h2></div><span className="landing-scheduled">Agendado</span></div>
    <div className="landing-prescription-summary"><div><span>Maior carga prevista</span><strong>140 <small>kg</small></strong></div><div><span>RPE previsto nas séries mais pesadas</span><strong>8 <small>/ 10</small></strong></div></div>
    <div className="landing-preview-table"><table><caption className="sr-only">Séries de exemplo, sem execução registrada</caption><thead><tr><th scope="col">Séries</th><th scope="col">Repetições</th><th scope="col">Carga</th></tr></thead><tbody>{[[1,6,60],[1,4,100],[3,3,140]].map(([sets,reps,load])=><tr key={load}><td>{sets}</td><td>{reps}</td><td>{load} <span>kg</span></td></tr>)}</tbody></table></div>
    <div className="landing-preview-note"><span aria-hidden="true">↗</span><p>O planejamento é o ponto de partida.<br/><strong>A evolução vem do que foi realizado.</strong></p></div>
    <div className="landing-movements"><span>AGACHAMENTO</span><span>SUPINO</span><span>TERRA</span></div>
  </aside>
}

export default function HomePage() {
  return <div className="site-shell landing-page" id="inicio">
    <a className="skip-link" href="#conteudo">Pular para o conteúdo</a>
    <header className="site-header">
      <a className="brand" href="#inicio" aria-label="Power System — início"><span className="brand-mark" aria-hidden="true"><i/><i/><i/></span>POWER<span className="brand-light">SYSTEM</span></a>
      <nav aria-label="Navegação principal"><a className="landing-section-link" href="#recursos">Recursos</a><a className="landing-section-link" href="#como-funciona">Como funciona</a><a className="landing-login" href="#/entrar">Entrar <span aria-hidden="true">↗</span></a></nav>
    </header>
    <main id="conteudo">
      <section className="landing-hero" aria-labelledby="landing-title">
        <div className="landing-intro"><p className="eyebrow">GESTÃO DE TREINAMENTO DE POWERLIFTING</p><h1 id="landing-title">Da prescrição<br/>à <span>evolução.</span></h1><p className="landing-lead">Treinador e aluno, conectados em cada sessão.</p><p className="landing-description">Organize os treinos, registre o que foi realizado e acompanhe cargas, esforço e peso corporal em um só lugar.</p><div className="landing-actions"><a className="landing-primary" href="#/cadastro">Começar como treinador <span aria-hidden="true">↗</span></a><a className="landing-secondary" href="#/entrar">Já tenho acesso</a></div><p className="landing-invite-hint">É aluno? Seu primeiro acesso começa pelo link de convite do treinador.</p></div>
        <TrainingPreview/>
      </section>
      <section className="landing-features landing-section" id="recursos" aria-labelledby="features-title"><div className="landing-section-heading"><div><p className="eyebrow">DO PLANEJAMENTO AO HISTÓRICO</p><h2 id="features-title">O treino inteiro.<br/>No mesmo lugar.</h2></div><p>Mais clareza para prescrever.<br/>Mais contexto para acompanhar.</p></div><div className="landing-feature-grid">{features.map(([number,title,description])=><article className="landing-feature" key={number}><span className="landing-feature-number">{number}</span><h3>{title}</h3><p>{description}</p></article>)}</div></section>
      <section className="landing-roles landing-section" aria-labelledby="roles-title"><div className="landing-section-heading"><div><p className="eyebrow">DOIS ACESSOS. UM ACOMPANHAMENTO.</p><h2 id="roles-title">Cada pessoa com<br/>o que precisa.</h2></div></div><div className="landing-role-grid"><article><span className="landing-role-tag">PARA O TREINADOR</span><h3>Planeje com contexto.</h3><p>Veja seus alunos, consulte o perfil individual e use o histórico para preparar as próximas sessões.</p><ul><li>Prescrição e edição de treinos por aluno.</li><li>Indicadores, gráficos e calendário de sessões.</li><li>Convites para conectar cada aluno à sua área.</li></ul><a href="#/cadastro">Criar conta de treinador <span aria-hidden="true">↗</span></a></article><article><span className="landing-role-tag">PARA O ALUNO</span><h3>Leve seu treino com você.</h3><p>No celular, consulte a próxima sessão, registre a execução e acompanhe sua própria evolução.</p><ul><li>Treinos previstos e conclusão com registro de ajustes.</li><li>RPE real nas séries mais pesadas de cada movimento.</li><li>Área de peso corporal e evolução das cargas.</li></ul><a href="#/entrar">Entrar na minha conta <span aria-hidden="true">↗</span></a></article></div></section>
      <section className="landing-process landing-section" id="como-funciona" aria-labelledby="process-title"><div className="landing-section-heading"><div><p className="eyebrow">COMO FUNCIONA</p><h2 id="process-title">Um fluxo simples.<br/>Um histórico que continua.</h2></div></div><ol><li><span>01</span><h3>Conecte</h3><p>O treinador cria sua conta com Google e compartilha um convite. O aluno entra com Google e confirma seu cadastro.</p></li><li><span>02</span><h3>Treine</h3><p>O treinador prescreve. O aluno consulta a sessão, conclui o treino e informa o que mudou na execução.</p></li><li><span>03</span><h3>Acompanhe</h3><p>Os registros alimentam o calendário e os indicadores, disponíveis tanto para o treinador quanto para o aluno.</p></li></ol></section>
      <section className="landing-start" aria-labelledby="start-title"><div><p className="eyebrow">O PRÓXIMO TREINO COMEÇA NO PLANEJAMENTO</p><h2 id="start-title">Dê direção à sua força.</h2><p>Acesse com sua conta Google, sem criar outra senha.</p></div><a className="landing-primary" href="#/entrar">Entrar no Power System <span aria-hidden="true">↗</span></a></section>
    </main>
    <footer className="site-footer"><span>POWER SYSTEM</span><p>Planeje. Registre. Evolua.</p><a href="#inicio">Voltar ao topo ↑</a></footer>
  </div>
}
