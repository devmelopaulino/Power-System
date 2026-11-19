module Main (main) where

import API.Routes (app)
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  configuredPort <- lookupEnv "PORT"
  port <- case configuredPort of
    Nothing -> pure 8080
    Just value -> case readMaybe value of
      Just number | number > 0 && number <= 65535 -> pure number
      _ -> ioError (userError "PORT deve ser um numero entre 1 e 65535.")
  putStrLn $ "Power System: http://localhost:" ++ show port ++ "/hello"
  run port app
