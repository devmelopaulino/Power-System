{-# LANGUAGE OverloadedStrings #-}

module Auth.Store
  ( Account (..), Student (..), InviteSummary, AuthFailure (..), Enrollment (..)
  , newToken, hashToken, challengeFor, saveOAuthRequest, saveEnrollmentRequest, consumeOAuthRequest
  , completeLogin, completeLoginWithEnrollment, createCoachSession, findAccount, removeSession, studentsForCoach
  , inviteSummary, createStudent, renewInvite, createDirectInvite, validateEnrollment
  , beginStudentSignup, pendingStudentSignup, confirmStudentSignup, confirmStudentSignupWithWeight, cancelStudentSignup
  ) where

import App.Time (appToday)
import Training.WeightStore (writeWeight)
import Control.Exception (Exception, throwIO)
import Control.Monad (unless, void, when)
import Crypto.Hash (Digest, SHA256, hash)
import Crypto.Random (getRandomBytes)
import Data.Aeson (ToJSON (..), object, (.=))
import qualified Data.ByteString as BS
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16, Base64URLUnpadded), convertToBase)
import Data.Int (Int64)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Database.Connection (Database, withDatabase, withDatabaseTransaction)
import Database.PostgreSQL.Simple (Connection, Only (..), execute, execute_, query)
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)

data Account = Account
  { accountSubject :: Text, accountRole :: Text, accountId :: Int64
  , accountName :: Text, accountEmail :: Text, accountCoachId :: Maybe Int64
  , accountCoachName :: Maybe Text
  } deriving (Eq, Show)
instance FromRow Account where
  fromRow = Account <$> field <*> field <*> field <*> field <*> field <*> field <*> field
instance ToJSON Account where
  toJSON account = object
    [ "id" .= accountId account, "perfil" .= accountRole account
    , "nome" .= accountName account, "email" .= accountEmail account
    , "treinadorId" .= accountCoachId account, "treinadorNome" .= accountCoachName account ]

data Student = Student Int64 Text (Maybe Text) Bool deriving (Eq, Show)
instance FromRow Student where
  fromRow = Student <$> field <*> field <*> field <*> field
instance ToJSON Student where
  toJSON (Student identifier name email active) = object
    ["id" .= identifier, "nome" .= name, "email" .= email, "acessoAtivo" .= active]

newtype InviteSummary = InviteSummary Text
instance FromRow InviteSummary where fromRow = InviteSummary <$> field
instance ToJSON InviteSummary where toJSON (InviteSummary coach) = object ["treinador" .= coach]

data AuthFailure = SessionConflict | ExecutedIdentityLocked | RegistrationRequired | InviteInvalid | InviteEmailMismatch | AccountRoleConflict
  | PermissionDenied | StudentNotFound | StudentAlreadyActive | InvalidStudent | InvalidStudentName | SignupExpired
  deriving (Eq, Show)
instance Exception AuthFailure

data Enrollment = Enrollment Text Text deriving (Eq, Show)

validateEnrollment :: Text -> Text -> IO Enrollment
validateEnrollment rawName rawEmail = do
  let name = Text.strip rawName; email = Text.toLower (Text.strip rawEmail)
  unless (validStudent name email) (throwIO InvalidStudent)
  pure (Enrollment name email)

sha256 :: BS.ByteString -> BS.ByteString
sha256 bytes = convert (hash bytes :: Digest SHA256)
newToken :: IO Text
newToken = decodeUtf8 . convertToBase Base64URLUnpadded <$> (getRandomBytes 32 :: IO BS.ByteString)
hashToken :: Text -> Text
hashToken = decodeUtf8 . convertToBase Base16 . sha256 . encodeUtf8
challengeFor :: Text -> Text
challengeFor = decodeUtf8 . convertToBase Base64URLUnpadded . sha256 . encodeUtf8

saveOAuthRequest :: Database -> Text -> Text -> Maybe Text -> Bool -> IO ()
saveOAuthRequest database state verifier invite registering = saveEnrollmentRequest database state verifier invite registering Nothing

