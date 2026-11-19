{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module API.Routes (API, app) where

import Data.Text (Text)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value, encode, object, (.=))
import Database.Connection (Database, databaseHealthy)
import Network.Wai (Application)
import Servant
  ( Get, Handler, JSON, PlainText, Proxy (..), Raw, err503, errBody, errHeaders
  , serve, serveDirectoryFileServer, throwError
  , (:<|>) (..), (:>)
  )

type HelloAPI = Get '[PlainText] Text

type API = "api" :> "hello" :> HelloAPI
      :<|> "hello" :> HelloAPI
      :<|> "api" :> "health" :> Get '[JSON] Value
      :<|> Raw

app :: Maybe Database -> FilePath -> Application
app database staticDirectory = serve (Proxy :: Proxy API)
  (pure ("Hello World" :: Text)
    :<|> pure ("Hello World" :: Text)
    :<|> healthHandler database
    :<|> serveDirectoryFileServer staticDirectory)

healthHandler :: Maybe Database -> Handler Value
healthHandler database = do
  connected <- maybe (pure False) (liftIO . databaseHealthy) database
  let response = object
        [ "status" .= (if connected then "ok" else "unavailable" :: Text)
        , "database" .= (case database of
            Nothing -> "not_configured"
            Just _ -> if connected then "connected" else "unavailable" :: Text)
        ]
  if connected then pure response
    else throwError err503
      { errBody = encode response, errHeaders = [("Content-Type", "application/json")] }
