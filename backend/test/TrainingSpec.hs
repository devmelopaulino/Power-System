{-# LANGUAGE OverloadedStrings #-}
module TrainingSpec (checkTraining) where
import App.Time (appToday, appDayAt)
import Auth.Store
import qualified Training.Profile as P
import Control.Concurrent (forkIO,newEmptyMVar,putMVar,takeMVar)
import Control.Exception (try,SomeException)
import Control.Monad (unless)
import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Aeson.KeyMap as KM
import Data.Int (Int64)
import Data.Maybe (isJust)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time
import Database.Connection
import Database.PostgreSQL.Simple (Only(..),query,execute)
import Network.HTTP.Types
import Network.Wai (Application, Request(..))
import Network.Wai.Test
import System.Exit (die)
import System.Environment (lookupEnv)

check :: String -> Bool -> IO ()
check label ok = unless ok (die ("FALHOU perfil: " ++ label))
at :: FromJSON a => [Key] -> Value -> Maybe a
at [] value = case fromJSON value of Success result -> Just result; _ -> Nothing
at (key:keys) (Object fields) = KM.lookup key fields >>= at keys
at _ _ = Nothing

checkTraining :: Database -> Application -> Account -> Account -> T.Text -> T.Text -> T.Text -> IO ()
checkTraining database application first second firstToken secondToken studentToken = do
 today <- appToday
 identifiers <- withDatabase database $ \connection -> query connection "SELECT id FROM alunos WHERE treinador_id=? ORDER BY id LIMIT 1" (Only (accountId first)) :: IO [Only Int64]
 studentId <- case identifiers of [Only identifier] -> pure identifier; _ -> die "Aluno de teste ausente"
 let route suffix = "/api/alunos/" <> encodeUtf8 (T.pack (show studentId)) <> suffix
     getFor token suffix = (setPath defaultRequest (route suffix)) {requestHeaders=[("Cookie","ps_session="<>encodeUtf8 token)]}
     postFor token suffix = (getFor token suffix) {requestMethod="POST", requestHeaders=[("Cookie","ps_session="<>encodeUtf8 token),("Origin","http://localhost:5173"),("X-Power-System-Request","1"),("Content-Type","application/json")]}
     sendPost token suffix body = do
      key <- newToken
      let requestWithKey=(postFor token suffix){requestHeaders=("Idempotency-Key",encodeUtf8 key):requestHeaders(postFor token suffix)}
      runSession (srequest (SRequest requestWithKey (encode body))) application
     profile = P.ProfileInput Nothing (Just "masculino") "Bloco de Força" (Just (addDays (-14) today)) 4 (Just 82) today
     exercise movement load = P.Exercise movement movement [P.TrainingSet 1 load (Just 1) (Just load) (Just 8)] Nothing Nothing
     session day title exercises = P.TrainingSession Nothing day title True exercises "Boa execução" "https://example.com/video" P.defaultPlan Nothing Nothing Nothing "ativa" Nothing
 check "DOTS masculino de referencia" (maybe False (\v -> abs (v-452.6)<0.1) (P.dots "masculino" 90 700))
 check "DOTS feminino e limites" (isJust (P.dots "feminino" 60 400) && P.dots "masculino" 20 700 == P.dots "masculino" 40 700 && P.dots "feminino" 160 400 == P.dots "feminino" 150 400)
 check "DOTS sem total ou categoria" (P.dots "" 80 600 == Nothing && P.dots "masculino" 80 0 == Nothing)
 empty <- P.studentProfile database first studentId 30 "semana"
 check "sem dados nao inventa PR e DOTS" ((at ["kpis","total"] empty :: Maybe (Maybe Double)) == Just Nothing && (at ["perfil","dots"] empty :: Maybe (Maybe Double)) == Just Nothing)
 forbidden <- runSession (request (getFor secondToken "/perfil")) application
 check "outro treinador nao le perfil" (simpleStatus forbidden == status404)
 studentDenied <- runSession (request (getFor studentToken "/perfil")) application
 check "aluno nao acessa painel do treinador" (simpleStatus studentDenied == status403)
 anonymous <- runSession (request (setPath defaultRequest (route "/perfil"))) application
 check "perfil exige sessao" (simpleStatus anonymous == status401)
 badOwner <- sendPost secondToken "/perfil" profile
 check "outro treinador nao altera perfil" (simpleStatus badOwner == status404)
 saved <- sendPost firstToken "/perfil" profile
 check "salva perfil e pesagem" (simpleStatus saved == status200)
 let ownAccount = first {accountRole="aluno",accountId=studentId}
 currentWeightSaved <- P.recordWeight database ownAccount (P.WeightInput 82 today "manual")
 check "peso informado pelo aluno" currentWeightSaved
 voidWeight <- P.recordWeight database ownAccount (P.WeightInput 80 (addDays (-8) today) "treino")
 check "persiste pesagem historica" voidWeight
 badWeight <- sendPost firstToken "/perfil" profile {P.peso=Just (-5)}
 check "recusa peso invalido" (simpleStatus badWeight == status400)
 unsafe <- runSession (srequest (SRequest ((getFor firstToken "/perfil"){requestMethod="POST"}) (encode profile))) application
 check "mutacao exige CSRF" (simpleStatus unsafe == status403)
 let firstSession = session today "SBD" [exercise "agachamento" 200,exercise "supino" 150,exercise "terra" 250]
 firstSave <- sendPost firstToken "/treinos" firstSession
 check "salva prescricao e execucao" (simpleStatus firstSave == status200)
 let sets = [P.TrainingSet 1 210 (Just 1) (Just 210) (Just 9),P.TrainingSet 5 100 (Just 5) (Just 100) (Just 7),P.TrainingSet 5 110 (Just 5) (Just 110) (Just 8)]
     secondSession = session today "Agachamento e volume" [P.Exercise "Agachamento" "agachamento" sets Nothing Nothing]
 check "volume soma cargas diferentes por serie" (P.sessionVolume secondSession == 1260)
 secondSave <- sendPost firstToken "/treinos" secondSession
 check "salva segunda sessao no mesmo dia" (simpleStatus secondSave == status200)
 previousSave <- sendPost firstToken "/treinos" (session (addDays (-7) today) "Semana passada" [exercise "agachamento" 100,exercise "supino" 100,exercise "terra" 100])
 check "salva historico anterior" (simpleStatus previousSave == status200)
 let future = (session (addDays 1 today) "Agendado" [P.Exercise "Supino" "supino" [P.TrainingSet 5 100 Nothing Nothing Nothing] Nothing Nothing]) {P.concluido=False}
 futureSave <- sendPost firstToken "/treinos" future
 check "prescricao futura sem execucao" (simpleStatus futureSave == status200)
 futureExecution <- sendPost firstToken "/treinos" firstSession {P.dataTreino=addDays 1 today}
 check "nao aceita execucao no futuro" (simpleStatus futureExecution == status400)
 wrongTrainer <- sendPost secondToken "/treinos" firstSession
 check "outro treinador nao prescreve" (simpleStatus wrongTrainer == status404)
 calculated <- P.studentProfile database first studentId 30 "semana"
 fixturePath <- lookupEnv "PROFILE_TEST_OUTPUT"
 case fixturePath of Just path -> LBS.writeFile path (encode calculated); Nothing -> pure ()
 check "PR e RPE da serie correta" ((at ["kpis","agachamento","valor"] calculated :: Maybe Double)==Just 210 && (at ["kpis","agachamento","rpe"] calculated :: Maybe Double)==Just 9)
 check "total dos tres melhores singles" ((at ["kpis","total"] calculated :: Maybe Double)==Just 610)
 check "volume semanal apenas executado" ((at ["kpis","volume"] calculated :: Maybe Double)==Just 1860)
 check "variacao comparavel semana anterior" ((at ["kpis","variacao"] calculated :: Maybe Double)==Just 520)
 check "peso atual e DOTS servidor" ((at ["perfil","peso"] calculated :: Maybe Double)==Just 82 && (at ["perfil","dots"] calculated :: Maybe Double)==P.dots "masculino" 82 610)
 check "semana automatica bloco" ((at ["perfil","semanaAtual"] calculated :: Maybe Int)==Just 3)
 overview <- P.studentOverview database first
 let overviewRows = case fromJSON overview of Success rows -> rows; _ -> [] :: [Value]
     selectedRows = filter (\row -> (at ["id"] row :: Maybe Int64)==Just studentId) overviewRows
 check "tabela mostra maximas e total do aluno" (case selectedRows of
  [row] -> (at ["agachamento"] row :: Maybe Double)==Just 210
    && (at ["supino"] row :: Maybe Double)==Just 150
    && (at ["terra"] row :: Maybe Double)==Just 250
    && (at ["total"] row :: Maybe Double)==Just 610
    && (at ["email"] row :: Maybe T.Text)==Nothing
  _ -> False)
 otherOverview <- P.studentOverview database second
 check "tabela de maximas isola treinadores" (case fromJSON otherOverview of
  Success rows -> all (\row -> (at ["id"] row :: Maybe Int64)/=Just studentId) (rows :: [Value])
  _ -> False)
 let dailyPoints = at ["historico","agachamento"] calculated :: Maybe [Value]
 check "grafico tem apenas a serie mais pesada por dia" (case dailyPoints of
  Just [_,point] -> (at ["valor"] point :: Maybe Double)==Just 210 && (at ["repeticoes"] point :: Maybe Int)==Just 1 && (at ["rpe"] point :: Maybe Double)==Just 9
  _ -> False)
 check "percentual usa o PR de todo o historico" (case dailyPoints of
  Just [older,latest] -> maybe False (\n -> abs(n-100/210*100)<0.001) (at ["percentualPr"] older :: Maybe Double)
    && (at ["prMovimento"] older :: Maybe Double)==Just 210
    && (at ["percentualPr"] latest :: Maybe Double)==Just 100
  _ -> False)
 result <- runSession (request (getFor firstToken "/perfil?periodo=90&volume=mes")) application
 check "API retorna analise e calendario" (simpleStatus result==status200 && case eitherDecode (simpleBody result) of Right value -> isJust (at ["calendario"] value :: Maybe [Value]); Left _ -> False)
 -- Upsert updates the existing session rather than duplicating its volume.
 ids <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='Agachamento e volume'" (Only studentId) :: IO [Only Int64]
 case ids of
  [Only identifier] -> do
   update <- sendPost firstToken "/treinos" secondSession {P.id=Just identifier,P.versao=Just 1,P.motivoAlteracao=Just "Revisao da prescricao"}
   check "editar sessao existente" (simpleStatus update==status200)
   unchanged <- P.studentProfile database first studentId 30 "semana"
   check "edicao nao duplica volume" ((at ["kpis","volume"] unchanged :: Maybe Double)==Just 1860)
   stolen <- sendPost secondToken "/treinos" secondSession {P.id=Just identifier,P.versao=Just 1,P.motivoAlteracao=Just "Revisao da prescricao"}
   check "id de sessao nao permite acesso externo" (simpleStatus stolen==status404)
  _ -> die "Sessao de teste ausente"
 beforePrescription <- P.athleteData database first studentId
 let plan = P.Plan "treino" "Barra vazia, 2 series de 10" (Just 220) (Just 8)
     trainingWithPlan = secondSession {P.prescricao=plan}
 plannedSave <- sendPost firstToken "/treinos" trainingWithPlan
 check "salva aquecimento carga maxima e RPE previsto" (simpleStatus plannedSave==status200)
 afterPrescription <- P.athleteData database first studentId
 check "prescricao preserva peso atual e historico integral" (beforePrescription==afterPrescription)
 metadataSave <- sendPost firstToken "/perfil" profile {P.peso=Just 55}
 check "metadados antigos nao sobrescrevem peso" (simpleStatus metadataSave==status200)
 afterMetadata <- P.athleteData database first studentId
 check "peso protegido de formulario antigo" (afterMetadata==beforePrescription)
 let rest = secondSession {P.titulo="Descanso",P.exercicios=[],P.prescricao=P.Plan "descanso" "" Nothing Nothing}
 restSave <- sendPost firstToken "/treinos" rest
 check "salva dia de descanso sem series" (simpleStatus restSave==status200)
 badRest <- sendPost firstToken "/treinos" rest {P.exercicios=P.exercicios secondSession}
 check "descanso nao aceita cargas executadas" (simpleStatus badRest==status400)
 repeatedWeight <- P.recordWeight database ownAccount (P.WeightInput 83 today "descanso")
 latestWeight <- P.athleteData database first studentId
 check "checkin atualiza peso e preserva pesagens do mesmo dia" (repeatedWeight && (at ["atual","peso"] latestWeight :: Maybe Double)==Just 83 && case at ["historico"] latestWeight :: Maybe [Value] of Just rows -> length rows==3; _ -> False)
 olderWeight <- P.recordWeight database ownAccount (P.WeightInput 79 (addDays (-30) today) "manual")
 stillLatest <- P.athleteData database first studentId
 check "pesagem retroativa nao substitui peso atual" (olderWeight && (at ["atual","peso"] stillLatest :: Maybe Double)==Just 83)
 let ownWeightRequest token = (setPath (postFor token "") "/api/auth/pesagens"){requestHeaders=("Idempotency-Key","test-own-weight-operation-001"):requestHeaders(postFor token "")}
 publicWeight <- runSession (srequest (SRequest (ownWeightRequest studentToken) (encode (object ["peso" .= (71::Double),"data" .= today,"origem" .= ("treino"::T.Text),"aluno_id" .= studentId])))) application
 check "aluno registra peso pela propria sessao" (simpleStatus publicWeight==status200)
 targetUnchanged <- P.athleteData database first studentId
 check "id enviado pelo aluno nao altera outra pessoa" ((at ["atual","peso"] targetUnchanged :: Maybe Double)==Just 83)
 trainerWeight <- runSession (srequest (SRequest (ownWeightRequest firstToken) (encode (object ["peso" .= (50::Double),"data" .= today])))) application
 check "treinador nao registra peso em nome do aluno" (simpleStatus trainerWeight==status403)
 futureWeight <- P.recordWeight database ownAccount (P.WeightInput 85 (addDays 1 today) "manual")
 check "recusa pesagem futura" (not futureWeight)
 onboardingInvite <- newToken
 createDirectInvite database first onboardingInvite
 onboardingTicket <- newToken
 beginStudentSignup database (hashToken onboardingInvite) "google-onboarding-weight" "onboarding-weight@example.invalid" onboardingTicket
 onboardingSession <- newToken
 onboardingAccount <- confirmStudentSignupWithWeight database onboardingTicket "Aluno com pesagem inicial" onboardingSession (Just 76.5)
 onboardingWeight <- P.ownAthleteData database onboardingAccount
 check "pesagem de onboarding usa o mesmo historico" ((at ["atual","peso"] onboardingWeight :: Maybe Double)==Just 76.5 && (at ["atual","origem"] onboardingWeight :: Maybe T.Text)==Just "onboarding")
 let multiRepMax = session today "Maior carga em tres repeticoes" [P.Exercise "Agachamento" "agachamento" [P.TrainingSet 3 225 (Just 3) (Just 225) (Just 9)] Nothing Nothing]
 _ <- sendPost firstToken "/treinos" multiRepMax
 unifiedProfile <- P.studentProfile database first studentId 30 "semana"
 unifiedOverview <- P.studentOverview database first
 let unifiedRows = case fromJSON unifiedOverview of Success rows -> rows; _ -> [] :: [Value]
 check "maximas da tabela e perfil usam a mesma fonte incluindo varias repeticoes" ((at ["kpis","agachamento","valor"] unifiedProfile :: Maybe Double)==Just 225 && case filter (\row -> (at ["id"] row :: Maybe Int64)==Just studentId) unifiedRows of [row] -> (at ["agachamento"] row :: Maybe Double)==Just 225 && (at ["total"] row :: Maybe Double)==at ["kpis","total"] unifiedProfile; _ -> False)
 settingsResponse <- sendPost firstToken "/dados-atleta" (object ["genero" .= ("feminino"::T.Text),"categoriaPesoAlvo" .= (83::Double)])
 check "treinador salva genero e limite de peso" (simpleStatus settingsResponse==status200)
 settingsData <- P.athleteData database first studentId
 check "dados exibem genero meta peso inicial e variacao" ((at ["genero"] settingsData :: Maybe T.Text)==Just "feminino" && (at ["categoriaPesoAlvo"] settingsData :: Maybe Double)==Just 83 && (at ["inicial","peso"] settingsData :: Maybe Double)==Just 79 && (at ["variacaoTotal"] settingsData :: Maybe Double)==Just 4)
 femaleProfile <- P.studentProfile database first studentId 30 "semana"
 check "genero escolhido recalcula DOTS na pagina individual" ((at ["perfil","dots"] femaleProfile :: Maybe Double)==P.dots "feminino" 83 625)
 invalidTarget <- sendPost firstToken "/dados-atleta" (object ["genero" .= ("feminino"::T.Text),"categoriaPesoAlvo" .= (-1::Double)])
 check "limite de peso negativo recusado" (simpleStatus invalidTarget==status400)
 settingsOther <- sendPost secondToken "/dados-atleta" (object ["genero" .= ("masculino"::T.Text)])
 check "outro treinador nao edita genero" (simpleStatus settingsOther==status404)
 let latestId = at ["atual","id"] settingsData :: Maybe Int64
 case latestId of
  Just identifier -> do
   let suffix action = "/pesagens/"<>encodeUtf8 (T.pack (show identifier))<>"/"<>action
   correctionDenied <- sendPost secondToken (suffix "editar") (object ["peso" .= (81::Double),"data" .= today])
   check "correcao exige propriedade do aluno" (simpleStatus correctionDenied==status404)
   corrected <- sendPost firstToken (suffix "editar") (object ["peso" .= (81::Double),"data" .= today])
   check "corrige pesagem incorreta" (simpleStatus corrected==status200)
   afterCorrection <- P.athleteData database first studentId
   correctedProfile <- P.studentProfile database first studentId 30 "semana"
   check "correcao sincroniza peso diario e origem" ((at ["atual","peso"] afterCorrection :: Maybe Double)==Just 81 && (at ["atual","origem"] afterCorrection :: Maybe T.Text)==Just "treinador" && (at ["perfil","peso"] correctedProfile :: Maybe Double)==Just 81)
   removed <- sendPost firstToken (suffix "excluir") (object [])
   check "exclui leitura dos calculos" (simpleStatus removed==status200)
   afterRemoval <- P.athleteData database first studentId
   removalProfile <- P.studentProfile database first studentId 30 "semana"
   check "exclusao recupera leitura anterior do mesmo dia e DOTS" ((at ["atual","peso"] afterRemoval :: Maybe Double)==Just 82 && (at ["perfil","peso"] removalProfile :: Maybe Double)==Just 82 && (at ["perfil","dots"] removalProfile :: Maybe Double)==P.dots "feminino" 82 625)
   replayRemoval <- sendPost firstToken (suffix "excluir") (object [])
   check "exclusao repetida nao altera outra pesagem" (simpleStatus replayRemoval==status400)
  Nothing -> die "Pesagem atual sem identificador"
 noTarget <- sendPost firstToken "/dados-atleta" (object ["genero" .= ("feminino"::T.Text),"categoriaPesoAlvo" .= Null])
 check "permite remover meta opcional" (simpleStatus noTarget==status200)
 let groupedSets = [P.TrainingSet 3 200 Nothing Nothing Nothing,P.TrainingSet 6 75 Nothing Nothing Nothing,P.TrainingSet 6 75 Nothing Nothing Nothing]
     groupedExercise = P.Exercise "Agachamento por linhas" "agachamento" groupedSets (Just [1,2]) Nothing
     groupedSession = (session today "Prescricao 1x3x200 e 2x6x75" [groupedExercise]) {P.concluido=False,P.prescricao=P.Plan "treino" "" (Just 999) Nothing}
 groupedSave <- sendPost firstToken "/treinos" groupedSession
 check "salva quantidade repeticoes e carga diferentes por linha" (simpleStatus groupedSave==status200)
 groupedRows <- withDatabase database $ \connection -> query connection "SELECT exercicios::text FROM treinos_alunos WHERE aluno_id=? AND titulo='Prescricao 1x3x200 e 2x6x75'" (Only studentId) :: IO [Only T.Text]
 check "agrupamentos persistem sem fabricar execucoes" (case groupedRows of
  [Only text] -> case eitherDecodeStrict (encodeUtf8 text) :: Either String [P.Exercise] of
   Right [exercise] -> P.agrupamentos exercise==Just [1,2] && length(P.series exercise)==3 && all (\set -> P.carga set==Nothing && P.repeticoes set==Nothing) (P.series exercise)
   _ -> False
  _ -> False)
 invalidGroup <- sendPost firstToken "/treinos" groupedSession {P.exercicios=[groupedExercise {P.agrupamentos=Just [2,2]}]}
 check "recusa agrupamento que nao corresponde as series" (simpleStatus invalidGroup==status400)
 mixedGroup <- sendPost firstToken "/treinos" groupedSession {P.exercicios=[groupedExercise {P.agrupamentos=Just [3]}]}
 check "cada linha precisa ter repeticoes e carga coerentes" (simpleStatus mixedGroup==status400)
 check "prescricao agrupada nao conta como volume executado" (P.sessionVolume groupedSession==0)
 derivedMaximum <- withDatabase database $ \connection -> query connection "SELECT (prescricao->>'cargaMaximaDia')::double precision FROM treinos_alunos WHERE aluno_id=? AND titulo='Prescricao 1x3x200 e 2x6x75'" (Only studentId) :: IO [Only Double]
 check "carga maxima vem das linhas e ignora campo manual" (derivedMaximum==[Only 200])
 executionIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='Prescricao 1x3x200 e 2x6x75'" (Only studentId) :: IO [Only Int64]
 case executionIds of
  [Only identifier] -> do
   let executed = groupedSession {P.versao=Just 1,P.concluido=True,P.titulo="Tentativa de alterar prescricao",P.exercicios=[groupedExercise {P.series=map (\row -> row {P.cargaPrevista=999,P.carga=Just 70,P.repeticoes=Just 3,P.rpe=Just 8}) (P.series groupedExercise)}]}
   savedExecution <- P.recordExecution database ownAccount identifier executed
   check "aluno registra execucao" savedExecution
   executionRows <- withDatabase database $ \connection -> query connection "SELECT titulo,exercicios::text FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(T.Text,T.Text)]
   check "execucao preserva prescricao e salva carga real" (case executionRows of
    [(title,text)] -> title=="Prescricao 1x3x200 e 2x6x75" && case eitherDecodeStrict (encodeUtf8 text) :: Either String [P.Exercise] of
     Right [item] -> P.cargaPrevista (head (P.series item))==200 && P.carga (head (P.series item))==Just 70
     _ -> False
    _ -> False)
   deniedExecution <- P.recordExecution database (ownAccount {accountId= -1}) identifier executed
   check "aluno nao altera sessao de outra pessoa" (not deniedExecution)
   invalidExecution <- P.recordExecution database ownAccount identifier executed {P.versao=Just 2,P.exercicios=[]}
   check "execucao exige todas as series originais" (not invalidExecution)
  _ -> die "Sessao para execucao ausente"
 advanceIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='Agendado'" (Only studentId) :: IO [Only Int64]
 case advanceIds of
  [Only identifier] -> do
   noExecution <- P.recordExecution database ownAccount identifier future {P.versao=Just 1,P.concluido=True}
   check "nao conclui treino sem execucao" (not noExecution)
   let advance = future {P.versao=Just 1,P.concluido=True,P.dataTreino=addDays 100 today,P.exercicios=[P.Exercise "Alterado" "terra" [P.TrainingSet 99 999 (Just 4) (Just 95) (Just 8)] Nothing Nothing]}
   advanced <- P.recordExecution database ownAccount identifier advance
   check "aluno pode adiantar sessao futura" advanced
   advancedRows <- withDatabase database $ \connection -> query connection "SELECT data,concluido,exercicios::text,observacoes FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(Day,Bool,T.Text,T.Text)]
   check "sessao adiantada usa dia real e preserva prescricao" (case advancedRows of
    [(day,done,text,notes)] -> day==today && done && notes==P.observacoes future && case eitherDecodeStrict (encodeUtf8 text) :: Either String [P.Exercise] of
     Right [item] -> P.nome item=="Supino" && case P.series item of
      [row] -> P.cargaPrevista row==100 && P.repeticoesPrevistas row==5 && P.carga row==Just 95
      _ -> False
     _ -> False
    _ -> False)
   corrected <- P.recordExecution database ownAccount identifier advance {P.versao=Just 2,P.motivoAlteracao=Just "Correcao do registro"}
   check "correcao de execucao nao duplica sessao" corrected
   sameSession <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [Only Int64]
   check "adiantamento atualiza a mesma sessao" (sameSession==[Only 1])
  _ -> die "Sessao futura de teste ausente"
 -- Optimistic concurrency and immutable execution identity.
 let protectedRows = [P.TrainingSet 5 100 Nothing Nothing Nothing,P.TrainingSet 5 100 Nothing Nothing Nothing,P.TrainingSet 3 120 Nothing Nothing Nothing]
     protectedExercise = P.Exercise "Supino" "supino" protectedRows Nothing Nothing
     protectedSession = (session today "Integridade concorrente" [protectedExercise]) {P.concluido=False}
 _ <- sendPost firstToken "/treinos" protectedSession
 protectedIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='Integridade concorrente'" (Only studentId) :: IO [Only Int64]
 case protectedIds of
  [Only identifier] -> do
   let partialRows = [P.TrainingSet 5 100 (Just 4) (Just 95) (Just 8),protectedRows!!1,protectedRows!!2]
       partialExecution = protectedSession {P.versao=Just 1,P.concluido=True,P.exercicios=[protectedExercise {P.series=partialRows}]}
   partialSaved <- P.recordExecution database ownAccount identifier partialExecution
   check "permite concluir parcialmente sem fabricar series" partialSaved
   ownBefore <- P.ownSessions database ownAccount
   let selected = case fromJSON ownBefore :: Result [P.TrainingSession] of Success rows -> filter ((==Just identifier) . P.id) rows; _ -> []
   check "sessao parcial tem estado e contagem explicitos" (case selected of
    [row] -> (at ["estadoExecucao"] (toJSON row) :: Maybe T.Text)==Just "parcial" && (at ["seriesRealizadas"] (toJSON row) :: Maybe Int)==Just 1 && P.versao row==Just 2
    _ -> False)
   staleCoach <- sendPost firstToken "/treinos" protectedSession {P.id=Just identifier,P.versao=Just 1}
   check "prescricao antiga nao sobrescreve execucao recente" (simpleStatus staleCoach==status409)
   missingVersion <- sendPost firstToken "/treinos" protectedSession {P.id=Just identifier}
   check "edicao sem versao nao contorna conflito" (simpleStatus missingVersion==status409)
   let coachEdit = protectedSession {P.id=Just identifier,P.versao=Just 2,P.motivoAlteracao=Just "Ajuste da prescricao",P.titulo="Prescricao revisada",P.exercicios=[protectedExercise {P.series=map (\row -> row {P.carga=Just 999,P.repeticoes=Just 99,P.rpe=Just 10}) protectedRows}]}
   updatedCoach <- sendPost firstToken "/treinos" coachEdit
   check "treinador atualiza apenas prescricao" (simpleStatus updatedCoach==status200)
   protectedAfter <- P.ownSessions database ownAccount
   check "servidor ignora execucao enviada pelo editor do treinador" (case fromJSON protectedAfter :: Result [P.TrainingSession] of
    Success rows -> case filter ((==Just identifier) . P.id) rows of
     [row] -> P.concluido row && P.versao row==Just 3 && case concatMap P.series (P.exercicios row) of
      [firstRow,secondRow,thirdRow] -> P.carga firstRow==Just 95 && P.repeticoes firstRow==Just 4 && P.rpe firstRow==Just 8 && P.carga secondRow==Nothing && P.carga thirdRow==Nothing
      _ -> False
     _ -> False
    _ -> False)
   renameDenied <- sendPost firstToken "/treinos" protectedSession {P.id=Just identifier,P.versao=Just 3,P.exercicios=[protectedExercise {P.nome="Terra",P.movimento="terra"}]}
   check "nao reclassifica levantamento executado" (simpleStatus renameDenied==status409)
   removeSeriesDenied <- sendPost firstToken "/treinos" protectedSession {P.id=Just identifier,P.versao=Just 3,P.exercicios=[protectedExercise {P.series=take 2 protectedRows}]}
   check "nao altera estrutura de exercicio executado" (simpleStatus removeSeriesDenied==status409)
   staleStudent <- try (P.recordExecution database ownAccount identifier partialExecution {P.versao=Just 2}) :: IO (Either AuthFailure Bool)
   check "execucao antiga nao grava sobre prescricao nova" (staleStudent==Left SessionConflict)
   let fullExecution = protectedSession {P.concluido=True,P.versao=Just 3,P.motivoAlteracao=Just "Completar registro",P.exercicios=[protectedExercise {P.series=map (\row -> row {P.carga=Just (P.cargaPrevista row),P.repeticoes=Just (P.repeticoesPrevistas row)}) protectedRows}]}
   _ <- P.recordExecution database ownAccount identifier fullExecution
   fullData <- P.ownSessions database ownAccount
   check "todas as series prescritas geram conclusao integral" (case fromJSON fullData :: Result [P.TrainingSession] of
    Success rows -> case filter ((==Just identifier) . P.id) rows of [row] -> (at ["estadoExecucao"] (toJSON row) :: Maybe T.Text)==Just "concluido"; _ -> False
    _ -> False)
   let alteredExecution = fullExecution {P.versao=Just 4,P.exercicios=[protectedExercise {P.series=map (\row -> row {P.carga=Just 90,P.repeticoes=Just 3}) protectedRows}]}
   _ <- P.recordExecution database ownAccount identifier alteredExecution
   alteredData <- P.ownSessions database ownAccount
   check "todas as series com ajustes geram conclusao alterada" (case fromJSON alteredData :: Result [P.TrainingSession] of
    Success rows -> case filter ((==Just identifier) . P.id) rows of [row] -> (at ["estadoExecucao"] (toJSON row) :: Maybe T.Text)==Just "concluido_alterado"; _ -> False
    _ -> False)
  _ -> die "Sessao protegida ausente"
 -- Sao Paulo remains on the preceding business day after midnight UTC.
 let boundary = UTCTime (fromGregorian 2026 11 22) (secondsToDiffTime (2*3600+59*60))
 check "data de negocio nao avanca antes da meia-noite em Sao Paulo" (appDayAt boundary==fromGregorian 2026 11 21)
 check "data de negocio avanca as 03 UTC" (appDayAt (addUTCTime 60 boundary)==fromGregorian 2026 11 22)
 -- Existing student may receive onboarding after a same-day legacy reading.
 inviteToken <- newToken
 _ <- createStudent database first "Onboarding com historico" "peso.onboarding@example.invalid" inviteToken
 onboardingIds <- withDatabase database $ \connection -> query connection "SELECT id FROM alunos WHERE treinador_id=? AND email='peso.onboarding@example.invalid'" (Only (accountId first)) :: IO [Only Int64]
 case onboardingIds of
  [Only identifier] -> do
   let pendingAccount = ownAccount {accountId=identifier}
   _ <- P.recordWeight database pendingAccount (P.WeightInput 80 today "manual")
   signupTicket <- newToken
   beginStudentSignup database (hashToken inviteToken) "google-peso-onboarding-integridade" "peso.onboarding@example.invalid" signupTicket
   signupSession <- newToken
   enrolled <- confirmStudentSignupWithWeight database signupTicket "Onboarding com historico" signupSession (Just 82)
   onboardingWeight <- P.ownAthleteData database enrolled
   onboardingProfile <- P.ownProfile database enrolled 30 "semana"
   check "onboarding atualiza historico e leitura diaria juntos" ((at ["atual","peso"] onboardingWeight :: Maybe Double)==Just 82 && (at ["perfil","peso"] onboardingProfile :: Maybe Double)==Just 82)
   check "onboarding preserva leitura anterior" (maybe False ((==2) . length) (at ["historico"] onboardingWeight :: Maybe [Value]))
  _ -> die "Aluno onboarding ausente"
 -- Planned dates stay unchanged after early completion and corrections.
 case advanceIds of
  [Only identifier] -> do
   dateRows <- withDatabase database $ \connection -> query connection "SELECT data_prevista,data_realizada,data FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(Day,Maybe Day,Day)]
   check "adiantar preserva planejamento e registra realizacao" (dateRows==[(addDays 1 today,Just today,today)])
   events <- P.sessionHistory database first studentId identifier
   check "conclusao e correcao ficam auditadas" (case fromJSON events :: Result [Value] of Success rows -> length rows==3 && any (\row -> (at ["acao"] row :: Maybe T.Text)==Just "corrigir_execucao") rows; _ -> False)
  _ -> pure ()
 -- Cancellation and annulment have different permissions and effects.
 let recordTitle="PR para anular"
     exceptional = session today recordTitle [exercise "agachamento" 500,exercise "supino" 300,exercise "terra" 600]
 baselineMetrics <- P.studentProfile database first studentId 30 "semana"
 _ <- sendPost firstToken "/treinos" exceptional
 exceptionalIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo=?" (studentId,recordTitle) :: IO [Only Int64]
 case exceptionalIds of
  [Only identifier] -> do
   let actionRoute action = "/treinos/"<>encodeUtf8 (T.pack(show identifier))<>"/"<>action
       actionBody reason = object ["versao" .= (1::Int),"motivo" .= (reason::T.Text)]
   raised <- P.studentProfile database first studentId 30 "semana"
   check "novo PR entra nos indicadores antes da anulacao" ((at ["kpis","total"] raised :: Maybe Double)==Just 1400)
   cannotCancel <- sendPost firstToken (actionRoute "cancelar") (actionBody "Tentativa indevida")
   check "treino executado nao pode ser cancelado como prescricao" (simpleStatus cannotCancel==status400)
   noReason <- sendPost firstToken (actionRoute "anular") (actionBody " ")
   check "anulacao exige motivo" (simpleStatus noReason==status400)
   foreignAction <- sendPost secondToken (actionRoute "anular") (actionBody "Nao sou proprietario")
   check "outro treinador nao anula execucao" (simpleStatus foreignAction==status404)
   studentAction <- sendPost studentToken (actionRoute "anular") (actionBody "Aluno nao pode anular")
   check "aluno nao acessa anulação administrativa" (simpleStatus studentAction==status403)
   annulled <- sendPost firstToken (actionRoute "anular") (actionBody "Registro de carga incorreto")
   check "treinador pode anular execucao incorreta" (simpleStatus annulled==status200)
   recalculated <- P.studentProfile database first studentId 30 "semana"
   check "anulacao recalcula PR total volume e DOTS" ((at ["kpis"] recalculated :: Maybe Value)==(at ["kpis"] baselineMetrics :: Maybe Value) && (at ["perfil","dots"] recalculated :: Maybe Value)==(at ["perfil","dots"] baselineMetrics :: Maybe Value))
   preservedRows <- withDatabase database $ \connection -> query connection "SELECT situacao,concluido,jsonb_array_length(exercicios) FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(T.Text,Bool,Int)]
   check "anulacao preserva registro e series originais" (preservedRows==[("anulada",True,3)])
   history <- P.sessionHistory database ownAccount studentId identifier
   currentAuthor <- findAccount database firstToken
   check "aluno consulta motivo e autor da anulacao" (case fromJSON history :: Result [Value] of
    Success (event:_) -> (at ["acao"] event :: Maybe T.Text)==Just "anular" && (at ["motivo"] event :: Maybe T.Text)==Just "Registro de carga incorreto" && (at ["autor"] event :: Maybe T.Text)==(accountName <$> currentAuthor) && isJust (at ["antes"] event :: Maybe Value)
    _ -> False)
   foreignHistory <- runSession (request (getFor secondToken (actionRoute "historico"))) application
   check "historico respeita propriedade do aluno" (simpleStatus foreignHistory==status404)
   sessionValues <- P.ownSessions database ownAccount
   let annulledRecords = case fromJSON sessionValues :: Result [P.TrainingSession] of Success rows -> filter ((==Just identifier) . P.id) rows; _ -> []
   check "sessao anulada nao pode voltar a contar por edicao do aluno" (case annulledRecords of [row] -> P.sessionVolume row==0; _ -> False)
   case annulledRecords of
    [row] -> do
     cannotRevive <- try (P.recordExecution database ownAccount identifier row {P.motivoAlteracao=Just "Tentativa de reativar"}) :: IO (Either AuthFailure Bool)
     check "gravacao de execucao nao reativa anulacao" (cannotRevive==Left SessionConflict)
    _ -> die "Registro anulado ausente"
  _ -> die "Sessao para anular ausente"
 let cancelledPlan = (session (addDays 10 today) "Prescricao para cancelar" [P.Exercise "Supino" "supino" [P.TrainingSet 5 100 Nothing Nothing Nothing] Nothing Nothing]) {P.concluido=False}
 _ <- sendPost firstToken "/treinos" cancelledPlan
 cancelIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='Prescricao para cancelar'" (Only studentId) :: IO [Only Int64]
 case cancelIds of
  [Only identifier] -> do
   let routeAction action="/treinos/"<>encodeUtf8(T.pack(show identifier))<>"/"<>action
       body=object ["versao" .= (1::Int),"motivo" .= ("Semana de recuperacao"::T.Text)]
   cannotAnnul <- sendPost firstToken (routeAction "anular") body
   check "prescricao sem execucao nao pode ser anulada como resultado" (simpleStatus cannotAnnul==status400)
   cancelled <- sendPost firstToken (routeAction "cancelar") body
   check "cancela prescricao sem excluir registro" (simpleStatus cancelled==status200)
   cancelledRows <- withDatabase database $ \connection -> query connection "SELECT situacao,data_prevista,data_realizada,versao FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(T.Text,Day,Maybe Day,Int64)]
   check "cancelamento preserva data prevista sem inventar realizacao" (cancelledRows==[("cancelada",addDays 10 today,Nothing,2)])
   cannotFinish <- try (P.recordExecution database ownAccount identifier cancelledPlan {P.versao=Just 2,P.concluido=True,P.exercicios=[exercise "supino" 100]}) :: IO (Either AuthFailure Bool)
   check "aluno nao conclui prescricao cancelada" (cannotFinish==Left SessionConflict)
   repeatCancel <- sendPost firstToken (routeAction "cancelar") body
   check "cancelamento repetido nao duplica historico" (simpleStatus repeatCancel==status409)
   history <- P.sessionHistory database first studentId identifier
   check "criar e cancelar ficam registrados atomicamente" (case fromJSON history :: Result [Value] of Success rows -> length rows==2; _ -> False)
  _ -> die "Prescricao para cancelar ausente"
 -- Per-exercise targets survive execution edits; explicit null removes actual RPE.
 let benchRpe=P.Exercise "Supino RPE" "supino" [P.TrainingSet 3 100 (Just 3) (Just 100) (Just 8)] Nothing (Just 8)
     deadRpe=P.Exercise "Terra RPE" "terra" [P.TrainingSet 2 200 (Just 2) (Just 200) (Just 9)] Nothing (Just 9)
     accessoryRpe=P.Exercise "Leg press" "acessorio" [P.TrainingSet 6 300 (Just 6) (Just 300) (Just 7)] Nothing Nothing
     rpeSession=session today "RPE por exercicio" [benchRpe,deadRpe,accessoryRpe]
 _ <- sendPost firstToken "/treinos" rpeSession
 badRpeTarget <- sendPost firstToken "/treinos" rpeSession {P.exercicios=[benchRpe {P.rpePrevistoExercicio=Just 11}]}
 check "meta RPE por exercicio exige 1 a 10" (simpleStatus badRpeTarget==status400)
 rpeIds <- withDatabase database $ \connection -> query connection "SELECT id FROM treinos_alunos WHERE aluno_id=? AND titulo='RPE por exercicio'" (Only studentId) :: IO [Only Int64]
 case rpeIds of
  [Only identifier] -> do
   let cleared=benchRpe {P.rpePrevistoExercicio=Just 10,P.series=map (\row->row {P.rpe=Nothing}) (P.series benchRpe)}
   removedRpe <- P.recordExecution database ownAccount identifier rpeSession {P.versao=Just 1,P.motivoAlteracao=Just "Remover RPE incorreto",P.exercicios=[cleared,deadRpe,accessoryRpe]}
   check "aluno remove RPE explicitamente" removedRpe
   savedRpe <- P.ownSessions database ownAccount
   check "limpar um RPE nao muda outros exercicios nem metas" (case fromJSON savedRpe :: Result [P.TrainingSession] of
    Success rows -> case filter ((==Just identifier) . P.id) rows of
     [row] -> case P.exercicios row of
      [bench,dead,accessory] -> P.rpePrevistoExercicio bench==Just 8 && P.rpePrevistoExercicio dead==Just 9 && map P.rpe (P.series bench)==[Nothing] && map P.rpe (P.series dead)==[Just 9] && map P.rpe (P.series accessory)==[Just 7]
      _ -> False
     _ -> False
    _ -> False)
   -- Deliberately corrupt one JSON document inside this disposable database.
   _ <- withDatabase database $ \connection -> execute connection "UPDATE treinos_alunos SET exercicios='[{\"nome\":\"Supino\"}]'::jsonb,versao=versao+1 WHERE id=?" (Only identifier)
   incomplete <- P.studentProfile database first studentId 30 "semana"
   check "sessao invalida aparece no calendario sem dados inventados" ((at ["dadosIncompletos"] incomplete :: Maybe Bool)==Just True && case at ["calendario"] incomplete :: Maybe [Value] of
    Just entries -> any (\entry -> (at ["sessao","id"] entry :: Maybe Int64)==Just identifier && (at ["sessao","erroDados"] entry :: Maybe Bool)==Just True) entries
    _ -> False)
   incompleteTable <- P.studentOverview database first
   check "tabela avisa que indicadores estao incompletos" (case fromJSON incompleteTable :: Result [Value] of Success entries -> any (\entry -> (at ["id"] entry :: Maybe Int64)==Just studentId && (at ["dadosIncompletos"] entry :: Maybe Bool)==Just True) entries; _ -> False)
   let recoveryRoute="/treinos/"<>encodeUtf8(T.pack(show identifier))<>"/recuperar"
       recovery=object ["versao" .= (3::Int),"motivo" .= ("Recuperar documento invalido"::T.Text)]
   deniedRecovery <- sendPost secondToken recoveryRoute recovery
   check "outro treinador nao recupera dados do aluno" (simpleStatus deniedRecovery==status404)
   restored <- sendPost firstToken recoveryRoute recovery
   check "recupera ultima versao valida com autoria e motivo" (simpleStatus restored==status200)
   completeAgain <- P.studentProfile database first studentId 30 "semana"
   check "recuperacao remove alerta sem excluir sessao" ((at ["dadosIncompletos"] completeAgain :: Maybe Bool)==Just False)
   recoveryHistory <- P.sessionHistory database ownAccount studentId identifier
   check "recuperacao fica registrada na auditoria" (case fromJSON recoveryHistory :: Result [Value] of Success (event:_) -> (at ["acao"] event :: Maybe T.Text)==Just "recuperar"; _ -> False)
  _ -> die "Sessao RPE ausente"
 legacyIds <- withDatabase database $ \connection -> query connection "INSERT INTO treinos_alunos(aluno_id,data,data_prevista,titulo,concluido,exercicios,observacoes,video,prescricao) VALUES (?,?,?,'Legado sem versao valida',FALSE,'[{\"nome\":\"Incompleto\"}]'::jsonb,'','','{}'::jsonb) RETURNING id" (studentId,today,today) :: IO [Only Int64]
 case legacyIds of
  [Only identifier] -> do
   noRecovery <- sendPost firstToken ("/treinos/"<>encodeUtf8(T.pack(show identifier))<>"/recuperar") (object ["versao" .= (1::Int),"motivo" .= ("Tentar recuperar legado"::T.Text)])
   check "sem historico valido nao inventa uma sessao vazia" (simpleStatus noRecovery==status400)
   stillInvalid <- withDatabase database $ \connection -> query connection "SELECT versao,exercicios->0->>'nome' FROM treinos_alunos WHERE id=?" (Only identifier) :: IO [(Int64,T.Text)]
   check "recuperacao impossivel preserva os dados originais" (stillInvalid==[(1,"Incompleto")])
  _ -> die "Registro legado ausente"
 -- A response lost after commit must be replayed, not recreated.
 operationKey <- newToken
 let safeRequest token suffix key=(postFor token suffix){requestHeaders=("Idempotency-Key",encodeUtf8 key):requestHeaders(postFor token suffix)}
     sendSafe token suffix key body=runSession(srequest(SRequest(safeRequest token suffix key)(encode body))) application
     creation=(session today "Criacao protegida contra repeticao" [P.Exercise "Supino" "supino" [P.TrainingSet 5 100 Nothing Nothing Nothing] Nothing Nothing]) {P.concluido=False}
 firstWrite <- sendSafe firstToken "/treinos" operationKey creation
 repeatedWrite <- sendSafe firstToken "/treinos" operationKey creation
 check "mesma tentativa retorna confirmacao sem criar duas sessoes" (simpleStatus firstWrite==status200 && simpleStatus repeatedWrite==status200 && simpleBody firstWrite==simpleBody repeatedWrite)
 countCreated <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM treinos_alunos WHERE aluno_id=? AND titulo=?" (studentId,P.titulo creation) :: IO[Only Int]
 check "criacao repetida tem apenas uma linha" (countCreated==[Only 1])
 mismatched <- sendSafe firstToken "/treinos" operationKey creation {P.titulo="Corpo diferente"}
 check "identificador nao pode ser reutilizado para outros dados" (simpleStatus mismatched==status409)
 foreignReplay <- sendSafe secondToken "/treinos" operationKey creation
 check "confirmacao nao atravessa permissoes entre contas" (simpleStatus foreignReplay==status404)
 missingKey <- runSession(srequest(SRequest(postFor firstToken "/treinos")(encode creation))) application
 check "gravacao exige identificador de tentativa" (simpleStatus missingKey==status400)
 failedKey <- newToken
 failedWrite <- sendSafe firstToken "/treinos" failedKey creation {P.titulo=""}
 receiptsAfterFailure <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM operacoes_gravacao WHERE autor_sub=? AND chave=?" (accountSubject first,failedKey) :: IO[Only Int]
 check "erro de validacao nao cria confirmacao de sucesso" (simpleStatus failedWrite==status400 && receiptsAfterFailure==[Only 0])
 repairedWrite <- sendSafe firstToken "/treinos" failedKey creation {P.titulo="Tentativa corrigida"}
 check "dados rejeitados podem ser corrigidos sem gravacao anterior" (simpleStatus repairedWrite==status200)
 concurrentKey <- newToken
 let concurrentBody=creation {P.titulo="Envio simultaneo protegido"}
 firstResult <- newEmptyMVar
 secondResult <- newEmptyMVar
 _ <- forkIO $ (try(sendSafe firstToken "/treinos" concurrentKey concurrentBody)::IO(Either SomeException SResponse)) >>= putMVar firstResult
 _ <- forkIO $ (try(sendSafe firstToken "/treinos" concurrentKey concurrentBody)::IO(Either SomeException SResponse)) >>= putMVar secondResult
 concurrentA <- takeMVar firstResult
 concurrentB <- takeMVar secondResult
 countConcurrent <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM treinos_alunos WHERE aluno_id=? AND titulo=?" (studentId,P.titulo concurrentBody) :: IO[Only Int]
 check "dois envios simultaneos gravam uma unica sessao" (countConcurrent==[Only 1] && case (concurrentA,concurrentB) of (Right a,Right b)->simpleStatus a==status200&&simpleStatus b==status200;_->False)
 weightActor <- findAccount database studentToken
 case weightActor of
  Just actor -> do
   initialCount <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM historico_pesagens WHERE aluno_id=?" (Only(accountId actor)) :: IO[Only Int]
   weightKey <- newToken
   let requestWeight=(setPath(safeRequest studentToken "" weightKey) "/api/auth/pesagens")
       weightBody=encode(object["peso" .= (72::Double),"data" .= today,"origem" .= ("manual"::T.Text)])
       submitWeight=runSession(srequest(SRequest requestWeight weightBody)) application
   savedWeight <- submitWeight
   repeatedWeightResult <- submitWeight
   finalCount <- withDatabase database $ \connection -> query connection "SELECT count(*) FROM historico_pesagens WHERE aluno_id=?" (Only(accountId actor)) :: IO[Only Int]
   check "pesagem repetida pela mesma tentativa nao duplica historico" (simpleStatus savedWeight==status200&&simpleStatus repeatedWeightResult==status200&&case(initialCount,finalCount)of([Only before],[Only after])->after==before+1;_->False)
  _ -> die "Conta do aluno ausente para teste de repeticao"
 ownDashboard <- P.ownProfile database ownAccount 90 "semana"
 coachDashboard <- P.studentProfile database first studentId 90 "semana"
 check "aluno e treinador usam mesmos indicadores e calendario" (ownDashboard==coachDashboard)
 beforeOwnEdit <- P.ownAthleteData database ownAccount
 savedOwnProfile <- P.saveOwnProfile database ownAccount (P.OwnProfileInput "Aluno atualizado" Nothing (Just "feminino"))
 check "aluno pode editar seu perfil" savedOwnProfile
 afterOwnEdit <- P.ownAthleteData database ownAccount
 check "editar perfil preserva pesagens" ((at ["historico"] beforeOwnEdit :: Maybe [Value])==(at ["historico"] afterOwnEdit :: Maybe [Value]))
 afterOwnDashboard <- P.ownProfile database ownAccount 90 "semana"
 check "perfil atualizado aparece ao treinador" ((at ["aluno","nome"] afterOwnDashboard :: Maybe T.Text)==Just "Aluno atualizado" && (at ["perfil","categoria"] afterOwnDashboard :: Maybe T.Text)==Just "feminino")
 invalidOwnEdit <- P.saveOwnProfile database ownAccount (P.OwnProfileInput " " Nothing Nothing)
 check "perfil rejeita nome vazio" (not invalidOwnEdit)
 let ownProfileRequest token = (setPath defaultRequest "/api/auth/perfil") {requestHeaders=[("Cookie","ps_session="<>encodeUtf8 token)]}
 studentDashboardResponse <- runSession (request (ownProfileRequest studentToken)) application
 check "aluno acessa proprio panorama pela API" (simpleStatus studentDashboardResponse==status200)
 coachOwnResponse <- runSession (request (ownProfileRequest firstToken)) application
 check "rota pessoal exclusiva do aluno" (simpleStatus coachOwnResponse==status403)
 check "segundo treinador preservado" (accountId second /= accountId first)
 putStrLn "OK: perfil, DOTS, PRs, volume, variacao, pesagens, calendario, edicao e isolamento por treinador."