saveEnrollmentRequest :: Database -> Text -> Text -> Maybe Text -> Bool -> Maybe Enrollment -> IO ()
saveEnrollmentRequest database state verifier invite registering enrollment = withDatabaseTransaction database $ \connection -> do
  void $ execute_ connection "DELETE FROM oauth_requests WHERE expires_at <= CURRENT_TIMESTAMP"
  let (name,email) = case enrollment of Just (Enrollment n e) -> (Just n,Just e); Nothing -> (Nothing,Nothing)
  void $ execute connection "INSERT INTO oauth_requests (state_hash, code_verifier, convite_hash, cadastro_treinador, nome_aluno, email_aluno) VALUES (?, ?, ?, ?, ?, ?)"
    (hashToken state, verifier, invite, registering,name,email)
consumeOAuthRequest :: Database -> Text -> IO (Maybe (Text, Maybe Text, Bool, Maybe Enrollment))
consumeOAuthRequest database state = withDatabase database $ \connection -> do
  rows <- query connection "DELETE FROM oauth_requests WHERE state_hash = ? AND expires_at > CURRENT_TIMESTAMP RETURNING code_verifier, convite_hash, cadastro_treinador, nome_aluno, email_aluno"
    (Only (hashToken state)) :: IO [(Text,Maybe Text,Bool,Maybe Text,Maybe Text)]
  pure $ case rows of
    [(verifier,invite,registering,name,email)] -> Just (verifier,invite,registering,Enrollment <$> name <*> email)
    _ -> Nothing

accountBySubject :: Connection -> Text -> IO (Maybe Account)
accountBySubject connection subject = do
  rows <- query connection
    "SELECT c.google_sub, c.perfil, COALESCE(t.id,a.id), COALESCE(t.nome,a.nome), COALESCE(t.email,a.email), a.treinador_id, dono.nome FROM contas c LEFT JOIN treinadores t ON t.id=c.treinador_id LEFT JOIN alunos a ON a.id=c.aluno_id LEFT JOIN treinadores dono ON dono.id=a.treinador_id WHERE c.google_sub=?"
    (Only subject)
  pure $ case rows of [account] -> Just account; _ -> Nothing

-- A intencao de cadastro e o convite vem da tentativa OAuth no banco, nunca do callback.
completeLogin :: Database -> Bool -> Maybe Text -> Text -> Text -> Text -> Text -> IO Account
completeLogin database registering invite = completeLoginWithEnrollment database registering invite Nothing

completeLoginWithEnrollment :: Database -> Bool -> Maybe Text -> Maybe Enrollment -> Text -> Text -> Text -> Text -> IO Account
completeLoginWithEnrollment database registering invite enrollment subject email name token =
  withDatabaseTransaction database $ \connection ->
    completeLoginOn connection registering invite enrollment subject email name token

