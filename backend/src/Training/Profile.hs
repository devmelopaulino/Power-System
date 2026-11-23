{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Training.Profile (recoverSession, SessionAction(..), sessionHistory, changeSessionState, OwnProfileInput(..), ownProfile, saveOwnProfile, ownSessions, recordExecution, studentOverview, studentProfile, saveProfile, saveSession, athleteData, ownAthleteData, recordWeight, saveAthleteSettings, correctWeight, AthleteSettings(..), WeightInput(..), Plan(..), defaultPlan, TrainingSession(..), Exercise(..), TrainingSet(..), ProfileInput(..), dots, sessionVolume) where

import App.Time (appToday)
import Training.WeightStore (writeWeight, rebuildDay)
import Auth.Store (Account(..), AuthFailure(..))
import Control.Exception (throwIO)
import Control.Monad (unless, void)
import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.Aeson.KeyMap as KM
import Data.Int (Int64)
import Data.List (maximumBy, sortOn, nub, groupBy)
import Data.Maybe (mapMaybe, listToMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import qualified Data.ByteString.Lazy as LBS
import Data.Time
import Data.Time.Calendar.WeekDate (toWeekDate)
import Database.Connection (Database, withDatabase, withDatabaseTransaction)
import Database.PostgreSQL.Simple
import GHC.Generics (Generic)

data TrainingSet = TrainingSet
 { repeticoesPrevistas :: Int, cargaPrevista :: Double, repeticoes :: Maybe Int, carga :: Maybe Double, rpe :: Maybe Double }
 deriving (Show, Generic)
instance FromJSON TrainingSet
instance ToJSON TrainingSet
data Exercise = Exercise { nome :: Text, movimento :: Text, series :: [TrainingSet], agrupamentos :: Maybe [Int], rpePrevistoExercicio :: Maybe Double } deriving (Show, Generic)
instance FromJSON Exercise where
 parseJSON = withObject "Exercicio" $ \o -> Exercise <$> o .: "nome" <*> o .: "movimento" <*> o .: "series" <*> o .:? "agrupamentos" <*> o .:? "rpePrevisto"
instance ToJSON Exercise where
 toJSON e = object ["nome" .= nome e,"movimento" .= movimento e,"series" .= series e,"agrupamentos" .= agrupamentos e,"rpePrevisto" .= rpePrevistoExercicio e]
data Plan = Plan { tipoDia :: Text, aquecimento :: Text, cargaMaximaDia :: Maybe Double, rpePrevisto :: Maybe Double } deriving (Show,Generic)
defaultPlan :: Plan
defaultPlan = Plan "treino" "" Nothing Nothing
planFromExercises :: [Exercise] -> Plan -> Plan
planFromExercises exercises plan = plan { cargaMaximaDia = case [cargaPrevista set | exercise <- exercises,set <- series exercise] of
 [] -> Nothing
 loads -> Just (maximum loads) }
instance FromJSON Plan where
 parseJSON = withObject "Prescricao" $ \o -> Plan <$> o .:? "tipoDia" .!= "treino" <*> o .:? "aquecimento" .!= "" <*> o .:? "cargaMaximaDia" <*> o .:? "rpePrevisto"
instance ToJSON Plan
data TrainingSession = TrainingSession
 { id :: Maybe Int64, dataTreino :: Day, titulo :: Text, concluido :: Bool, exercicios :: [Exercise], observacoes :: Text, video :: Text, prescricao :: Plan, versao :: Maybe Int64, dataPrevista :: Maybe Day, dataRealizada :: Maybe Day, situacao :: Text, motivoAlteracao :: Maybe Text }
 deriving (Show, Generic)
instance FromJSON TrainingSession where
 parseJSON = withObject "Sessao" $ \o -> TrainingSession <$> o .:? "id" <*> o .: "dataTreino" <*> o .: "titulo" <*> o .: "concluido" <*> o .: "exercicios" <*> o .: "observacoes" <*> o .: "video" <*> o .:? "prescricao" .!= defaultPlan <*> o .:? "versao" <*> o .:? "dataPrevista" <*> o .:? "dataRealizada" <*> o .:? "situacao" .!= "ativa" <*> o .:? "motivoAlteracao"
instance ToJSON TrainingSession where
 toJSON session = case genericToJSON defaultOptions session of
  Object fields -> Object (KM.insert "estadoExecucao" (toJSON (executionStatus session)) (KM.insert "seriesRealizadas" (toJSON (length [() | e <- exercicios session,s <- series e,carga s/=Nothing])) (KM.insert "seriesPrescritas" (toJSON (sum (map (length . series) (exercicios session)))) fields)))
  value -> value

executionStatus :: TrainingSession -> Text
executionStatus session
 | situacao session/="ativa" = situacao session
 | not (concluido session) = "pendente"
 | any (any (\row -> carga row==Nothing) . series) (exercicios session) = "parcial"
 | any (any (\row -> carga row/=Just (cargaPrevista row) || repeticoes row/=Just (repeticoesPrevistas row)) . series) (exercicios session) = "concluido_alterado"
 | otherwise = "concluido"
data ProfileInput = ProfileInput
 { foto :: Maybe Text, categoria :: Maybe Text, bloco :: Text, inicioBloco :: Maybe Day, semanas :: Int, peso :: Maybe Double, dataPeso :: Day }
 deriving (Show, Generic)
instance FromJSON ProfileInput
instance ToJSON ProfileInput

data WeightInput = WeightInput Double Day Text deriving (Show)
instance FromJSON WeightInput where
 parseJSON = withObject "Pesagem" $ \o -> WeightInput <$> o .: "peso" <*> o .: "data" <*> o .:? "origem" .!= "manual"

recordWeight :: Database -> Account -> WeightInput -> IO Bool
recordWeight database account (WeightInput weight day source) = do
 unless (accountRole account == "aluno") (throwIO PermissionDenied)
 today <- appToday
 if not (finiteRange 1 500 weight) || day>today || source `notElem` ["onboarding","treino","descanso","manual"] then pure False else
  withDatabaseTransaction database $ \connection -> do
   writeWeight connection (accountId account) day weight source
   pure True

weightData :: Connection -> Int64 -> IO Value
weightData connection studentId = do
 today <- appToday
 events <- query connection "SELECT id,data,peso,origem,registrado_em,COALESCE(origem_original,origem) FROM historico_pesagens WHERE aluno_id=? AND excluido_em IS NULL AND data<=? ORDER BY data,registrado_em,id" (studentId,today) :: IO [(Int64,Day,Double,Text,UTCTime,Text)]
 settings <- query connection "SELECT categoria,categoria_peso_alvo FROM perfis_alunos WHERE aluno_id=?" (Only studentId) :: IO [(Maybe Text,Maybe Double)]
 let (gender,target) = case settings of [row] -> row; _ -> (Nothing,Nothing)
     item (identifier,day,weight,source,updated,_) = object ["id" .= identifier,"data" .= day,"peso" .= weight,"valor" .= weight,"origem" .= source,"atualizadoEm" .= updated]
     weigh (_,_,weight,_,_,_) = weight
     initial = case filter (\(_,_,_,_,_,originalSource) -> originalSource=="onboarding") events of row:_ -> Just row; _ -> listToMaybe events
     latest = listToMaybe (reverse events)
     delta = (-) <$> fmap weigh latest <*> fmap weigh initial
     points = zipWith (\row previous -> object ["registro" .= item row,"variacaoAnterior" .= fmap (\before -> weigh row-weigh before) previous]) events (Nothing:map Just events)
 pure $ object ["atual" .= fmap item latest,"inicial" .= fmap item initial,"variacaoTotal" .= delta,"genero" .= gender,"categoriaPesoAlvo" .= target,"historico" .= map item (reverse events),"pontos" .= points]

data AthleteSettings = AthleteSettings (Maybe Text) (Maybe Double)
instance FromJSON AthleteSettings where
 parseJSON = withObject "Dados do atleta" $ \o -> AthleteSettings <$> o .:? "genero" <*> o .:? "categoriaPesoAlvo"

saveAthleteSettings :: Database -> Account -> Int64 -> AthleteSettings -> IO Bool
saveAthleteSettings database account studentId (AthleteSettings gender target) = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 if gender `notElem` [Nothing,Just "masculino",Just "feminino"] || not (maybe True (finiteRange 1 500) target) then pure False else do
  void $ execute connection "INSERT INTO perfis_alunos(aluno_id,categoria,categoria_peso_alvo) VALUES (?,?,?) ON CONFLICT(aluno_id) DO UPDATE SET categoria=EXCLUDED.categoria,categoria_peso_alvo=EXCLUDED.categoria_peso_alvo" (studentId,gender,target)
  pure True

-- Corrections are audited; deleted readings remain recoverable in storage.
correctWeight :: Database -> Account -> Int64 -> Int64 -> Maybe WeightInput -> IO Bool
correctWeight database account studentId eventId replacement = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 void (query connection "SELECT id FROM alunos WHERE id=? FOR UPDATE" (Only studentId) :: IO [Only Int64])
 today <- appToday
 let valid = case replacement of Nothing -> True; Just (WeightInput weight day _) -> finiteRange 1 500 weight && day<=today
 rows <- query connection "SELECT data,row_to_json(h)::text FROM historico_pesagens h WHERE id=? AND aluno_id=? AND excluido_em IS NULL FOR UPDATE" (eventId,studentId) :: IO [(Day,Text)]
 case (valid,rows) of
  (True,[(oldDay,before)]) -> do
   newDay <- case replacement of
    Nothing -> do
     void $ execute connection "UPDATE historico_pesagens SET excluido_em=CURRENT_TIMESTAMP WHERE id=?" (Only eventId)
     pure oldDay
    Just (WeightInput weight day _) -> do
     void $ execute connection "UPDATE historico_pesagens SET data=?,peso=?,origem_original=COALESCE(origem_original,origem),origem='treinador',registrado_em=CURRENT_TIMESTAMP WHERE id=?" (day,weight,eventId)
     pure day
   void $ execute connection "INSERT INTO correcoes_pesagens(pesagem_id,treinador_id,antes,depois) SELECT id,?,?::jsonb,row_to_json(h)::jsonb FROM historico_pesagens h WHERE id=?" (accountId account,before,eventId)
   mapM_ (rebuildDay connection studentId) (nub [oldDay,newDay])
   pure True
  _ -> pure False

athleteData :: Database -> Account -> Int64 -> IO Value
athleteData database account studentId = withDatabase database $ \connection -> do
 _ <- ensureOwner connection account studentId
 weightData connection studentId
ownAthleteData :: Database -> Account -> IO Value
ownAthleteData database account = do
 unless (accountRole account == "aluno") (throwIO PermissionDenied)
 withDatabase database $ \connection -> weightData connection (accountId account)

ensureOwner :: Connection -> Account -> Int64 -> IO (Text, Maybe Text)
ensureOwner connection account studentId = do
 unless (accountRole account == "treinador") (throwIO PermissionDenied)
 rows <- query connection "SELECT nome,email FROM alunos WHERE id=? AND treinador_id=?" (studentId,accountId account)
 case rows of [row] -> pure row; _ -> throwIO StudentNotFound

-- Both the table and individual page use the same decoded sessions and maxima.
type StoredSessionRow = (Int64,Day,Text,Bool,Text,Text,Text,Text,Int64,Text)
loadSessions :: Connection -> Int64 -> IO [TrainingSession]
loadSessions connection studentId = fst <$> loadSessionData connection studentId

loadSessionData :: Connection -> Int64 -> IO ([TrainingSession],[Value])
loadSessionData connection studentId = do
 rows <- query connection "SELECT id,data,titulo,concluido,exercicios::text,observacoes,video,prescricao::text,versao,jsonb_build_object('dataPrevista',data_prevista,'dataRealizada',data_realizada,'situacao',situacao)::text FROM treinos_alunos WHERE aluno_id=? ORDER BY data,id" (Only studentId) :: IO [StoredSessionRow]
 let decoded = map (\row -> (row,decodeSessionRow row)) rows
     issues = [object ["id" .= identifier,"dataTreino" .= day,"dataPrevista" .= day,"titulo" .= title,"versao" .= version,"erroDados" .= True,"situacao" .= ("indisponivel"::Text),"mensagem" .= ("Exercicios ou prescricao indisponiveis. Consulte o historico para recuperar uma versao valida."::Text)] | ((identifier,day,title,_,_,_,_,_,version,_),Nothing) <- decoded]
 mapM_ (\(row,result) -> case result of Nothing -> let (identifier,_,_,_,_,_,_,_,_,_)=row in putStrLn ("Sessao "++show identifier++": dados de treino invalidos; indicadores incompletos."); _ -> pure ()) decoded
 pure ([session | (_,Just session) <- decoded],issues)

decodeSessionRow :: StoredSessionRow -> Maybe TrainingSession
decodeSessionRow (identifier,day,title,done,payload,notes,url,plan,version,metadata) = do
 exercises <- either (const Nothing) Just (eitherDecodeStrict (encodeUtf8 payload))
 prescription <- either (const Nothing) Just (eitherDecodeStrict (encodeUtf8 plan))
 details <- either (const Nothing) Just (eitherDecodeStrict (encodeUtf8 metadata))
 (planned,actual,state) <- parseMaybe (withObject "Datas" (\o -> (,,) <$> o .:? "dataPrevista" <*> o .:? "dataRealizada" <*> o .: "situacao")) details
 if validStored exercises prescription then Just (TrainingSession (Just identifier) day title done exercises notes url (planFromExercises exercises prescription) (Just version) planned actual state Nothing) else Nothing

validStored :: [Exercise] -> Plan -> Bool
validStored exercises plan = tipoDia plan `elem` ["treino","descanso"] && maybe True (finiteRange 1 10) (rpePrevisto plan)
 && (if tipoDia plan=="descanso" then null exercises else not (null exercises)) && all validExercise exercises
 where
  validExercise e = not(T.null(T.strip(nome e))) && movimento e `elem` ["agachamento","supino","terra","acessorio"] && not(null(series e)) && all validSet(series e)
   && maybe True (finiteRange 1 10) (rpePrevistoExercicio e)
   && maybe True (\groups -> all (>0) groups && sum groups==length(series e) && consistentGroups groups(series e)) (agrupamentos e)
  validSet row = repeticoesPrevistas row>=1 && repeticoesPrevistas row<=100 && finiteRange 0 1500 (cargaPrevista row)
   && maybe True (\reps -> reps>=1 && reps<=100) (repeticoes row) && maybe True (finiteRange 0 1500) (carga row)
   && (carga row==Nothing)==(repeticoes row==Nothing) && maybe True (finiteRange 1 10) (rpe row) && (rpe row==Nothing || carga row/=Nothing)

snapshot :: Connection -> Int64 -> IO (Maybe Text)
snapshot connection identifier = do
 rows <- query connection "SELECT row_to_json(t)::text FROM treinos_alunos t WHERE id=?" (Only identifier) :: IO [Only Text]
 pure $ case rows of [Only value] -> Just value; _ -> Nothing

writeAudit :: Connection -> Account -> Int64 -> Text -> Text -> Maybe Text -> IO ()
writeAudit connection account identifier action reason before = void $ execute connection
 "INSERT INTO auditoria_treinos(treino_id,aluno_id,autor_sub,autor_nome,autor_perfil,acao,motivo,antes,depois) SELECT id,aluno_id,?,?,?,?,?,?::jsonb,row_to_json(t)::jsonb FROM treinos_alunos t WHERE id=?"
 (accountSubject account,accountName account,accountRole account,action,reason,before,identifier)

validReason :: Maybe Text -> Bool
validReason = maybe False (\reason -> T.length (T.strip reason)>=3 && T.length reason<=1000)

sessionHistory :: Database -> Account -> Int64 -> Int64 -> IO Value
sessionHistory database account studentId identifier = withDatabase database $ \connection -> do
 if accountRole account=="aluno" then unless (studentId==accountId account) (throwIO PermissionDenied) else void (ensureOwner connection account studentId)
 found <- query connection "SELECT id FROM treinos_alunos WHERE id=? AND aluno_id=?" (identifier,studentId) :: IO [Only Int64]
 unless (not (null found)) (throwIO StudentNotFound)
 rows <- query connection "SELECT id,autor_nome,autor_perfil,acao,motivo,antes::text,depois::text,criado_em FROM auditoria_treinos WHERE treino_id=? AND aluno_id=? ORDER BY id DESC" (identifier,studentId) :: IO [(Int64,Text,Text,Text,Text,Maybe Text,Text,UTCTime)]
 let json text = either (const Null) Prelude.id (eitherDecodeStrict (encodeUtf8 text))
 pure $ toJSON [object ["id" .= eventId,"autor" .= author,"perfil" .= role,"acao" .= action,"motivo" .= reason,"antes" .= fmap json before,"depois" .= json after,"data" .= time] | (eventId,author,role,action,reason,before,after,time) <- rows]

data SessionAction = SessionAction Int64 Text deriving Show
instance FromJSON SessionAction where
 parseJSON = withObject "Acao da sessao" $ \o -> SessionAction <$> o .: "versao" <*> o .: "motivo"

changeSessionState :: Database -> Account -> Int64 -> Int64 -> Text -> SessionAction -> IO Bool
changeSessionState database account studentId identifier action (SessionAction version reason) = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 locked <- query connection "SELECT id FROM treinos_alunos WHERE id=? AND aluno_id=? FOR UPDATE" (identifier,studentId) :: IO [Only Int64]
 sessions <- loadSessions connection studentId
 case filter ((==Just identifier) . Training.Profile.id) sessions of
  [original] | not (null locked) -> do
   unless (versao original==Just version && situacao original=="ativa") (throwIO SessionConflict)
   let executed = any (any (\row -> carga row/=Nothing) . series) (exercicios original)
       allowed = action=="cancelar" && not executed && not (concluido original) || action=="anular" && executed
   if not allowed || not (validReason (Just reason)) then pure False else do
    before <- snapshot connection identifier
    void $ execute connection "UPDATE treinos_alunos SET situacao=?,versao=versao+1,atualizado_em=CURRENT_TIMESTAMP WHERE id=? AND aluno_id=?"
     ((if action=="cancelar" then "cancelada" else "anulada" :: Text),identifier,studentId)
    writeAudit connection account identifier action (T.strip reason) before
    pure True
  _ -> throwIO StudentNotFound

recoverSession :: Database -> Account -> Int64 -> Int64 -> SessionAction -> IO Bool
recoverSession database account studentId identifier (SessionAction version reason) = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 locked <- query connection "SELECT versao FROM treinos_alunos WHERE id=? AND aluno_id=? FOR UPDATE" (identifier,studentId) :: IO [Only Int64]
 case locked of
  [Only current] -> do
   unless (version==current) (throwIO SessionConflict)
   (valid,_) <- loadSessionData connection studentId
   if any ((==Just identifier) . Training.Profile.id) valid || not(validReason(Just reason)) then pure False else do
    rows <- query connection "SELECT depois::text FROM auditoria_treinos WHERE treino_id=? AND aluno_id=? ORDER BY id DESC" (identifier,studentId) :: IO [Only Text]
    let candidate (Only text) = do
         value <- either (const Nothing) Just (eitherDecodeStrict(encodeUtf8 text))
         (exercises,plan,done) <- parseMaybe (withObject "Snapshot" (\o -> (,,) <$> o .: "exercicios" <*> o .: "prescricao" <*> o .: "concluido")) value
         if validStored exercises plan then Just(exercises,plan,done) else Nothing
    case mapMaybe candidate rows of
     (exercises,plan,done):_ -> do
      before <- snapshot connection identifier
      void $ execute connection "UPDATE treinos_alunos SET exercicios=?::jsonb,prescricao=?::jsonb,concluido=?,versao=versao+1,atualizado_em=CURRENT_TIMESTAMP WHERE id=? AND aluno_id=?"
       (decodeUtf8(LBS.toStrict(encode exercises)),decodeUtf8(LBS.toStrict(encode plan)),(done :: Bool),identifier,studentId)
      writeAudit connection account identifier "recuperar" (T.strip reason) before
      pure True
     _ -> pure False
  _ -> throwIO StudentNotFound

data OwnProfileInput = OwnProfileInput Text (Maybe Text) (Maybe Text) deriving Show
instance FromJSON OwnProfileInput where
 parseJSON = withObject "Meu perfil" $ \o -> OwnProfileInput <$> o .: "nome" <*> o .:? "foto" <*> o .:? "genero"

saveOwnProfile :: Database -> Account -> OwnProfileInput -> IO Bool
saveOwnProfile database account (OwnProfileInput name photo gender) = do
 unless (accountRole account=="aluno") (throwIO PermissionDenied)
 let trimmed = T.strip name
 if T.null trimmed || T.length trimmed>120 || not (maybe True validUrl photo) || gender `notElem` [Nothing,Just "masculino",Just "feminino"] then pure False
 else withDatabaseTransaction database $ \connection -> do
  changed <- execute connection "UPDATE alunos SET nome=? WHERE id=?" (trimmed,accountId account)
  if changed/=1 then pure False else do
   void $ execute connection "INSERT INTO perfis_alunos(aluno_id,foto,categoria) VALUES (?,?,?) ON CONFLICT(aluno_id) DO UPDATE SET foto=EXCLUDED.foto,categoria=EXCLUDED.categoria"
    (accountId account,photo,gender)
   pure True

-- Student execution only: prescription and ownership always come from the database.
ownSessions :: Database -> Account -> IO Value
ownSessions database account = do
 unless (accountRole account == "aluno") (throwIO PermissionDenied)
 withDatabase database $ \connection -> do
  (sessions,issues) <- loadSessionData connection (accountId account)
  pure $ toJSON (map toJSON sessions++issues)

recordExecution :: Database -> Account -> Int64 -> TrainingSession -> IO Bool
recordExecution database account identifier input = do
 unless (accountRole account == "aluno") (throwIO PermissionDenied)
 withDatabaseTransaction database $ \connection -> do
  locked <- query connection "SELECT id FROM treinos_alunos WHERE id=? AND aluno_id=? FOR UPDATE" (identifier,accountId account) :: IO [Only Int64]
  sessions <- loadSessions connection (accountId account)
  today <- appToday
  case filter ((==Just identifier) . Training.Profile.id) sessions of
   [original] | not (null locked) && situacao original/="ativa" -> throwIO SessionConflict
   [original] | not (null locked) && situacao original=="ativa" && tipoDia (prescricao original)/="descanso" -> do
    unless (versao input==versao original) (throwIO SessionConflict)
    before <- snapshot connection identifier
    let correcting = any (any (\row -> carga row/=Nothing) . series) (exercicios original)
        originals = exercicios original
        updates = exercicios input
        validSet row = case (repeticoes row,carga row) of
         (Nothing,Nothing) -> rpe row==Nothing
         (Just reps,Just load) -> reps>=1 && reps<=100 && finiteRange 0 1500 load && maybe True (finiteRange 1 10) (rpe row)
         _ -> False
        valid = length originals==length updates && and (zipWith (\a b -> length (series a)==length (series b) && all validSet (series b)) originals updates)
        mergeSet a b = a {repeticoes=repeticoes b,carga=carga b,rpe=rpe b}
        merged = zipWith (\a b -> a {series=zipWith mergeSet (series a) (series b)}) originals updates
        done = concluido input && any (any (\row -> carga row/=Nothing) . series) merged
        completionDay = maybe today Prelude.id (dataRealizada original)
    if not valid || not done || not (maybe True (\reason -> validReason (Just reason)) (motivoAlteracao input)) || (correcting && not (validReason (motivoAlteracao input))) then pure False else do
     void $ execute connection "UPDATE treinos_alunos SET exercicios=?::jsonb,concluido=?,data=?,data_realizada=?,versao=versao+1,atualizado_em=CURRENT_TIMESTAMP WHERE id=? AND aluno_id=?"
      (decodeUtf8 (LBS.toStrict (encode merged)),done,completionDay,completionDay,identifier,accountId account)
     writeAudit connection account identifier (if correcting then "corrigir_execucao" else "concluir") (maybe "Conclusao informada pelo aluno." T.strip (motivoAlteracao input)) before
     pure True
   _ -> pure False

studentOverview :: Database -> Account -> IO Value
studentOverview database account = do
 unless (accountRole account == "treinador") (throwIO PermissionDenied)
 today <- appToday
 withDatabase database $ \connection -> do
  rows <- query connection "SELECT a.id,a.nome,EXISTS(SELECT 1 FROM contas c WHERE c.aluno_id=a.id AND c.perfil='aluno') FROM alunos a WHERE a.treinador_id=? ORDER BY lower(a.nome),a.id" (Only (accountId account)) :: IO [(Int64,Text,Bool)]
  values <- mapM (\(identifier,name,active) -> do
   (allSessions,issues) <- loadSessionData connection identifier
   let sessions=filter (\session -> situacao session=="ativa" && dataTreino session<=today) allSessions
   let maximumFor movement = (\(_,load,_,_) -> load) <$> bestLift movement sessions
   pure $ object ["id" .= identifier,"nome" .= name,"acessoAtivo" .= active,"agachamento" .= maximumFor "agachamento","supino" .= maximumFor "supino","terra" .= maximumFor "terra","total" .= totalFor sessions,"dadosIncompletos" .= not(null issues),"sessoesInvalidas" .= length issues]) rows
  pure (toJSON values)
validUrl :: Text -> Bool
validUrl url = T.null url || ("https://" `T.isPrefixOf` url && T.length url <= 2000 && not (T.any (`elem` ['\r','\n',' ']) url))
finiteRange :: Double -> Double -> Double -> Bool
finiteRange low high n = not (isNaN n || isInfinite n) && n >= low && n <= high

saveProfile :: Database -> Account -> Int64 -> ProfileInput -> IO Bool
saveProfile database account studentId input = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 today <- appToday
 let valid = maybe True validUrl (foto input) && categoria input `elem` [Nothing,Just "masculino",Just "feminino"]
       && T.length (bloco input) <= 120 && semanas input >= 1 && semanas input <= 52
       && maybe True (finiteRange 1 500) (peso input) && dataPeso input <= today
 if not valid then pure False else do
  void $ execute connection "INSERT INTO perfis_alunos (aluno_id,foto,categoria,bloco,inicio_bloco,semanas) VALUES (?,?,?,?,?,?) ON CONFLICT(aluno_id) DO UPDATE SET foto=EXCLUDED.foto,categoria=EXCLUDED.categoria,bloco=EXCLUDED.bloco,inicio_bloco=EXCLUDED.inicio_bloco,semanas=EXCLUDED.semanas"
    (studentId,foto input,categoria input,T.strip (bloco input),inicioBloco input,semanas input)
  -- Metadata changes never mutate the student's measurements, including legacy clients.
  pure True

saveSession :: Database -> Account -> Int64 -> TrainingSession -> IO Bool
saveSession database account studentId input = withDatabaseTransaction database $ \connection -> do
 _ <- ensureOwner connection account studentId
 today <- appToday
 let validSet s = repeticoesPrevistas s >= 1 && repeticoesPrevistas s <= 100 && finiteRange 0 1500 (cargaPrevista s)
       && maybe True (\n -> n >= 1 && n <= 100) (repeticoes s) && maybe True (finiteRange 0 1500) (carga s)
       && ((carga s == Nothing) == (repeticoes s == Nothing)) && maybe True (finiteRange 1 10) (rpe s)
       && (rpe s == Nothing || carga s /= Nothing)
     validExercise e = not (T.null (T.strip (nome e))) && T.length (nome e) <= 120
       && movimento e `elem` ["agachamento","supino","terra","acessorio"] && not (null (series e)) && length (series e) <= 30 && all validSet (series e)
       && maybe True (finiteRange 1 10) (rpePrevistoExercicio e)
       && maybe True (\groups -> not (null groups) && all (\n -> n>=1 && n<=30) groups && sum groups==length (series e) && consistentGroups groups (series e)) (agrupamentos e)
     plan = planFromExercises (exercicios input) (prescricao input)
     rest = tipoDia plan == "descanso"
     valid = tipoDia plan `elem` ["treino","descanso"] && T.length (aquecimento plan)<=4000
       && maybe True (finiteRange 0 1500) (cargaMaximaDia plan) && maybe True (finiteRange 1 10) (rpePrevisto plan)
       && (not rest || (null (exercicios input) && cargaMaximaDia plan==Nothing && rpePrevisto plan==Nothing))
       && not (T.null (T.strip (titulo input))) && T.length (titulo input) <= 120 && T.length (observacoes input) <= 4000
       && maybe True (\reason -> validReason (Just reason)) (motivoAlteracao input)
       && validUrl (video input) && (rest || not (null (exercicios input))) && length (exercicios input) <= 30 && all validExercise (exercicios input)
       && (not (concluido input) || dataTreino input <= today)
       && (dataTreino input <= today || all (all (\s -> carga s == Nothing) . series) (exercicios input))
     payload = decodeUtf8 (LBS.toStrict (encode (exercicios input)))
 if not valid then pure False else case Training.Profile.id input of
  Nothing -> do
   identifiers <- query connection "INSERT INTO treinos_alunos (aluno_id,data,data_prevista,data_realizada,titulo,concluido,exercicios,observacoes,video,prescricao) VALUES (?,?,?,?,?,?,?::jsonb,?,?,?::jsonb) RETURNING id"
    (studentId,dataTreino input,dataTreino input,if any (any (\row -> carga row/=Nothing) . series) (exercicios input) then Just (dataTreino input) else Nothing,T.strip (titulo input),concluido input,payload,observacoes input,video input,decodeUtf8 (LBS.toStrict (encode plan))) :: IO [Only Int64]
   case identifiers of
    [Only identifier] -> writeAudit connection account identifier "criar" "Prescricao criada pelo treinador." Nothing >> pure True
    _ -> pure False
  Just identifier -> do
   locked <- query connection "SELECT id FROM treinos_alunos WHERE id=? AND aluno_id=? FOR UPDATE" (identifier,studentId) :: IO [Only Int64]
   originals <- loadSessions connection studentId
   case filter ((==Just identifier) . Training.Profile.id) originals of
    [original] | not (null locked) && situacao original/="ativa" -> throwIO SessionConflict
    [original] | not (null locked) && situacao original=="ativa" -> do
     unless (versao input==versao original) (throwIO SessionConflict)
     before <- snapshot connection identifier
     let executed = any (any (\row -> carga row/=Nothing) . series) (exercicios original)
         compatible a b = nome a==nome b && movimento a==movimento b && length (series a)==length (series b)
         identitySafe = dataTreino input==dataTreino original && tipoDia plan==tipoDia (prescricao original)
           && length (exercicios input)==length (exercicios original) && and (zipWith compatible (exercicios original) (exercicios input))
         preserveSet old new = new {carga=carga old,repeticoes=repeticoes old,rpe=rpe old}
         clean e = e {series=map (\row -> row {carga=Nothing,repeticoes=Nothing,rpe=Nothing}) (series e)}
         merged = if executed then zipWith (\old new -> new {series=zipWith preserveSet (series old) (series new)}) (exercicios original) (exercicios input) else map clean (exercicios input)
     unless (not executed || identitySafe) (throwIO ExecutedIdentityLocked)
     if executed && not (validReason (motivoAlteracao input)) then pure False else do
      void $ execute connection "UPDATE treinos_alunos SET data=?,data_prevista=?,titulo=?,exercicios=?::jsonb,observacoes=?,video=?,prescricao=?::jsonb,versao=versao+1,atualizado_em=CURRENT_TIMESTAMP WHERE id=? AND aluno_id=?"
       (dataTreino input,maybe (dataTreino input) Prelude.id (if executed then dataPrevista original else Just (dataTreino input)),T.strip (titulo input),decodeUtf8 (LBS.toStrict (encode merged)),observacoes input,video input,decodeUtf8 (LBS.toStrict (encode plan)),identifier,studentId)
      writeAudit connection account identifier "editar_prescricao" (maybe "Atualizacao da prescricao." T.strip (motivoAlteracao input)) before
      pure True
    _ -> throwIO StudentNotFound

consistentGroups :: [Int] -> [TrainingSet] -> Bool
consistentGroups [] rows = null rows
consistentGroups (count:groups) rows = case splitAt count rows of
 (first:rest,remaining) -> all (\s -> repeticoesPrevistas s==repeticoesPrevistas first && cargaPrevista s==cargaPrevista first) rest && consistentGroups groups remaining
 _ -> False

-- Coefficients: IPF Models Evaluation (2020), section 3; same clamps as OpenPowerlifting.
dots :: Text -> Double -> Double -> Maybe Double
dots sex weight total
 | weight <= 0 || total <= 0 || sex `notElem` ["masculino","feminino"] = Nothing
 | otherwise = Just (total * 500 / polynomial)
 where
  x = max 40 (min (if sex == "masculino" then 210 else 150) weight)
  (a,b,c,d,e) = if sex == "masculino" then (-0.000001093,0.0007391293,-0.1918759221,24.0900756,-307.75076)
    else (-0.0000010706,0.0005158568,-0.1126655495,13.6175032,-57.96288)
  polynomial = ((((a*x)+b)*x+c)*x+d)*x+e

sessionVolume :: TrainingSession -> Double
sessionVolume session | situacao session/="ativa" = 0
                     | otherwise = sum [fromIntegral reps * load | exercise <- exercicios session, s <- series exercise, Just reps <- [repeticoes s], Just load <- [carga s]]

type Lift = (Day, Double, Int, Maybe Double)
liftRows :: Text -> [TrainingSession] -> [Lift]
liftRows movement sessions = [(dataTreino session,load,reps,rpe s) | session <- sessions, situacao session=="ativa", exercise <- exercicios session, movimento exercise == movement, s <- series exercise, Just load <- [carga s], Just reps <- [repeticoes s]]
-- One point per day, retaining repetitions and RPE from the heaviest set.
-- Equal loads keep the first recorded set in session/series order.
heaviestDaily :: Text -> [TrainingSession] -> [Lift]
heaviestDaily movement sessions = mapMaybe select (groupBy sameDay (sortOn dayOf (liftRows movement sessions)))
 where
  dayOf (day,_,_,_) = day
  sameDay a b = dayOf a == dayOf b
  select (row:rows) = Just (foldl heavier row rows)
  select [] = Nothing
  heavier current@(_,currentLoad,_,_) candidate@(_,candidateLoad,_,_)
   | candidateLoad > currentLoad = candidate
   | otherwise = current

bestLift :: Text -> [TrainingSession] -> Maybe Lift
bestLift movement sessions = case liftRows movement sessions of
 [] -> Nothing
 rows -> Just (maximumBy (comparing (\(day,load,_,_) -> (load,day))) rows)
liftJSON :: Lift -> Value
liftJSON (day,load,reps,effort) = object ["data" .= day,"valor" .= load,"repeticoes" .= reps,"rpe" .= effort]
totalFor :: [TrainingSession] -> Maybe Double
totalFor sessions = sum <$> traverse (fmap (\(_,load,_,_) -> load) . (`bestLift` sessions)) ["agachamento","supino","terra"]

studentProfile :: Database -> Account -> Int64 -> Int -> Text -> IO Value
studentProfile database account studentId period volumePeriod = withDatabaseTransaction database $ \connection -> do
 person <- ensureOwner connection account studentId
 profileData connection studentId person period volumePeriod

ownProfile :: Database -> Account -> Int -> Text -> IO Value
ownProfile database account period volumePeriod = do
 unless (accountRole account=="aluno") (throwIO PermissionDenied)
 withDatabaseTransaction database $ \connection -> do
  people <- query connection "SELECT nome,email FROM alunos WHERE id=?" (Only (accountId account)) :: IO [(Text,Maybe Text)]
  case people of
   [person] -> profileData connection (accountId account) person period volumePeriod
   _ -> throwIO StudentNotFound

profileData :: Connection -> Int64 -> (Text,Maybe Text) -> Int -> Text -> IO Value
profileData connection studentId (studentName,studentEmail) period volumePeriod = do
 today <- appToday
 profileRows <- query connection "SELECT foto,categoria,bloco,inicio_bloco,semanas FROM perfis_alunos WHERE aluno_id=?" (Only studentId) :: IO [(Maybe Text,Maybe Text,Text,Maybe Day,Int)]
 weights <- query connection "SELECT data,peso FROM pesos_alunos WHERE aluno_id=? AND data<=? ORDER BY data" (studentId,today) :: IO [(Day,Double)]
 weightOrigins <- query connection "SELECT data,origem FROM pesos_alunos WHERE aluno_id=? AND data<=?" (studentId,today) :: IO [(Day,Text)]
 (sessions,issues) <- loadSessionData connection studentId
 let pastSessions = filter (\session -> situacao session=="ativa" && dataTreino session<=today) sessions
     (photo,sex,block,start,weeks) = case profileRows of [row] -> row; _ -> (Nothing,Nothing,"",Nothing,4)
     currentWeight = snd <$> listToMaybe (reverse weights)
     total = totalFor pastSessions
     currentDots = do category <- sex; weight <- currentWeight; result <- total; dots category weight result
     -- ISO weekday, Monday = 1. Avoid locale-dependent week boundaries.
     monday day = let (_,_,weekday) = toWeekDate day in addDays (fromIntegral (1-weekday)) day
     (year,month,_) = toGregorian today
     currentStart = if volumePeriod == "mes" then fromGregorian year month 1 else monday today
     elapsed = diffDays today currentStart + 1
     previousStart = if volumePeriod == "mes" then addGregorianMonthsClip (-1) currentStart else addDays (-7) currentStart
     previousEnd = min (addDays (elapsed-1) previousStart) (addDays (-1) currentStart)
     volumeBetween a b = sum [sessionVolume s | s <- pastSessions, dataTreino s >= a, dataTreino s <= b]
     volumeNow = volumeBetween currentStart today
     volumeBefore = volumeBetween previousStart previousEnd
     variation = if volumeBefore == 0 then Nothing else Just ((volumeNow-volumeBefore)/volumeBefore*100)
     fromDay = addDays (negate (fromIntegral period)+1) today
     movementHistory movement =
      let allLifts = liftRows movement pastSessions
          highest = maximum (0 : [load | (_,load,_,_) <- allLifts])
          point (day,load,reps,effort) = object
           ["data" .= day,"valor" .= load,"repeticoes" .= reps,"rpe" .= effort
           ,"prMovimento" .= highest,"percentualPr" .= (if highest > 0 then Just (load/highest*100) else Nothing :: Maybe Double)]
      in map point (filter (\(day,_,_,_) -> day >= fromDay) (heaviestDaily movement pastSessions))
     days = sortOn Prelude.id (nub ([dataTreino s | s <- pastSessions, dataTreino s >= fromDay] ++ [day | (day,_) <- weights,day >= fromDay]))
     totalPoints = [object ["data" .= day,"valor" .= value] | day <- days, Just value <- [totalFor (filter ((<=day) . dataTreino) pastSessions)]]
     weightPoints = [object ["data" .= day,"valor" .= value,"origem" .= lookup day weightOrigins,"variacaoAnterior" .= fmap (\(_,before) -> value-before) previous] | ((day,value),previous) <- zip weights (Nothing:map Just weights),day >= fromDay]
     dotsPoints = [object ["data" .= day,"valor" .= value] | day <- days, Just category <- [sex], Just (_,weight) <- [listToMaybe (reverse (filter ((<=day) . fst) weights))], Just result <- [totalFor (filter ((<=day) . dataTreino) pastSessions)], Just value <- [dots category weight result]]
     weekDays = sortOn Prelude.id (nub [monday (dataTreino s) | s <- pastSessions,dataTreino s >= fromDay])
     volumePoints = [object ["data" .= day,"valor" .= volumeBetween day (addDays 6 day)] | day <- weekDays]
     weekNumber = fmap (\day -> max 0 (min weeks (fromIntegral (diffDays today day `div` 7)+1))) start
     blockStatus :: Text
     blockStatus = case start of Nothing -> "sem_bloco"; Just day | today < day -> "agendado"; Just day | today >= addDays (fromIntegral (weeks*7)) day -> "finalizado"; _ -> "ativo"
     calendar s = object ["sessao" .= s,"status" .= (if situacao s/="ativa" then situacao s else if tipoDia (prescricao s)=="descanso" then "descanso" else if concluido s then executionStatus s else if dataTreino s < today then "perdido" else "agendado" :: Text)]
 pure $ object
  ["aluno" .= object ["id" .= studentId,"nome" .= studentName,"email" .= studentEmail,"foto" .= photo]
  ,"perfil" .= object ["foto" .= photo,"categoria" .= sex,"bloco" .= block,"inicioBloco" .= start,"semanas" .= weeks,"semanaAtual" .= weekNumber,"statusBloco" .= blockStatus,"peso" .= currentWeight,"dataPeso" .= (fst <$> listToMaybe (reverse weights)),"dots" .= currentDots]
  ,"kpis" .= object ["agachamento" .= fmap liftJSON (bestLift "agachamento" pastSessions),"supino" .= fmap liftJSON (bestLift "supino" pastSessions),"terra" .= fmap liftJSON (bestLift "terra" pastSessions),"total" .= total,"volume" .= volumeNow,"variacao" .= variation,"volumeAnterior" .= volumeBefore,"inicioPeriodo" .= currentStart,"fimAnterior" .= previousEnd]
  ,"historico" .= object ["agachamento" .= movementHistory "agachamento","supino" .= movementHistory "supino","terra" .= movementHistory "terra","total" .= totalPoints,"volume" .= volumePoints,"peso" .= weightPoints,"dots" .= dotsPoints]
  ,"calendario" .= (map calendar sessions++[object ["sessao" .= issue,"status" .= ("indisponivel"::Text)] | issue<-issues]),"sessoesInvalidas" .= issues,"dadosIncompletos" .= not(null issues),"hoje" .= today]
