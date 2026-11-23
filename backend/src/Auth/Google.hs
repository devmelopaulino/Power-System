{-# LANGUAGE OverloadedStrings #-}

module Auth.Google
  ( GoogleConfig (..), GoogleProfile (..), loadGoogleConfig, authorizationUrl, googleProfile ) where

import Auth.Store (challengeFor)
import Control.Monad (unless)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:), (.:?), (.!=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Client
  ( Manager, Request (..), Response, httpLbs, parseRequest, responseBody, responseStatus
  , responseTimeoutMicro, urlEncodedBody )
import Network.HTTP.Types (renderQuery, statusCode)
import Network.URI (URI (..), URIAuth (..), parseURI)
import System.Environment (lookupEnv)

-- Nao derive Show: o segredo nunca deve aparecer nos logs.
data GoogleConfig = GoogleConfig
  { googleClientId :: Text, googleClientSecret :: Text, appBaseUrl :: Text, secureCookies :: Bool }

data GoogleProfile = GoogleProfile { googleSubject :: Text, googleEmail :: Text, googleName :: Text }

data TokenResponse = TokenResponse Text Text
instance FromJSON TokenResponse where
  parseJSON = withObject "TokenResponse" $ \value -> TokenResponse <$> value .: "access_token" <*> value .: "token_type"

data UserInfo = UserInfo Text Text Bool Text
instance FromJSON UserInfo where
  parseJSON = withObject "UserInfo" $ \value -> UserInfo
    <$> value .: "sub" <*> value .: "email" <*> value .: "email_verified" <*> (value .:? "name" .!= "Treinador")

loadGoogleConfig :: IO (Maybe GoogleConfig)
loadGoogleConfig = do
  identifier <- lookupEnv "GOOGLE_CLIENT_ID"
  secret <- lookupEnv "GOOGLE_CLIENT_SECRET"
  configuredBase <- lookupEnv "APP_BASE_URL"
  railway <- lookupEnv "RAILWAY_ENVIRONMENT_ID"
  let base = Text.dropWhileEnd (== '/') (Text.pack (fromMaybe "http://localhost:5173" configuredBase))
      originAllowed = validOrigin base && (railway == Nothing || "https://" `Text.isPrefixOf` base)
  case (identifier, secret) of
    (Just client, Just clientSecret) | not (null client) && not (null clientSecret) && originAllowed ->
      pure $ Just (GoogleConfig (Text.pack client) (Text.pack clientSecret) base ("https://" `Text.isPrefixOf` base))
    _ -> do
      putStrLn "Acesso Google indisponivel: configure GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET e APP_BASE_URL."
      pure Nothing

validOrigin :: Text -> Bool
validOrigin value = case parseURI (Text.unpack value) of
  Just uri -> case uriAuthority uri of
    Just authority -> null (uriUserInfo authority) && not (null (uriRegName authority))
      && uriPath uri `elem` ["", "/"] && null (uriQuery uri) && null (uriFragment uri)
      && (uriScheme uri == "https:" || (uriScheme uri == "http:" && uriRegName authority `elem` ["localhost", "127.0.0.1"]))
    Nothing -> False
  Nothing -> False

redirectUri :: GoogleConfig -> Text
redirectUri config = appBaseUrl config <> "/api/auth/google/callback"

authorizationUrl :: GoogleConfig -> Text -> Text -> BS.ByteString
authorizationUrl config state verifier = "https://accounts.google.com/o/oauth2/v2/auth" <> renderQuery True
  [ ("client_id", Just (encodeUtf8 (googleClientId config)))
  , ("redirect_uri", Just (encodeUtf8 (redirectUri config)))
  , ("response_type", Just "code"), ("scope", Just "openid email profile")
  , ("state", Just (encodeUtf8 state)), ("code_challenge", Just (encodeUtf8 (challengeFor verifier)))
  , ("code_challenge_method", Just "S256"), ("prompt", Just "select_account")
  ]

requestJSON :: FromJSON a => Manager -> Request -> IO a
requestJSON manager request = do
  response <- httpLbs request { redirectCount = 0, responseTimeout = responseTimeoutMicro 10000000 } manager
  unless (statusCode (responseStatus response) == 200 && LBS.length (responseBody response) <= 65536) $
    ioError (userError "Resposta de autenticacao indisponivel.")
  decodeResponse response
  where
    decodeResponse :: FromJSON a => Response LBS.ByteString -> IO a
    decodeResponse response = case eitherDecode (responseBody response) of
      Left _ -> ioError (userError "Resposta de autenticacao invalida.")
      Right result -> pure result

-- O perfil vem diretamente do endpoint HTTPS do Google usando o token trocado
-- pelo codigo, client secret e PKCE. Nenhum nome/e-mail enviado pelo navegador e aceito.
googleProfile :: Manager -> GoogleConfig -> Text -> Text -> IO GoogleProfile
googleProfile manager config code verifier = do
  tokenRequest <- parseRequest "https://oauth2.googleapis.com/token"
  TokenResponse accessToken tokenType <- requestJSON manager $ urlEncodedBody
    [ ("code", encodeUtf8 code), ("client_id", encodeUtf8 (googleClientId config))
    , ("client_secret", encodeUtf8 (googleClientSecret config))
    , ("redirect_uri", encodeUtf8 (redirectUri config))
    , ("grant_type", "authorization_code"), ("code_verifier", encodeUtf8 verifier)
    ] tokenRequest
  unless (Text.toLower tokenType == "bearer" && not (Text.null accessToken)) $
    ioError (userError "Token de autenticacao invalido.")
  profileRequest <- parseRequest "https://openidconnect.googleapis.com/v1/userinfo"
  UserInfo subject email verified name <- requestJSON manager profileRequest
    { requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 accessToken)] }
  unless (verified && not (Text.null subject) && Text.length subject <= 255
    && Text.length email <= 320 && "@" `Text.isInfixOf` email) $
      ioError (userError "Identidade Google nao verificada.")
  pure (GoogleProfile subject (Text.toLower (Text.strip email)) (Text.take 200 (if Text.null (Text.strip name) then "Treinador" else Text.strip name)))