completeLoginOn :: Connection -> Bool -> Maybe Text -> Maybe Enrollment -> Text -> Text -> Text -> Text -> IO Account
completeLoginOn connection registering invite enrollment subject email name token = do
  validatedEnrollment <- case enrollment of
    Nothing -> pure Nothing
    Just (Enrollment enteredName enteredEmail) -> do
      validated@(Enrollment _ normalizedEmail) <- validateEnrollment enteredName enteredEmail
      unless (normalizedEmail == Text.toLower (Text.strip email)) (throwIO InviteEmailMismatch)
      pure (Just validated)
  void (query connection "SELECT 1 FROM pg_advisory_xact_lock(hashtextextended(?, 0))" (Only subject) :: IO [Only Int])
  existing <- accountBySubject connection subject
  case existing of
    Just account -> do
      when (isJust invite) (throwIO AccountRoleConflict)
      if accountRole account == "treinador"
        then void $ execute connection "UPDATE treinadores SET nome=?, email=? WHERE id=?" (name, email, accountId account)
        else void $ execute connection "UPDATE alunos SET email=? WHERE id=?" (email, accountId account)
    Nothing -> case invite of
      Just inviteHash -> do
        invitations <- query connection
          "SELECT aluno_id,treinador_id FROM convites_alunos WHERE token_hash=? AND accepted_at IS NULL AND expires_at>CURRENT_TIMESTAMP FOR UPDATE"
          (Only inviteHash) :: IO [(Maybe Int64,Int64)]
        case invitations of
          [(linkedStudent,coachId)] -> do
            studentId <- case linkedStudent of
              Nothing -> case validatedEnrollment of
                Just (Enrollment studentName studentEmail) -> do
                  validated <- validateEnrollment studentName studentEmail
                  let Enrollment validatedName validatedEmail = validated
                  unless (validatedEmail == Text.toLower (Text.strip email)) (throwIO InviteEmailMismatch)
                  prior <- query connection "SELECT id FROM alunos WHERE treinador_id=? AND lower(btrim(email))=? FOR UPDATE"
                    (coachId,validatedEmail) :: IO [Only Int64]
                  case prior of
                    [Only identifier] -> do
                      linked <- query connection "SELECT EXISTS(SELECT 1 FROM contas WHERE aluno_id=?)" (Only identifier) :: IO [Only Bool]
                      when (linked == [Only True]) (throwIO AccountRoleConflict)
                      void $ execute connection "UPDATE alunos SET nome=?,email=? WHERE id=?" (validatedName,validatedEmail,identifier)
                      pure identifier
                    [] -> do
                      ids <- query connection "INSERT INTO alunos (treinador_id,nome,email) VALUES (?,?,?) RETURNING id"
                        (coachId,validatedName,validatedEmail) :: IO [Only Int64]
                      case ids of [Only identifier] -> pure identifier; _ -> throwIO InvalidStudent
                    _ -> throwIO InvalidStudent
                Nothing -> throwIO InvalidStudent
              Just identifier -> do
                linked <- query connection "SELECT email FROM alunos WHERE id=? AND treinador_id=?" (identifier,coachId) :: IO [Only (Maybe Text)]
                case linked of
                  [Only (Just invitedEmail)] -> unless (Text.toCaseFold (Text.strip invitedEmail) == Text.toCaseFold (Text.strip email)) (throwIO InviteEmailMismatch)
                  _ -> throwIO InviteInvalid
                case validatedEnrollment of
                  Just (Enrollment enteredName enteredEmail) -> void $ execute connection "UPDATE alunos SET nome=?,email=? WHERE id=?" (enteredName,enteredEmail,identifier)
                  Nothing -> pure ()
                pure identifier
            void $ execute connection "INSERT INTO contas (google_sub,perfil,aluno_id) VALUES (?,'aluno',?)" (subject, studentId)
            void $ execute connection "UPDATE convites_alunos SET aluno_id=?,accepted_at=CURRENT_TIMESTAMP WHERE token_hash=?" (studentId,inviteHash)
          _ -> throwIO InviteInvalid
      Nothing | registering -> do
        identifiers <- query connection "INSERT INTO treinadores (nome,email) VALUES (?,?) RETURNING id" (name,email) :: IO [Only Int64]
        case identifiers of
          [Only identifier] -> void $ execute connection "INSERT INTO contas (google_sub,perfil,treinador_id) VALUES (?,'treinador',?)" (subject,identifier)
          _ -> ioError (userError "Falha ao cadastrar treinador.")
      Nothing -> throwIO RegistrationRequired
  current <- accountBySubject connection subject
  case current of
    Nothing -> ioError (userError "Conta indisponivel.")
    Just account -> do
      void $ execute_ connection "DELETE FROM sessoes WHERE expires_at<=CURRENT_TIMESTAMP"
      void $ execute connection "INSERT INTO sessoes (token_hash,conta_sub) VALUES (?,?)" (hashToken token,subject)
      pure account

-- Google ja foi validado pelo servidor, mas nenhum aluno ou acesso e criado
-- ate a confirmacao do nome. O ticket so serve para esta etapa intermediaria.
beginStudentSignup :: Database -> Text -> Text -> Text -> Text -> IO ()
beginStudentSignup database inviteHash subject email ticket = withDatabaseTransaction database $ \connection -> do
  existing <- accountBySubject connection subject
  when (isJust existing) (throwIO AccountRoleConflict)
  invitations <- query connection
    "SELECT a.email FROM convites_alunos i LEFT JOIN alunos a ON a.id=i.aluno_id WHERE i.token_hash=? AND i.accepted_at IS NULL AND i.expires_at>CURRENT_TIMESTAMP"
    (Only inviteHash) :: IO [Only (Maybe Text)]
  case invitations of
    [Only (Just expected)] -> unless (Text.toCaseFold (Text.strip expected) == Text.toCaseFold (Text.strip email)) (throwIO InviteEmailMismatch)
    [Only Nothing] -> pure ()
    _ -> throwIO InviteInvalid
  void $ execute_ connection "DELETE FROM cadastros_alunos_pendentes WHERE expires_at<=CURRENT_TIMESTAMP"
  void $ execute connection
    "INSERT INTO cadastros_alunos_pendentes (token_hash,convite_hash,google_sub,email_google) VALUES (?,?,?,?)"
    (hashToken ticket,inviteHash,subject,Text.toLower (Text.strip email))

