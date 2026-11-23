{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import API.Auth (authMiddleware, newAuthContext)
import Auth.Store
import TrainingSpec (checkTraining)
import Control.Exception (bracket, try)
import Control.Monad (unless, void)
import Data.Aeson (FromJSON (..), eitherDecode, toJSON, encode, object, withObject, (.:), (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe, isJust, isNothing)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Database.Connection (initializeDatabase, withDatabase)
import Database.PostgreSQL.Simple (Only (..), SqlError (..), connectPostgreSQL, close, execute, execute_, query, withTransaction)
import Database.PostgreSQL.Simple.Types (Query (..))
import Network.HTTP.Types (HeaderName, parseQuery, status200, status204, status302, status400, status401, status403, status405, status201, status409, status413)
import Network.Wai (Application, Request (..), defaultRequest, responseLBS)
import Network.Wai.Test (SRequest (..), SResponse, request, srequest, runSession, setPath, simpleBody, simpleHeaders, simpleStatus)
import System.Environment (lookupEnv, setEnv)
import System.Exit (die)

check :: String -> Bool -> IO ()
check label condition = unless condition (die ("FALHOU: " ++ label))

send :: Application -> Request -> IO SResponse
send application req = runSession (request req) application

get :: BS.ByteString -> Request
get = setPath defaultRequest

header :: HeaderName -> SResponse -> BS.ByteString
header name response = fromMaybe "" (lookup name (simpleHeaders response))

newtype GoogleStart = GoogleStart Text.Text
instance FromJSON GoogleStart where parseJSON = withObject "GoogleStart" $ \value -> GoogleStart <$> value .: "url"
newtype CreatedInvite = CreatedInvite Text.Text
instance FromJSON CreatedInvite where parseJSON = withObject "CreatedInvite" $ \value -> CreatedInvite <$> value .: "convite"

main :: IO ()
main = do
  configured <- lookupEnv "AUTH_TEST_DATABASE_URL"
  url <- maybe (die "Configure AUTH_TEST_DATABASE_URL para um banco local descartavel.") pure configured
  check "banco de testes isolado" ("@127.0.0.1:5433/power_system_auth_test_" `contains` url)
  setEnv "DATABASE_URL" url
  setEnv "GOOGLE_CLIENT_ID" "auth-tests.apps.googleusercontent.com"
  setEnv "GOOGLE_CLIENT_SECRET" "somente-testes-sem-chamadas-ao-google"
  setEnv "APP_BASE_URL" "http://localhost:5173"
  -- Simula uma conta e sessao existentes antes da migracao para dois perfis.
  legacySession <- newToken
  bracket (connectPostgreSQL (encodeUtf8 (Text.pack url))) close $ \connection -> withTransaction connection $ do
    initial <- BS.readFile "migrations/001_initial.sql"
    googleSchema <- BS.readFile "migrations/002_google_auth.sql"
    void $ execute_ connection (Query initial)
    void $ execute_ connection (Query googleSchema)
    void $ execute_ connection "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, aplicada_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    void $ execute_ connection "INSERT INTO schema_migrations (version) VALUES (1),(2)"
    void $ execute_ connection "INSERT INTO treinadores (nome,email,google_sub) VALUES ('Treinador preservado','preservado@example.invalid','google-preservado')"
    void $ execute connection "INSERT INTO sessoes (token_hash,treinador_id) SELECT ?,id FROM treinadores WHERE google_sub='google-preservado'" (Only (hashToken legacySession))
  initialized <- initializeDatabase
  database <- maybe (die "Banco indisponivel") pure initialized
  void initializeDatabase
  preserved <- findAccount database legacySession
  check "migracao preserva treinador e sessao existentes" (maybe False ((== "treinador") . accountRole) preserved)
  context <- newAuthContext (Just database)
  let application = authMiddleware context (\_ respond -> respond (responseLBS status200 [] "fallback"))
  anonymous <- send application (get "/api/auth/me")
  check "sessao obrigatoria" (simpleStatus anonymous == status401)
  studentsAnonymous <- send application (get "/api/alunos")
  check "alunos protegidos" (simpleStatus studentsAnonymous == status401)

  start <- send application (get "/api/auth/google")
  check "redireciona para Google" (simpleStatus start == status302 && "https://accounts.google.com/" `BS.isPrefixOf` header "Location" start)
  check "cookie OAuth HttpOnly" ("HttpOnly" `BS.isInfixOf` header "Set-Cookie" start)
  check "cookie OAuth SameSite" ("SameSite=Lax" `BS.isInfixOf` header "Set-Cookie" start)
  let parameters = parseQuery (BS.dropWhile (/= 63) (header "Location" start))
      state = decodeUtf8 (fromMaybe "" (lookup "state" parameters >>= id))
      oauthCookie = BS.takeWhile (/= 59) (header "Set-Cookie" start)
      callback = (get "/api/auth/google/callback")
        { queryString = [("state", Just (encodeUtf8 state)), ("error", Just "access_denied")] }
  check "PKCE S256" (lookup "code_challenge_method" parameters == Just (Just "S256"))
  check "state aleatorio" (Text.length state == 43)
  missingCookie <- send application callback
  check "callback sem cookie recusado" (simpleStatus missingCookie == status302 && "erro=google" `BS.isSuffixOf` header "Location" missingCookie)
  cancelled <- send application callback { requestHeaders = [("Cookie", oauthCookie)] }
  check "cancelamento nao cria sessao" (not ("ps_session=" `BS.isInfixOf` header "Set-Cookie" cancelled))
  consumed <- consumeOAuthRequest database state
  check "state consumido uma unica vez" (isNothing consumed)

  unknownToken <- newToken
  unknownAccount <- try (completeLogin database False Nothing "google-desconhecido" "desconhecido@example.invalid" "Sem cadastro" unknownToken) :: IO (Either AuthFailure Account)
  check "entrar nao cria treinador automaticamente" (unknownAccount == Left RegistrationRequired)
  firstToken <- newToken
  first <- createCoachSession database "google-test-1" "coach1@example.invalid" "Treinador 1" firstToken
  secondToken <- newToken
  second <- createCoachSession database "google-test-2" "coach2@example.invalid" "Treinador 2" secondToken
  repeatToken <- newToken
  repeated <- createCoachSession database "google-test-1" "coach1@example.invalid" "Nome atualizado" repeatToken
  check "registro nao duplica a conta Google" (accountId first == accountId repeated)
  withDatabase database $ \connection -> do
    stored <- query connection "SELECT token_hash FROM sessoes WHERE conta_sub = ?" (Only (accountSubject first)) :: IO [Only Text.Text]
    check "tokens nao sao guardados em texto puro" (all (\(Only value) -> Text.length value == 64 && value /= firstToken && value /= repeatToken) stored)
    void $ execute connection "INSERT INTO alunos (treinador_id, nome) VALUES (?, ?)" (accountId first, "Aluno do treinador 1" :: Text.Text)
    void $ execute connection "INSERT INTO alunos (treinador_id, nome) VALUES (?, ?)" (accountId second, "Aluno do treinador 2" :: Text.Text)
    void $ execute connection "INSERT INTO treinadores (nome, email) VALUES (?, ?)" ("Conta antiga" :: Text.Text, "legacy@example.invalid" :: Text.Text)
  collisionToken <- newToken
  collision <- try (createCoachSession database "outro-google-sub" "legacy@example.invalid" "Nao vincular" collisionToken) :: IO (Either SqlError Account)
  check "nao vincula conta existente apenas por email" (case collision of Left err -> sqlState err == "23505"; Right _ -> False)
  let cookie = "ps_session=" <> encodeUtf8 firstToken
      signed path = (get path) { requestHeaders = [("Cookie", cookie)] }
  me <- send application (signed "/api/auth/me")
  check "sessao identifica treinador" (simpleStatus me == status200 && eitherDecode (simpleBody me) == Right (toJSON repeated))
  students <- send application (signed "/api/alunos")
  let studentsBody = LBS.toStrict (simpleBody students)
  check "filtra alunos pelo treinador da sessao" (simpleStatus students == status200 && "Aluno do treinador 1" `BS.isInfixOf` studentsBody && not ("Aluno do treinador 2" `BS.isInfixOf` studentsBody))
  inviteToken <- newToken
  Student invitedId _ _ _ <- createStudent database first "Aluno convidado" "student@example.invalid" inviteToken
  validInvite <- inviteSummary database (hashToken inviteToken)
  check "convite criado" (isJust validInvite)
  deniedToken <- newToken
  crossCoach <- try (renewInvite database second invitedId deniedToken) :: IO (Either AuthFailure ())
  check "outro treinador nao renova convite" (crossCoach == Left StudentNotFound)
  wrongEmailToken <- newToken
  wrongEmail <- try (completeLogin database False (Just (hashToken inviteToken)) "google-aluno" "errado@example.invalid" "Aluno" wrongEmailToken) :: IO (Either AuthFailure Account)
  check "convite exige email Google correto" (wrongEmail == Left InviteEmailMismatch)
  retained <- inviteSummary database (hashToken inviteToken)
  check "email incorreto nao consome convite" (isJust retained)
  studentToken <- newToken
  student <- completeLogin database False (Just (hashToken inviteToken)) "google-aluno" "student@example.invalid" "Aluno Google" studentToken
  check "aluno vinculado ao treinador correto" (accountRole student == "aluno" && accountId student == invitedId && accountCoachId student == Just (accountId first))
  studentResponse <- send application (get "/api/alunos") { requestHeaders = [("Cookie","ps_session=" <> encodeUtf8 studentToken)] }
  check "aluno nao acessa lista de alunos" (simpleStatus studentResponse == status403)
  replayToken <- newToken
  replay <- try (completeLogin database False (Just (hashToken inviteToken)) "google-aluno-replay" "student@example.invalid" "Outro" replayToken) :: IO (Either AuthFailure Account)
  check "convite de uso unico" (replay == Left InviteInvalid)
  elevationToken <- newToken
  unchanged <- completeLogin database True Nothing "google-aluno" "student@example.invalid" "Aluno" elevationToken
  check "cadastro treinador nao eleva perfil de aluno" (accountRole unchanged == "aluno")
  activeInvite <- try (renewInvite database first invitedId deniedToken) :: IO (Either AuthFailure ())
  check "nao regenera convite de aluno ativo" (activeInvite == Left StudentAlreadyActive)
  pendingToken <- newToken
  Student pendingId _ _ _ <- createStudent database first "Aluno pendente" "pending@example.invalid" pendingToken
  replacement <- newToken
  renewInvite database first pendingId replacement
  invalidated <- inviteSummary database (hashToken pendingToken)
  available <- inviteSummary database (hashToken replacement)
  check "novo convite revoga o anterior" (isNothing invalidated && isJust available)
  let enrollmentHeaders = [("Origin","http://localhost:5173"),("X-Power-System-Request","1"),("Content-Type","application/json")]
      enrollmentBody = encode (object ["token" .= replacement,"nome" .= ("Nome do proprio aluno" :: Text.Text),"email" .= ("pending@example.invalid" :: Text.Text)])
      enrollmentRequest = (get "/api/auth/google/convite") { requestMethod="POST",requestHeaders=enrollmentHeaders }
  inviteStart <- runSession (srequest (SRequest enrollmentRequest enrollmentBody)) application
  check "cadastro do aluno inicia Google" (simpleStatus inviteStart == status200)
  GoogleStart googleUrl <- either die pure (eitherDecode (simpleBody inviteStart))
  let inviteParameters = parseQuery (BS.dropWhile (/=63) (encodeUtf8 googleUrl))
      inviteState = decodeUtf8 (fromMaybe "" (lookup "state" inviteParameters >>= id))
  boundAttempt <- consumeOAuthRequest database inviteState
  check "inicio do Google ignora nome e email enviados antes de autenticar" (case boundAttempt of Just (_,Just tokenHash,False,Nothing) -> tokenHash == hashToken replacement; _ -> False)
  directGoogle <- send application (get "/api/auth/google") { queryString=[("convite",Just (encodeUtf8 replacement))] }
  check "convite oferece entrada direta com Google" (simpleStatus directGoogle == status302 && "https://accounts.google.com/" `BS.isPrefixOf` header "Location" directGoogle)
  preview <- runSession (srequest (SRequest ((get "/api/convites/verificar") { requestMethod="POST" }) (encode (object ["token" .= replacement])))) application
  check "convite publico nao divulga email do aluno" (simpleStatus preview == status200 && not ("pending@example.invalid" `BS.isInfixOf` LBS.toStrict (simpleBody preview)))
  conflictToken <- newToken
  profileConflict <- try (completeLogin database False (Just (hashToken replacement)) "google-test-1" "coach1@example.invalid" "Treinador" conflictToken) :: IO (Either AuthFailure Account)
  check "conta de treinador nao vira aluno por convite" (profileConflict == Left AccountRoleConflict)
  withDatabase database $ \connection -> void $ execute connection "UPDATE convites_alunos SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE token_hash=?" (Only (hashToken replacement))
  expiredInvite <- inviteSummary database (hashToken replacement)
  check "convite expirado recusado" (isNothing expiredInvite)
  let headersFor token = [("Cookie","ps_session=" <> encodeUtf8 token),("Origin","http://localhost:5173"),("X-Power-System-Request","1"),("Content-Type","application/json")]
      body = encode (object ["nome" .= ("Aluno pela API" :: Text.Text),"email" .= ("api@example.invalid" :: Text.Text),"treinador_id" .= accountId second])
      postFor token = (get "/api/alunos") { requestMethod="POST",requestHeaders=headersFor token }
  created <- runSession (srequest (SRequest (postFor firstToken) body)) application
  check "treinador cadastra aluno pela API" (simpleStatus created == status201)
  withDatabase database $ \connection -> do
    owners <- query connection "SELECT treinador_id FROM alunos WHERE email='api@example.invalid'" () :: IO [Only Int]
    check "id de treinador enviado pelo cliente e ignorado" (owners == [Only (fromIntegral (accountId first))])
  studentCreate <- runSession (srequest (SRequest (postFor studentToken) body)) application
  check "aluno nao pode cadastrar aluno" (simpleStatus studentCreate == status403)
  duplicate <- runSession (srequest (SRequest (postFor firstToken) body)) application
  check "email duplicado retorna conflito" (simpleStatus duplicate == status409)
  invalidData <- runSession (srequest (SRequest (postFor firstToken) (encode (object ["nome" .= (" " :: Text.Text),"email" .= ("sem-email" :: Text.Text)])))) application
  check "dados invalidos recusados" (simpleStatus invalidData == status400)
  oversized <- runSession (srequest (SRequest (postFor firstToken) (LBS.replicate 20000 120))) application
  check "limite do corpo de cadastro" (simpleStatus oversized == status413)
  beforeDirect <- studentsForCoach database first
  let directRequest = (get "/api/convites") { requestMethod="POST",requestHeaders=headersFor firstToken }
  directResponse <- runSession (srequest (SRequest directRequest "{}")) application
  check "treinador gera link sem preencher aluno" (simpleStatus directResponse == status201)
  CreatedInvite directUrl <- either die pure (eitherDecode (simpleBody directResponse))
  let directToken = last (Text.splitOn "/" directUrl)
  afterDirect <- studentsForCoach database first
  check "gerar link nao cria aluno ficticio" (length beforeDirect == length afterDirect)
  studentInviteResponse <- runSession (srequest (SRequest (directRequest { requestHeaders=headersFor studentToken }) "{}")) application
  check "aluno nao gera convite" (simpleStatus studentInviteResponse == status403)
  mismatchToken <- newToken
  mismatch <- try (completeLoginWithEnrollment database False (Just (hashToken directToken)) (Just (Enrollment "Nome preenchido" "self@example.invalid")) "google-self" "outro@example.invalid" "Nome Google" mismatchToken) :: IO (Either AuthFailure Account)
  check "email preenchido precisa ser confirmado pelo Google" (mismatch == Left InviteEmailMismatch)
  notConsumed <- inviteSummary database (hashToken directToken)
  check "erro no email preserva convite" (isJust notConsumed)
  missingFormToken <- newToken
  missingForm <- try (completeLogin database False (Just (hashToken directToken)) "google-self" "self@example.invalid" "Nome Google" missingFormToken) :: IO (Either AuthFailure Account)
  check "convite generico exige formulario do aluno" (missingForm == Left InvalidStudent)
  selfToken <- newToken
  selfRegistered <- completeLoginWithEnrollment database False (Just (hashToken directToken)) (Just (Enrollment "Nome preenchido" "self@example.invalid")) "google-self" "self@example.invalid" "Nome Google diferente" selfToken
  check "cadastro usa nome escolhido e treinador do convite" (accountRole selfRegistered == "aluno" && accountName selfRegistered == "Nome preenchido" && accountCoachId selfRegistered == Just (accountId first))
  afterAcceptance <- studentsForCoach database first
  check "aluno aparece na lista apos confirmar Google" (length afterAcceptance == length beforeDirect + 1)
  repeatDirect <- newToken
  reusedDirect <- try (completeLoginWithEnrollment database False (Just (hashToken directToken)) (Just (Enrollment "Outro" "outro@example.invalid")) "google-self-outro" "outro@example.invalid" "Outro" repeatDirect) :: IO (Either AuthFailure Account)
  check "link direto continua de uso unico" (reusedDirect == Left InviteInvalid)
  csrfEnrollment <- runSession (srequest (SRequest (enrollmentRequest { requestHeaders=[] }) enrollmentBody)) application
  check "cadastro publico exige origem e cabecalho" (simpleStatus csrfEnrollment == status403)
  intermediateInvite <- newToken
  createDirectInvite database first intermediateInvite
  intermediateTicket <- newToken
  beforeIntermediate <- studentsForCoach database first
  beginStudentSignup database (hashToken intermediateInvite) "google-intermediario" "verificado@example.invalid" intermediateTicket
  pendingDetails <- pendingStudentSignup database intermediateTicket
  check "Google libera somente etapa do nome" (isJust pendingDetails)
  afterGoogle <- studentsForCoach database first
  check "Google sozinho ainda nao cria aluno" (length beforeIntermediate == length afterGoogle)
  noPlatform <- findAccount database intermediateTicket
  check "ticket intermediario nao e sessao da plataforma" (isNothing noPlatform)
  let intermediateCookie = "ps_student_signup=" <> encodeUtf8 intermediateTicket
      nameRequest = (get "/api/auth/cadastro-aluno") { requestMethod="POST",requestHeaders=[("Cookie",intermediateCookie),("Origin","http://localhost:5173"),("X-Power-System-Request","1"),("Content-Type","application/json")] }
  pendingResponse <- send application (get "/api/auth/cadastro-aluno") { requestHeaders=[("Cookie",intermediateCookie)] }
  check "tela intermediaria autenticada disponivel" (simpleStatus pendingResponse == status200)
  check "tela intermediaria nao expoe dados Google" (not ("verificado@example.invalid" `BS.isInfixOf` LBS.toStrict (simpleBody pendingResponse)))
  unauthenticatedName <- send application (get "/api/auth/cadastro-aluno")
  check "tela do nome exige autenticar Google antes" (simpleStatus unauthenticatedName == status401)
  invalidName <- runSession (srequest (SRequest nameRequest (encode (object ["nome" .= ("   " :: Text.Text)])))) application
  check "nome obrigatorio antes de concluir" (simpleStatus invalidName == status400)
  longName <- runSession (srequest (SRequest nameRequest (encode (object ["nome" .= Text.replicate 121 "x"])))) application
  check "cadastro recusa nome acima do limite do perfil" (simpleStatus longName == status400)
  nameStillPending <- pendingStudentSignup database intermediateTicket
  check "erro no nome preserva etapa intermediaria" (isJust nameStillPending)
  nameCsrf <- runSession (srequest (SRequest (nameRequest {requestHeaders=[("Cookie",intermediateCookie)]}) (encode (object ["nome" .= ("Nome" :: Text.Text)])))) application
  check "confirmacao exige protecao CSRF" (simpleStatus nameCsrf == status403)
  confirmResponse <- runSession (srequest (SRequest nameRequest (encode (object ["nome" .= ("Nome confirmado" :: Text.Text),"email" .= ("forjado@example.invalid" :: Text.Text),"google_sub" .= ("forjado" :: Text.Text),"treinador_id" .= accountId second])))) application
  check "nome confirmado libera plataforma" (simpleStatus confirmResponse == status200)
  let platformCookies = [value | (key,value) <- simpleHeaders confirmResponse,key=="Set-Cookie","ps_session=" `BS.isPrefixOf` value]
  platformCookieHeader <- case platformCookies of
    [value] -> pure value
    _ -> die "FALHOU: sessao criada somente apos confirmar"
  check "sessao criada somente apos confirmar" ("HttpOnly" `BS.isInfixOf` platformCookieHeader)
  let platformCookie = BS.takeWhile (/=59) platformCookieHeader
  finalProfile <- send application (get "/api/auth/me") { requestHeaders=[("Cookie",platformCookie)] }
  check "confirmacao usa email Google e treinador do convite" (simpleStatus finalProfile==status200 && "verificado@example.invalid" `BS.isInfixOf` LBS.toStrict (simpleBody finalProfile) && "Nome confirmado" `BS.isInfixOf` LBS.toStrict (simpleBody finalProfile) && not ("forjado@example.invalid" `BS.isInfixOf` LBS.toStrict (simpleBody finalProfile)))
  consumedName <- runSession (srequest (SRequest nameRequest (encode (object ["nome" .= ("Outro nome" :: Text.Text)])))) application
  check "confirmacao do nome e de uso unico" (simpleStatus consumedName==status401)
  afterName <- studentsForCoach database first
  check "aluno aparece apenas apos nome confirmado" (length afterName==length beforeIntermediate+1)
  boundaryInvite <- newToken
  createDirectInvite database first boundaryInvite
  boundaryTicket <- newToken
  beginStudentSignup database (hashToken boundaryInvite) "google-name-boundary" "name-boundary@example.invalid" boundaryTicket
  boundarySession <- newToken
  boundaryAccount <- confirmStudentSignupWithWeight database boundaryTicket (Text.replicate 120 "x") boundarySession Nothing
  check "cadastro aceita nome de 120 caracteres sem peso opcional" (Text.length (accountName boundaryAccount)==120)
  expiredSignupInvite <- newToken
  createDirectInvite database first expiredSignupInvite
  expiredSignupTicket <- newToken
  beginStudentSignup database (hashToken expiredSignupInvite) "google-expirado" "expirado@example.invalid" expiredSignupTicket
  withDatabase database $ \connection -> void $ execute connection "UPDATE cadastros_alunos_pendentes SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE token_hash=?" (Only (hashToken expiredSignupTicket))
  expiredSessionToken <- newToken
  expiredSignup <- try (confirmStudentSignup database expiredSignupTicket "Nome" expiredSessionToken) :: IO (Either AuthFailure Account)
  check "etapa de nome expirada nao cria sessao" (expiredSignup==Left SignupExpired)
  revokedSignupTicket <- newToken
  beginStudentSignup database (hashToken expiredSignupInvite) "google-revogado" "revogado@example.invalid" revokedSignupTicket
  withDatabase database $ \connection -> void $ execute connection "UPDATE convites_alunos SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE token_hash=?" (Only (hashToken expiredSignupInvite))
  revokedSessionToken <- newToken
  revokedSignup <- try (confirmStudentSignup database revokedSignupTicket "Nome" revokedSessionToken) :: IO (Either AuthFailure Account)
  check "convite e revalidado ao confirmar nome" (revokedSignup==Left InviteInvalid)
  checkTraining database application first second firstToken secondToken studentToken
  unsafeLogout <- send application (signed "/api/auth/logout") { requestMethod = "POST" }
  check "logout exige protecao CSRF" (simpleStatus unsafeLogout == status403)
  wrongOrigin <- send application (get "/api/auth/logout")
    { requestMethod = "POST", requestHeaders = [("Cookie", cookie), ("Origin", "https://outro.example"), ("X-Power-System-Request", "1")] }
  check "logout recusa origem externa" (simpleStatus wrongOrigin == status403)
  getLogout <- send application (signed "/api/auth/logout")
  check "logout nao aceita GET" (simpleStatus getLogout == status405)
  logoutInvite <- newToken
  createDirectInvite database first logoutInvite
  logoutPending <- newToken
  beginStudentSignup database (hashToken logoutInvite) "google-cancelado" "cancelado@example.invalid" logoutPending
  logout <- send application (get "/api/auth/logout")
    { requestMethod = "POST", requestHeaders = [("Cookie", cookie <> "; ps_student_signup=" <> encodeUtf8 logoutPending), ("Origin", "http://localhost:5173"), ("X-Power-System-Request", "1")] }
  check "logout invalida sessao e cookie" (simpleStatus logout == status204 && "Max-Age=0" `BS.isInfixOf` header "Set-Cookie" logout)
  cancelledPending <- pendingStudentSignup database logoutPending
  check "logout cancela cadastro intermediario" (isNothing cancelledPending)
  loggedOut <- send application (signed "/api/auth/me")
  check "cookie antigo nao reutilizavel" (simpleStatus loggedOut == status401)
  withDatabase database $ \connection -> void $ execute connection "UPDATE sessoes SET expires_at = CURRENT_TIMESTAMP - INTERVAL '1 minute' WHERE token_hash = ?" (Only (hashToken repeatToken))
  expired <- findAccount database repeatToken
  check "sessao expirada recusada" (isNothing expired)
  setEnv "APP_BASE_URL" "https://power-system.example"
  secureContext <- newAuthContext (Just database)
  let secureApplication = authMiddleware secureContext (\_ respond -> respond (responseLBS status200 [] ""))
  secureStart <- send secureApplication (get "/api/auth/google")
  check "HTTPS usa cookie Secure" ("; Secure" `BS.isSuffixOf` header "Set-Cookie" secureStart && "__Secure-ps_oauth_state=" `BS.isPrefixOf` header "Set-Cookie" secureStart)
  putStrLn "OK: dois perfis, migracao, convites, vinculo por email, uso unico, permissoes, sessao e logout. Nenhuma chamada ao Google foi simulada como login real."
  where
    contains needle haystack = Text.pack needle `Text.isInfixOf` Text.pack haystack
