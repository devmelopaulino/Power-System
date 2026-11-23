{-# LANGUAGE OverloadedStrings #-}

module API.Auth (AuthContext, newAuthContext, authMiddleware) where

import API.ReliableWrite (protectedWrite,reliableWrite)
import Data.IORef (newIORef,atomicModifyIORef')
import Auth.Google
import Auth.Store
import qualified Training.Profile as Training
import Control.Exception (AsyncException, SomeException, catch, fromException, throwIO)
import Data.Aeson (FromJSON (..), Value, eitherDecode, encode, object, toJSON, withObject, (.:), (.:?), (.=))
import Data.ByteArray (constEq)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Int (Int64)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Database.Connection (Database)
import Database.PostgreSQL.Simple (SqlError (..))
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types
  ( ResponseHeaders, Status, status200, status201, status204, status302, status400
  , status401, status403, status404, status405, status409, status413, status503 )
import Network.Wai (Middleware, Request(..), Response, getRequestBodyChunk, pathInfo, queryString, requestHeaders, requestMethod, responseLBS, setRequestBodyChunks)
import Text.Read (readMaybe)
import Web.Cookie (parseCookies)

data AuthContext = AuthContext (Maybe Database) (Maybe GoogleConfig) Manager
newAuthContext :: Maybe Database -> IO AuthContext
newAuthContext database = AuthContext database <$> loadGoogleConfig <*> newManager tlsManagerSettings

privateHeaders :: ResponseHeaders
privateHeaders = [("Cache-Control", "no-store"), ("Referrer-Policy", "no-referrer"), ("X-Content-Type-Options", "nosniff")]
jsonResponse :: Status -> Value -> Response
jsonResponse status value = responseLBS status (("Content-Type", "application/json; charset=utf-8") : privateHeaders) (encode value)
message :: Status -> Text -> Response
message status text = jsonResponse status (object ["erro" .= text])
unavailable :: Response
unavailable = message status503 "O acesso esta temporariamente indisponivel."
unauthorized :: Response
unauthorized = message status401 "Entre na sua conta para continuar."
redirect :: BS.ByteString -> ResponseHeaders -> Response
redirect location headers = responseLBS status302 (("Location", location) : privateHeaders ++ headers) ""
configuration :: AuthContext -> Maybe (Database, GoogleConfig)
configuration (AuthContext database config _) = (,) <$> database <*> config
sessionName :: GoogleConfig -> BS.ByteString
sessionName config = if secureCookies config then "__Host-ps_session" else "ps_session"
signupName :: GoogleConfig -> BS.ByteString
signupName config = if secureCookies config then "__Host-ps_student_signup" else "ps_student_signup"
clearSignup :: GoogleConfig -> ResponseHeaders
clearSignup config = cookieHeader config (signupName config) "" "/" "0"
stateName :: GoogleConfig -> BS.ByteString
stateName config = if secureCookies config then "__Secure-ps_oauth_state" else "ps_oauth_state"
cookieHeader :: GoogleConfig -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString -> ResponseHeaders
cookieHeader config name value path age = [("Set-Cookie", name <> "=" <> value <> "; Path=" <> path
  <> "; Max-Age=" <> age <> "; HttpOnly; SameSite=Lax" <> if secureCookies config then "; Secure" else "")]
clearState :: GoogleConfig -> ResponseHeaders
clearState config = cookieHeader config (stateName config) "" "/api/auth/google" "0"
loginFailure :: AuthContext -> Text -> Response
loginFailure context code = case configuration context of
  Just (_, config) -> redirect (encodeUtf8 (appBaseUrl config <> "/#/entrar?erro=" <> code)) (clearState config)
  Nothing -> redirect "/#/entrar?erro=indisponivel" []

failureCode :: AuthFailure -> Text
failureCode failure = case failure of
  RegistrationRequired -> "cadastro"
  InviteEmailMismatch -> "convite_email"
  AccountRoleConflict -> "perfil"
  _ -> "convite"
failureResponse :: AuthFailure -> Response
failureResponse failure = case failure of
  SessionConflict -> message status409 "Esta sessao foi atualizada por outra pessoa. Suas alteracoes foram preservadas. Recarregue a sessao e revise antes de salvar."
  ExecutedIdentityLocked -> message status409 "Este treino ja possui execucao. Nao e possivel alterar seus exercicios, numero de series ou data pela prescricao."
  PermissionDenied -> message status403 "Sua conta nao tem permissao para esta acao. Confira a conta utilizada."
  StudentNotFound -> message status404 "Aluno nao encontrado."
  StudentAlreadyActive -> message status409 "Este aluno ja possui acesso."
  InvalidStudent -> message status400 "Informe seu nome e o e-mail da sua conta Google."
  InvalidStudentName -> message status400 "Informe seu nome, com ate 120 caracteres."
  SignupExpired -> message status401 "Seu cadastro expirou. Abra o convite e entre com Google novamente."
  InviteEmailMismatch -> message status403 "Use a mesma conta Google do e-mail preenchido no cadastro."
  _ -> message status404 "Convite indisponivel, expirado ou ja utilizado."

readCookie :: BS.ByteString -> Request -> Maybe Text
readCookie name request = do
  header <- lookup "Cookie" (requestHeaders request)
  value <- lookup name (parseCookies header)
  either (const Nothing) Just (decodeUtf8' value)
parameter :: BS.ByteString -> Request -> Maybe Text
parameter name request = case [value | (key, Just value) <- queryString request, key == name] of
  [value] -> either (const Nothing) Just (decodeUtf8' value)
  _ -> Nothing
validToken :: Text -> Bool
validToken value = Text.length value == 43 && Text.all (\char ->
  (char >= 'A' && char <= 'Z') || (char >= 'a' && char <= 'z') ||
  (char >= '0' && char <= '9') || char == '-' || char == '_') value

-- Limita o corpo antes de decodificar: os cadastros nao aceitam cargas arbitrarias.
readJSON :: FromJSON a => Request -> IO (Either Response a)
readJSON request = collect (if (take 2 (pathInfo request) == ["api","alunos"] && last (pathInfo request) == "treinos") || take 3 (pathInfo request) == ["api","auth","treinos"] then 262144 else 16384) []
  where
    collect remaining chunks = do
      chunk <- getRequestBodyChunk request
      if BS.length chunk > remaining then pure (Left (message status413 "Solicitacao muito grande."))
        else if BS.null chunk then pure $ case eitherDecode (LBS.fromChunks (reverse chunks)) of
          Left _ -> Left (message status400 "Dados invalidos.")
          Right value -> Right value
        else collect (remaining - BS.length chunk) (chunk:chunks)

data StudentInput = StudentInput Text Text
instance FromJSON StudentInput where parseJSON = withObject "Aluno" $ \value -> StudentInput <$> value .: "nome" <*> value .: "email"
newtype InviteInput = InviteInput Text
instance FromJSON InviteInput where parseJSON = withObject "Convite" $ \value -> InviteInput <$> value .: "token"
data NameInput = NameInput Text (Maybe Double)
instance FromJSON NameInput where parseJSON = withObject "Nome do aluno" $ \value -> NameInput <$> value .: "nome" <*> value .:? "peso"

authMiddleware :: AuthContext -> Middleware
authMiddleware context application request respond
  | take 2 (pathInfo request) `elem` [["api","auth"],["api","alunos"],["api","convites"]] = do
      response <- dispatch context request `catch` recover
      respond response
  | otherwise = application request respond
  where
    recover :: SomeException -> IO Response
    recover err = case fromException err :: Maybe AsyncException of
      Just _ -> throwIO err
      Nothing -> case fromException err :: Maybe AuthFailure of
        Just failure -> pure $ if pathInfo request == ["api","auth","google","callback"]
          then loginFailure context (failureCode failure) else failureResponse failure
        Nothing -> case fromException err :: Maybe SqlError of
          Just sqlError | sqlState sqlError == "23505" && requestMethod request == "POST" && pathInfo request == ["api","alunos"] ->
            pure (message status409 "Ja existe um aluno com este e-mail na sua lista.")
          _ -> do
            putStrLn "Falha ao processar acesso ou cadastro."
            pure $ if pathInfo request == ["api","auth","google","callback"] then loginFailure context "google" else unavailable

dispatch :: AuthContext -> Request -> IO Response
dispatch context request | not(protectedWrite request) = route context request
dispatch context request = authenticated context request $ \database account -> case configuration context of
 Just(_,config) | csrfAllowed config request -> do
  let roleAllowed = if take 2(pathInfo request)==["api","alunos"] then accountRole account=="treinador" else accountRole account=="aluno"
      scope=accountRole account<>":"<>Text.pack(show(accountId account))
  if not roleAllowed then pure(failureResponse PermissionDenied) else case lookup "X-Power-System-Account" (requestHeaders request) of
   Just expected | expected/=encodeUtf8 scope -> pure(message status409 "A conta mudou. Recarregue a pagina antes de salvar.")
   _ -> case lookup "Idempotency-Key" (requestHeaders request) >>= either (const Nothing) Just . decodeUtf8' of
    Just key | Text.length key>=16 && Text.length key<=128 && Text.all (\char->char>='a'&&char<='z'||char>='A'&&char<='Z'||char>='0'&&char<='9'||char `elem` ['-','_']) key -> do
     payload <- readJSON request :: IO(Either Response Value)
     case payload of
      Left response -> pure response
      Right value -> do
       let bytes=encode value
       chunks <- newIORef(LBS.toChunks bytes)
       let buffered=setRequestBodyChunks (atomicModifyIORef' chunks (\remaining->case remaining of []->([],BS.empty);chunk:rest->(rest,chunk))) request
           path="/"<>Text.intercalate "/"(pathInfo request)
       reliableWrite database account key path bytes $ \transaction -> case context of
        AuthContext _ google manager -> route (AuthContext(Just transaction) google manager) buffered
    _ -> pure(message status400 "Atualize a pagina para iniciar uma tentativa de salvamento protegida.")
 _ -> pure(message status403 "Solicitacao invalida.")

route :: AuthContext -> Request -> IO Response
route context request = case (requestMethod request, pathInfo request) of
  ("GET", ["api","auth","config"]) -> pure $ jsonResponse status200 (object ["google" .= isJust (configuration context)])
  ("GET", ["api","auth","google"]) -> beginLogin context request
  ("POST", ["api","auth","google","convite"]) -> beginStudentLogin context request
  ("GET", ["api","auth","google","callback"]) -> finishLogin context request
  ("GET", ["api","auth","me"]) -> authenticated context request $ \_ account -> pure (jsonResponse status200 (toJSON account))
  ("GET", ["api","auth","cadastro-aluno"]) -> signupDetails context request
  ("POST", ["api","auth","cadastro-aluno"]) -> finishStudentSignup context request
  ("GET", ["api","alunos"]) -> authenticated context request $ \database account -> jsonResponse status200 <$> Training.studentOverview database account
  ("GET", ["api","auth","perfil"]) -> authenticated context request $ \database account -> do
    let period = case parameter "periodo" request of Just "90" -> 90; Just "180" -> 180; Just "365" -> 365; _ -> 30
        volumePeriod = case parameter "volume" request of Just "mes" -> "mes"; _ -> "semana"
    jsonResponse status200 <$> Training.ownProfile database account period volumePeriod
  ("POST", ["api","auth","perfil"]) -> authenticated context request $ \database account -> case configuration context of
    Just (_,config) | csrfAllowed config request -> do
      input <- readJSON request
      case input of
        Left response -> pure response
        Right profile -> do
          saved <- Training.saveOwnProfile database account profile
          pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Informe um nome de 1 a 120 caracteres e selecione um genero valido."
    _ -> pure (message status403 "Solicitacao invalida.")
  ("GET", ["api","auth","treinos",identifier,"historico"]) -> authenticated context request $ \database account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just sessionId | sessionId>0 -> jsonResponse status200 <$> Training.sessionHistory database account (accountId account) sessionId
      _ -> pure (message status404 "Sessao nao encontrada.")
  ("GET", ["api","alunos",student,"treinos",identifier,"historico"]) -> authenticated context request $ \database account ->
    case (readMaybe (Text.unpack student),readMaybe (Text.unpack identifier)) :: (Maybe Int64,Maybe Int64) of
      (Just studentId,Just sessionId) | studentId>0 && sessionId>0 -> jsonResponse status200 <$> Training.sessionHistory database account studentId sessionId
      _ -> pure (message status404 "Sessao nao encontrada.")
  ("POST", ["api","alunos",student,"treinos",identifier,"recuperar"]) -> coachMutation context request $ \database _ account ->
    case (readMaybe (Text.unpack student),readMaybe (Text.unpack identifier)) :: (Maybe Int64,Maybe Int64) of
      (Just studentId,Just sessionId) | studentId>0 && sessionId>0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right change -> do
            saved <- Training.recoverSession database account studentId sessionId change
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Informe um motivo. A recuperacao exige dados invalidos e uma versao valida no historico; nenhuma carga sera inventada."
      _ -> pure (message status404 "Sessao nao encontrada.")
  ("POST", ["api","alunos",student,"treinos",identifier,action]) | action `elem` ["cancelar","anular"] -> coachMutation context request $ \database _ account ->
    case (readMaybe (Text.unpack student),readMaybe (Text.unpack identifier)) :: (Maybe Int64,Maybe Int64) of
      (Just studentId,Just sessionId) | studentId>0 && sessionId>0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right change -> do
            saved <- Training.changeSessionState database account studentId sessionId action change
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Informe um motivo (3 a 1000 caracteres). Cancele apenas prescricoes sem execucao; anule apenas sessoes com execucao."
      _ -> pure (message status404 "Sessao nao encontrada.")
  ("GET", ["api","auth","treinos"]) -> authenticated context request $ \database account -> jsonResponse status200 <$> Training.ownSessions database account
  ("POST", ["api","auth","treinos",identifier]) -> authenticated context request $ \database account -> case configuration context of
    Just (_,config) | csrfAllowed config request -> case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just sessionId | sessionId>0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right session -> do
            saved <- Training.recordExecution database account sessionId session
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Verifique a sessao, a data e os dados de execucao."
      _ -> pure (message status404 "Sessao nao encontrada.")
    _ -> pure (message status403 "Solicitacao invalida.")
  ("GET", ["api","auth","dados-atleta"]) -> authenticated context request $ \database account -> jsonResponse status200 <$> Training.ownAthleteData database account
  ("POST", ["api","auth","pesagens"]) -> authenticated context request $ \database account -> case configuration context of
    Just (_,config) | csrfAllowed config request -> do
      input <- readJSON request
      case input of
        Left response -> pure response
        Right weight -> do
          saved <- Training.recordWeight database account weight
          pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Informe um peso entre 1 e 500 kg e uma data que nao seja futura."
    _ -> pure (message status403 "Solicitacao invalida.")
  ("GET", ["api","alunos",identifier,"dados-atleta"]) -> authenticated context request $ \database account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId > 0 -> jsonResponse status200 <$> Training.athleteData database account studentId
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","alunos",identifier,"dados-atleta"]) -> coachMutation context request $ \database _ account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId>0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right settings -> do
            saved <- Training.saveAthleteSettings database account studentId settings
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Verifique o genero e a categoria de peso alvo."
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","alunos",identifier,"pesagens",reading,action]) | action `elem` ["editar","excluir"] -> coachMutation context request $ \database _ account ->
    case (readMaybe (Text.unpack identifier),readMaybe (Text.unpack reading)) :: (Maybe Int64,Maybe Int64) of
      (Just studentId,Just eventId) | studentId>0 && eventId>0 -> do
        input <- if action=="excluir" then pure (Right Nothing) else fmap (fmap Just) (readJSON request)
        case input of
          Left response -> pure response
          Right replacement -> do
            saved <- Training.correctWeight database account studentId eventId replacement
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Pesagem nao encontrada ou dados invalidos."
      _ -> pure (message status404 "Pesagem nao encontrada.")
  ("GET", ["api","alunos",identifier,"perfil"]) -> authenticated context request $ \database account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId > 0 -> do
        let period = case parameter "periodo" request of Just "90" -> 90; Just "180" -> 180; Just "365" -> 365; _ -> 30
            volumePeriod = case parameter "volume" request of Just "mes" -> "mes"; _ -> "semana"
        jsonResponse status200 <$> Training.studentProfile database account studentId period volumePeriod
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","alunos",identifier,"perfil"]) -> coachMutation context request $ \database _ account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId > 0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right profile -> do
            saved <- Training.saveProfile database account studentId profile
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Verifique o peso, a categoria, a foto e as datas do bloco."
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","alunos",identifier,"treinos"]) -> coachMutation context request $ \database _ account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId > 0 -> do
        input <- readJSON request
        case input of
          Left response -> pure response
          Right session -> do
            saved <- Training.saveSession database account studentId session
            pure $ if saved then jsonResponse status200 (object ["salvo" .= True]) else message status400 "Verifique as series, as cargas, as datas e o RPE (1 a 10)."
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","alunos"]) -> coachMutation context request $ \database config account -> do
    input <- readJSON request
    case input of
      Left response -> pure response
      Right (StudentInput name email) -> do
        token <- newToken
        student <- createStudent database account name email token
        pure (jsonResponse status201 (object ["aluno" .= student, "convite" .= inviteLink config token, "expiraEmDias" .= (7 :: Int)]))
  ("POST", ["api","alunos",identifier,"convite"]) -> coachMutation context request $ \database config account ->
    case readMaybe (Text.unpack identifier) :: Maybe Int64 of
      Just studentId | studentId > 0 -> do
        token <- newToken
        renewInvite database account studentId token
        pure (jsonResponse status200 (object ["convite" .= inviteLink config token, "expiraEmDias" .= (7 :: Int)]))
      _ -> pure (message status404 "Aluno nao encontrado.")
  ("POST", ["api","convites","verificar"]) -> previewInvite context request
  ("POST", ["api","convites"]) -> coachMutation context request $ \database config account -> do
    token <- newToken
    createDirectInvite database account token
    pure (jsonResponse status201 (object ["convite" .= inviteLink config token, "expiraEmDias" .= (7 :: Int)]))
  ("POST", ["api","auth","logout"]) -> logout context request
  (_, ["api","auth",endpoint]) | endpoint `elem` ["config","google","me","logout"] -> pure (message status405 "Metodo nao permitido.")
  _ -> pure (message status404 "Rota nao encontrada.")

inviteLink :: GoogleConfig -> Text -> Text
inviteLink config token = appBaseUrl config <> "/#/convite/" <> token

previewInvite :: AuthContext -> Request -> IO Response
previewInvite (AuthContext Nothing _ _) _ = pure unavailable
previewInvite (AuthContext (Just database) _ _) request = do
  input <- readJSON request
  case input of
    Left response -> pure response
    Right (InviteInput token) | validToken token -> do
      summary <- inviteSummary database (hashToken token)
      pure $ maybe (failureResponse InviteInvalid) (jsonResponse status200 . toJSON) summary
    _ -> pure (failureResponse InviteInvalid)

beginLogin :: AuthContext -> Request -> IO Response
beginLogin context request = case configuration context of
  Nothing -> pure unavailable
  Just (database, config) -> do
    inviteHash <- case parameter "convite" request of
      Nothing -> pure Nothing
      Just token | validToken token -> do
        summary <- inviteSummary database (hashToken token)
        if isJust summary then pure (Just (hashToken token)) else throwIO InviteInvalid
      _ -> throwIO InviteInvalid
    let registering = isNothing inviteHash && parameter "cadastro" request == Just "treinador"
    state <- newToken
    verifier <- newToken
    saveOAuthRequest database state verifier inviteHash registering
    pure $ redirect (authorizationUrl config state verifier) (cookieHeader config (stateName config) (encodeUtf8 state) "/api/auth/google" "600")

beginStudentLogin :: AuthContext -> Request -> IO Response
beginStudentLogin context request = case configuration context of
  Nothing -> pure unavailable
  Just (database,config) | csrfAllowed config request -> do
    input <- readJSON request
    case input of
      Left response -> pure response
      Right (InviteInput token) | validToken token -> do
        summary <- inviteSummary database (hashToken token)
        if isNothing summary then throwIO InviteInvalid else do
          state <- newToken
          verifier <- newToken
          saveOAuthRequest database state verifier (Just (hashToken token)) False
          pure $ responseLBS status200
            (("Content-Type","application/json; charset=utf-8") : privateHeaders ++ cookieHeader config (stateName config) (encodeUtf8 state) "/api/auth/google" "600")
            (encode (object ["url" .= either (const ("" :: Text)) id (decodeUtf8' (authorizationUrl config state verifier))]))
      _ -> pure (failureResponse InviteInvalid)
  _ -> pure (message status403 "Solicitacao invalida.")

finishLogin :: AuthContext -> Request -> IO Response
finishLogin context@(AuthContext _ _ manager) request = case configuration context of
  Nothing -> pure (loginFailure context "indisponivel")
  Just (database, config) -> case (parameter "state" request, readCookie (stateName config) request) of
    (Just state, Just cookieState) | validToken state && validToken cookieState && constEq (encodeUtf8 state) (encodeUtf8 cookieState) -> do
      attempt <- consumeOAuthRequest database state
      case (attempt, parameter "code" request, parameter "error" request) of
        (Just (verifier,invite,registering,_), Just code, Nothing) | not (Text.null code) && Text.length code <= 4096 -> do
          profile <- googleProfile manager config code verifier
          token <- newToken
          case invite of
            Just inviteHash -> do
              beginStudentSignup database inviteHash (googleSubject profile) (googleEmail profile) token
              pure $ redirect (encodeUtf8 (appBaseUrl config <> "/#/completar-cadastro"))
                (clearState config ++ cookieHeader config (signupName config) (encodeUtf8 token) "/" "600")
            Nothing -> do
              account <- completeLogin database registering Nothing (googleSubject profile) (googleEmail profile) (googleName profile) token
              replaceSession database config request
              let destination = if accountRole account == "treinador" then "/#/alunos" else "/#/meus-treinos"
              pure $ redirect (encodeUtf8 (appBaseUrl config <> destination))
                (clearState config ++ clearSignup config ++ cookieHeader config (sessionName config) (encodeUtf8 token) "/" "604800")
        _ -> pure (loginFailure context "google")
    _ -> pure (loginFailure context "google")

replaceSession :: Database -> GoogleConfig -> Request -> IO ()
replaceSession database config request = case readCookie (sessionName config) request of
  Just previous | validToken previous -> removeSession database previous
  _ -> pure ()

signupDetails :: AuthContext -> Request -> IO Response
signupDetails context request = case configuration context of
  Nothing -> pure unavailable
  Just (database,config) -> case readCookie (signupName config) request of
    Just ticket | validToken ticket -> do
      pending <- pendingStudentSignup database ticket
      pure $ maybe (failureResponse SignupExpired) (jsonResponse status200 . toJSON) pending
    _ -> pure (failureResponse SignupExpired)

finishStudentSignup :: AuthContext -> Request -> IO Response
finishStudentSignup context request = case configuration context of
  Nothing -> pure unavailable
  Just (database,config) | csrfAllowed config request -> case readCookie (signupName config) request of
    Just ticket | validToken ticket -> do
      input <- readJSON request
      case input of
        Left response -> pure response
        Right (NameInput _ (Just weight)) | isNaN weight || isInfinite weight || weight<1 || weight>500 -> pure (message status400 "Informe um peso entre 1 e 500 kg.")
        Right (NameInput name weight) -> do
          token <- newToken
          _ <- confirmStudentSignupWithWeight database ticket name token weight
          replaceSession database config request
          pure $ responseLBS status200
            (("Content-Type","application/json; charset=utf-8") : privateHeaders ++ clearSignup config ++ cookieHeader config (sessionName config) (encodeUtf8 token) "/" "604800")
            (encode (object ["destino" .= ("/#/meus-treinos" :: Text)]))
    _ -> pure (failureResponse SignupExpired)
  _ -> pure (message status403 "Solicitacao invalida.")

authenticated :: AuthContext -> Request -> (Database -> Account -> IO Response) -> IO Response
authenticated context request action = case configuration context of
  Nothing -> pure unavailable
  Just (database, config) -> case readCookie (sessionName config) request of
    Just token | validToken token -> do
      account <- findAccount database token
      maybe (pure unauthorized) (action database) account
    _ -> pure unauthorized

csrfAllowed :: GoogleConfig -> Request -> Bool
csrfAllowed config request = lookup "Origin" (requestHeaders request) == Just (encodeUtf8 (appBaseUrl config))
  && lookup "X-Power-System-Request" (requestHeaders request) == Just "1"
coachMutation :: AuthContext -> Request -> (Database -> GoogleConfig -> Account -> IO Response) -> IO Response
coachMutation context request action = authenticated context request $ \database account -> case configuration context of
  Just (_, config) | csrfAllowed config request -> if accountRole account == "treinador" then action database config account else throwIO PermissionDenied
  _ -> pure (message status403 "Solicitacao invalida.")

logout :: AuthContext -> Request -> IO Response
logout context request = case configuration context of
  Nothing -> pure unavailable
  Just (database, config)
    | not (csrfAllowed config request) -> pure (message status403 "Solicitacao invalida.")
    | otherwise -> do
        case readCookie (sessionName config) request of
          Just token | validToken token -> removeSession database token
          _ -> pure ()
        case readCookie (signupName config) request of
          Just ticket | validToken ticket -> cancelStudentSignup database ticket
          _ -> pure ()
        pure $ responseLBS status204 (privateHeaders ++ clearSignup config ++ cookieHeader config (sessionName config) "" "/" "0") ""