pendingStudentSignup :: Database -> Text -> IO (Maybe InviteSummary)
pendingStudentSignup database ticket = withDatabase database $ \connection -> do
  rows <- query connection
    "SELECT t.nome FROM cadastros_alunos_pendentes p JOIN convites_alunos i ON i.token_hash=p.convite_hash JOIN treinadores t ON t.id=i.treinador_id WHERE p.token_hash=? AND p.expires_at>CURRENT_TIMESTAMP AND i.accepted_at IS NULL AND i.expires_at>CURRENT_TIMESTAMP AND NOT EXISTS(SELECT 1 FROM contas c WHERE c.google_sub=p.google_sub)"
    (Only (hashToken ticket))
  pure $ case rows of [summary] -> Just summary; _ -> Nothing

confirmStudentSignup :: Database -> Text -> Text -> Text -> IO Account
confirmStudentSignup database ticket rawName sessionToken = confirmStudentSignupWithWeight database ticket rawName sessionToken Nothing
confirmStudentSignupWithWeight :: Database -> Text -> Text -> Text -> Maybe Double -> IO Account
confirmStudentSignupWithWeight database ticket rawName sessionToken weight = withDatabaseTransaction database $ \connection -> do
  unless (maybe True (\n -> not (isNaN n || isInfinite n) && n>=1 && n<=500) weight) (throwIO InvalidStudent)
  let name = Text.strip rawName
  rows <- query connection
    "SELECT convite_hash,google_sub,email_google FROM cadastros_alunos_pendentes WHERE token_hash=? AND expires_at>CURRENT_TIMESTAMP FOR UPDATE"
    (Only (hashToken ticket)) :: IO [(Text,Text,Text)]
  case rows of
    [(inviteHash,subject,email)] -> do
      unless (not (Text.null name) && Text.length name<=120 && not (Text.any (`elem` ['\r','\n','\0']) name)) (throwIO InvalidStudentName)
      account <- completeLoginOn connection False (Just inviteHash) (Just (Enrollment name email)) subject email name sessionToken
      case weight of
        Just measured -> do
          today <- appToday
          writeWeight connection (accountId account) today measured "onboarding"
        Nothing -> pure ()
      void $ execute connection "DELETE FROM cadastros_alunos_pendentes WHERE token_hash=?" (Only (hashToken ticket))
      pure account
    _ -> throwIO SignupExpired

cancelStudentSignup :: Database -> Text -> IO ()
cancelStudentSignup database ticket = withDatabase database $ \connection ->
  void $ execute connection "DELETE FROM cadastros_alunos_pendentes WHERE token_hash=?" (Only (hashToken ticket))

-- Auxiliar dos testes: cadastro explicito de treinador, sem rota publica de simulacao.
createCoachSession :: Database -> Text -> Text -> Text -> Text -> IO Account
createCoachSession database = completeLogin database True Nothing

findAccount :: Database -> Text -> IO (Maybe Account)
findAccount database token = withDatabase database $ \connection -> do
  rows <- query connection
    "SELECT c.google_sub,c.perfil,COALESCE(t.id,a.id),COALESCE(t.nome,a.nome),COALESCE(t.email,a.email),a.treinador_id,dono.nome FROM sessoes s JOIN contas c ON c.google_sub=s.conta_sub LEFT JOIN treinadores t ON t.id=c.treinador_id LEFT JOIN alunos a ON a.id=c.aluno_id LEFT JOIN treinadores dono ON dono.id=a.treinador_id WHERE s.token_hash=? AND s.expires_at>CURRENT_TIMESTAMP"
    (Only (hashToken token))
  pure $ case rows of [account] -> Just account; _ -> Nothing
