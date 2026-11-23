{-# LANGUAGE OverloadedStrings #-}

module Database.Connection
  ( Database, initializeDatabase, withDatabase, withDatabaseTransaction, transactionDatabase, databaseHealthy ) where

import Control.Concurrent (threadDelay)
import Control.Exception (AsyncException, SomeException, bracket, fromException, tryJust)
import Control.Monad (unless, void)
import qualified Data.ByteString as BS
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Database.PostgreSQL.Simple
  ( Connection, Only (..), close, connectPostgreSQL, execute, execute_
  , query_, withTransaction )
import Database.PostgreSQL.Simple.Types (Query (..))
import System.Environment (lookupEnv)
import System.Exit (die)

-- Sem Show para evitar que a URL com senha apareça nos logs.
data Database = Database BS.ByteString | TransactionDatabase Connection

trySynchronous :: IO a -> IO (Either SomeException a)
trySynchronous = tryJust synchronous
  where
    synchronous err = case fromException err :: Maybe AsyncException of
      Just _ -> Nothing
      Nothing -> Just err

withDatabase :: Database -> (Connection -> IO a) -> IO a
withDatabase (Database connectionString) = bracket (connectPostgreSQL connectionString) close
withDatabase (TransactionDatabase connection) = (\action -> action connection)

withDatabaseTransaction :: Database -> (Connection -> IO a) -> IO a
withDatabaseTransaction (TransactionDatabase connection) action = action connection
withDatabaseTransaction database action = withDatabase database (\connection -> withTransaction connection (action connection))

transactionDatabase :: Connection -> Database
transactionDatabase = TransactionDatabase

initializeDatabase :: IO (Maybe Database)
initializeDatabase = do
  configuredUrl <- lookupEnv "DATABASE_URL"
  railwayEnvironment <- lookupEnv "RAILWAY_ENVIRONMENT_ID"
  case configuredUrl of
    Nothing -> case railwayEnvironment of
      Just _ -> die "DATABASE_URL precisa estar configurada no Railway."
      Nothing -> do
        putStrLn "Banco nao configurado: apenas a pagina e as rotas Hello World estao disponiveis."
        pure Nothing
    Just "" -> die "DATABASE_URL nao pode estar vazia."
    Just url -> do
      let separator = if '?' `elem` url then "&" else "?"
          database = Database (encodeUtf8 (Text.pack (url ++ separator ++ "connect_timeout=5")))
      awaitDatabase database (15 :: Int)
      migrationDirectory <- fromMaybe "migrations" <$> lookupEnv "MIGRATIONS_DIR"
      migrated <- trySynchronous (migrate database migrationDirectory)
      case migrated of
        Left _ -> die "Falha ao preparar as tabelas do banco. Verifique as migracoes e as permissoes do usuario."
        Right _ -> do
          putStrLn "PostgreSQL conectado. Migracoes aplicadas."
          pure (Just database)

awaitDatabase :: Database -> Int -> IO ()
awaitDatabase database remaining = do
  result <- trySynchronous (withDatabase database (\connection -> query_ connection "SELECT 1" :: IO [Only Int]))
  case result of
    Right [Only 1] -> pure ()
    _ | remaining > 1 -> do
          putStrLn "Aguardando PostgreSQL..."
          threadDelay 2000000
          awaitDatabase database (remaining - 1)
      | otherwise -> die "Nao foi possivel conectar ao PostgreSQL. Verifique DATABASE_URL e a disponibilidade do banco."

migrate :: Database -> FilePath -> IO ()
migrate database directory = withDatabase database $ \connection -> withTransaction connection $ do
  void $ execute_ connection "SET LOCAL statement_timeout = '30s'"
  void $ execute_ connection "SET LOCAL lock_timeout = '15s'"
  -- Serializa migracoes quando dois deployments iniciam ao mesmo tempo.
  void (query_ connection "SELECT 1 FROM pg_advisory_xact_lock(731946201)" :: IO [Only Int])
  void $ execute_ connection "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, aplicada_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP)"
  mapM_ (applyMigration connection)
    [(1, "001_initial.sql"), (2, "002_google_auth.sql"), (3, "003_student_accounts.sql"), (4, "004_self_registration.sql"), (5, "005_pending_student_signup.sql"), (6, "006_student_training.sql"), (7, "007_athlete_data.sql"), (8, "008_athlete_weight_analysis.sql"), (9, "009_session_integrity.sql"), (10, "010_session_history.sql"), (11, "011_reliable_writes.sql")]
  where
    applyMigration connection (version, filename) = do
      applied <- query_ connection "SELECT version FROM schema_migrations" :: IO [Only Int]
      unless (Only version `elem` applied) $ do
        script <- BS.readFile (directory ++ "/" ++ filename)
        void $ execute_ connection (Query script)
        void $ execute connection "INSERT INTO schema_migrations (version) VALUES (?)" (Only (version :: Int))

databaseHealthy :: Database -> IO Bool
databaseHealthy database = do
  result <- trySynchronous $ withDatabase database $ \connection -> do
    void $ execute_ connection "SET statement_timeout = '5s'"
    query_ connection "SELECT version FROM schema_migrations WHERE version IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11) ORDER BY version" :: IO [Only Int]
  pure $ case result of
    Right [Only 1, Only 2, Only 3, Only 4, Only 5, Only 6, Only 7, Only 8, Only 9, Only 10, Only 11] -> True
    _ -> False
