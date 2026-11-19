{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module API.Routes (API, app) where

import Data.Text (Text)
import Network.Wai (Application)
import Servant (Get, PlainText, Proxy (..), serve, (:>))

type API = "hello" :> Get '[PlainText] Text

app :: Application
app = serve (Proxy :: Proxy API) (pure "Hello World")