removeSession :: Database -> Text -> IO ()
removeSession database token = withDatabase database $ \connection -> void $ execute connection "DELETE FROM sessoes WHERE token_hash=?" (Only (hashToken token))

requireCoach :: Account -> IO ()
requireCoach account = unless (accountRole account == "treinador") (throwIO PermissionDenied)

studentsForCoach :: Database -> Account -> IO [Student]
studentsForCoach database account = do
  requireCoach account
  withDatabase database $ \connection -> query connection
    "SELECT a.id,a.nome,a.email,EXISTS(SELECT 1 FROM contas c WHERE c.aluno_id=a.id) FROM alunos a WHERE a.treinador_id=? ORDER BY lower(a.nome),a.id"
    (Only (accountId account))

inviteSummary :: Database -> Text -> IO (Maybe InviteSummary)
inviteSummary database tokenHash = withDatabase database $ \connection -> do
  rows <- query connection
    "SELECT t.nome FROM convites_alunos i JOIN treinadores t ON t.id=i.treinador_id WHERE i.token_hash=? AND i.accepted_at IS NULL AND i.expires_at>CURRENT_TIMESTAMP AND NOT EXISTS(SELECT 1 FROM contas c WHERE c.aluno_id=i.aluno_id)"
    (Only tokenHash)
  pure $ case rows of [summary] -> Just summary; _ -> Nothing

createDirectInvite :: Database -> Account -> Text -> IO ()
createDirectInvite database account token = do
  requireCoach account
  withDatabase database $ \connection ->
    void $ execute connection "INSERT INTO convites_alunos (token_hash,treinador_id) VALUES (?,?)" (hashToken token,accountId account)

validStudent :: Text -> Text -> Bool
validStudent name email = not (Text.null name) && Text.length name <= 120 && Text.length email <= 320
  && not (Text.any (`elem` ['\r','\n',' ']) email) && case Text.splitOn "@" email of
    [local,domain] -> not (Text.null local) && not (Text.null domain)
    _ -> False

createStudent :: Database -> Account -> Text -> Text -> Text -> IO Student
createStudent database account rawName rawEmail token = do
  requireCoach account
  let name = Text.strip rawName; email = Text.toLower (Text.strip rawEmail)
  unless (validStudent name email) (throwIO InvalidStudent)
  withDatabaseTransaction database $ \connection -> do
    rows <- query connection "INSERT INTO alunos (treinador_id,nome,email) VALUES (?,?,?) RETURNING id,nome,email,FALSE" (accountId account,name,email)
    case rows of
      [student@(Student identifier _ _ _)] -> do
        void $ execute connection "INSERT INTO convites_alunos (token_hash,aluno_id,treinador_id) VALUES (?,?,?)" (hashToken token,identifier,accountId account)
        pure student
      _ -> ioError (userError "Falha ao cadastrar aluno.")

renewInvite :: Database -> Account -> Int64 -> Text -> IO ()
renewInvite database account identifier token = do
  requireCoach account
  withDatabaseTransaction database $ \connection -> do
    void (query connection "SELECT 1 FROM convites_alunos i JOIN alunos a ON a.id=i.aluno_id WHERE a.id=? AND a.treinador_id=? FOR UPDATE OF i"
      (identifier,accountId account) :: IO [Only Int])
    rows <- query connection "SELECT email FROM alunos WHERE id=? AND treinador_id=? FOR UPDATE"
      (identifier,accountId account) :: IO [Only (Maybe Text)]
    case rows of
      [Only (Just email)] | validStudent "Aluno" email -> do
        active <- query connection "SELECT EXISTS(SELECT 1 FROM contas WHERE aluno_id=?)" (Only identifier) :: IO [Only Bool]
        when (active == [Only True]) (throwIO StudentAlreadyActive)
        void $ execute connection
          "INSERT INTO convites_alunos (token_hash,aluno_id,treinador_id) VALUES (?,?,?) ON CONFLICT (aluno_id) DO UPDATE SET token_hash=EXCLUDED.token_hash,expires_at=CURRENT_TIMESTAMP+INTERVAL '7 days',accepted_at=NULL,criado_em=CURRENT_TIMESTAMP"
          (hashToken token,identifier,accountId account)
      [Only _] -> throwIO InvalidStudent
      _ -> throwIO StudentNotFound
