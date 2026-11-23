{-# LANGUAGE OverloadedStrings #-}
module API.ReliableWrite (protectedWrite, reliableWrite) where
import Auth.Store (Account(..))
import Control.Exception (Exception,throwIO,catch)
import Control.Monad (void)
import Crypto.Hash (Digest,SHA256,hash)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.ByteString.Builder (toLazyByteString)
import Data.IORef
import Data.Text (Text)
import qualified Data.Text as T
import Database.Connection
import Database.PostgreSQL.Simple
import Network.HTTP.Types
import Network.Wai

protectedWrite :: Request -> Bool
protectedWrite request = requestMethod request=="POST" && case pathInfo request of
 ["api","auth",name] -> name `elem` ["pesagens","perfil"]
 ["api","auth","treinos",_] -> True
 ["api","alunos",_,name] -> name `elem` ["treinos","perfil","dados-atleta"]
 ["api","alunos",_,"pesagens",_,action] -> action `elem` ["editar","excluir"]
 ["api","alunos",_,"treinos",_,action] -> action `elem` ["recuperar","cancelar","anular"]
 _ -> False

data RollbackResponse = RollbackResponse Response
instance Show RollbackResponse where show _="Mutation rejected"
instance Exception RollbackResponse

reliableWrite :: Database -> Account -> Text -> Text -> LBS.ByteString -> (Database -> IO Response) -> IO Response
reliableWrite database account key path payload action = (withDatabaseTransaction database $ \connection -> do
 let digest=T.pack(show(hash(LBS.toStrict payload)::Digest SHA256))
 void(query connection "SELECT 1 FROM pg_advisory_xact_lock(hashtextextended(?,0))" (Only(accountSubject account<>":"<>key))::IO[Only Int])
 receipts <- query connection "SELECT caminho,fingerprint,status,resposta FROM operacoes_gravacao WHERE autor_sub=? AND chave=?" (accountSubject account,key)::IO[(Text,Text,Int,BS.ByteString)]
 case receipts of
  [(savedPath,savedDigest,code,body)] | savedPath==path && savedDigest==digest -> pure(responseLBS(mkStatus code "") [("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Idempotency-Replayed","true")] (LBS.fromStrict body))
  [_] -> pure(responseLBS status409 [("Content-Type","application/json"),("Cache-Control","no-store")] "{\"erro\":\"Este identificador ja foi utilizado para outros dados. Confirme a tentativa anterior antes de iniciar outra.\"}")
  _ -> do
   response <- action(transactionDatabase connection)
   let (status,_,withBody)=responseToStream response
   if statusCode status<200 || statusCode status>=300 then throwIO(RollbackResponse response) else do
    body <- withBody $ \stream -> do
     chunks <- newIORef []
     stream (\builder -> modifyIORef' chunks (toLazyByteString builder:)) (pure())
     LBS.concat . reverse <$> readIORef chunks
    void $ execute connection "INSERT INTO operacoes_gravacao(autor_sub,chave,caminho,fingerprint,status,resposta) VALUES (?,?,?,?,?,?)" (accountSubject account,key,path,digest,statusCode status,LBS.toStrict body)
    pure(responseLBS status [("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")] body)
 ) `catch` (\(RollbackResponse response)->pure response)
