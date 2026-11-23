module Main (main) where

import API.Routes (app)
import API.Auth (newAuthContext)
import Data.Maybe (fromMaybe)
import Database.Connection (initializeDatabase)
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  staticDirectory <- fromMaybe "../frontend/dist" <$> lookupEnv "STATIC_DIR"
  configuredPort <- lookupEnv "PORT"
  port <- case configuredPort of
    Nothing -> pure 8080
    Just value -> case readMaybe value of
      Just number | number > 0 && number <= 65535 -> pure number
      _ -> ioError (userError "PORT deve ser um numero entre 1 e 65535.")
  database <- initializeDatabase
  auth <- newAuthContext database
  putStrLn $ "Power System: http://localhost:" ++ show port
  run port (app database auth staticDirectory)
