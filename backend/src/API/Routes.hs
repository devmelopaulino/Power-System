{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module API.Routes (API, app) where

import Data.Text (Text)
import Network.Wai (Application)
import Servant
  ( Get, PlainText, Proxy (..), Raw, serve, serveDirectoryFileServer
  , (:<|>) (..), (:>)
  )

type HelloAPI = Get '[PlainText] Text

type API = "api" :> "hello" :> HelloAPI
      :<|> "hello" :> HelloAPI
      :<|> Raw

app :: FilePath -> Application
app staticDirectory = serve (Proxy :: Proxy API)
  (pure ("Hello World" :: Text)
    :<|> pure ("Hello World" :: Text)
    :<|> serveDirectoryFileServer staticDirectory)
