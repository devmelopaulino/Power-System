module Main (main) where

import Database.Connection (initializeDatabase)
import System.Exit (die)

main :: IO ()
main = do
  database <- initializeDatabase
  case database of
    Nothing -> die "Configure DATABASE_URL para preparar o banco."
    Just _ -> putStrLn "Banco preparado."
