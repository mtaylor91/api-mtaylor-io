{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main (main) where

import Control.Monad.IO.Class
import Control.Monad.Except
import Crypto.Sign.Ed25519
import Data.Aeson
import Data.ByteString.Base64
import Data.Text
import Data.Text.Encoding
import Data.UUID
import Data.UUID.V4
import Network.HTTP.Types

import Test.Hspec
import Test.Hspec.Wai

import IAM.IAM
import IAM.Server.API (app)
import IAM.Server.Auth (authStringToSign)
import IAM.Server.IAM.DB
import IAM.Server.IAM.DB.InMemory

main :: IO ()
main = do
  db <- inMemory
  (pk, sk) <- createKeypair
  callerPolicyId <- nextRandom
  let allowReads = Rule Allow Read "*"
      allowWrites = Rule Allow Write "*"
      callerPolicy = Policy callerPolicyId callerPolicyRules
      callerPolicyRules = [allowReads, allowWrites]
      callerId = UserEmail "caller@example.com"
      callerPrincipal = User callerId [] [] [pk]
  result0 <- runExceptT $ createUser db callerPrincipal
  case result0 of
    Right _  -> do
      result1 <- runExceptT $ createPolicy db callerPolicy
      case result1 of
        Right _ -> do
          result2 <- runExceptT $ createUserPolicyAttachment db callerId callerPolicyId
          case result2 of
            Right _ ->
              hspec $ spec db pk sk
            Left _ -> error "Failed to attach test user policy"
        Left _ -> error "Failed to create test user policy"
    Left _ -> error "Failed to create test user"

spec :: DB db => db -> PublicKey -> SecretKey -> Spec
spec db callerPK callerSK = with (return $ app db) $ do
  describe "GET /users" $ do
    it "responds with 200" $ do
      requestId <- liftIO nextRandom
      let headers =
            [ ("Authorization", "Signature " <> sig)
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodGet "/users" "" requestId
      request methodGet "/users" headers mempty `shouldRespondWith` 200
  describe "POST /users with email address" $ do
    it "responds with 201" $ do
      (pk, _) <- liftIO createKeypair
      requestId <- liftIO nextRandom
      let uid = UserEmail "bob@example.com"
          user = User uid [] [] [pk]
          userJSON = encode user
          headers =
            [ ("Authorization", "Signature " <> sig)
            , ("Content-Type", "application/json")
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodPost "/users" "" requestId
      request methodPost "/users" headers userJSON `shouldRespondWith` 201
      result <- liftIO $ runExceptT $ deleteUser db uid
      liftIO $ result `shouldBe` Right uid
  describe "POST /users with UUID" $ do
    it "responds with 201" $ do
      uuid <- liftIO nextRandom
      (pk, _) <- liftIO createKeypair
      requestId <- liftIO nextRandom
      let user = User (UserUUID uuid) [] [] [pk]
          userJSON = encode user
          headers =
            [ ("Authorization", "Signature " <> sig)
            , ("Content-Type", "application/json")
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodPost "/users" "" requestId
      request methodPost "/users" headers userJSON `shouldRespondWith` 201
      result <- liftIO $ runExceptT $ deleteUser db $ UserUUID uuid
      liftIO $ result `shouldBe` Right (UserUUID uuid)
  describe "GET /groups" $ do
    it "responds with 200" $ do
      requestId <- liftIO nextRandom
      let headers =
            [ ("Authorization", "Signature " <> sig)
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodGet "/groups" "" requestId
      request methodGet "/groups" headers mempty `shouldRespondWith` 200
  describe "POST /groups" $ do
    it "responds with 201" $ do
      requestId <- liftIO nextRandom
      let headers =
            [ ("Authorization", "Signature " <> sig)
            , ("Content-Type", "application/json")
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          groupJSON = encode $ Group (GroupName "admins") [] []
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodPost "/groups" "" requestId
      request methodPost "/groups" headers groupJSON `shouldRespondWith` 201
      r <- liftIO $ runExceptT $ deleteGroup db $ GroupName "admins"
      liftIO $ r `shouldBe` Right ()
  describe "GET /policies" $ do
    it "responds with 200" $ do
      requestId <- liftIO nextRandom
      let headers =
            [ ("Authorization", "Signature " <> sig)
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 requestIdString)
            ]
          requestIdString = pack $ toString requestId
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodGet "/policies" "" requestId
      request methodGet "/policies" headers mempty `shouldRespondWith` 200
  describe "POST /policies" $ do
    it "responds with 201" $ do
      pid <- liftIO nextRandom
      requestId <- liftIO nextRandom
      let headers =
            [ ("Authorization", "Signature " <> sig)
            , ("Content-Type", "application/json")
            , ("X-MTaylor-IO-User-Id", "caller@example.com")
            , ("X-MTaylor-IO-Public-Key", encodeUtf8 $ encodeBase64 $ unPublicKey callerPK)
            , ("X-MTaylor-IO-Request-Id", encodeUtf8 $ pack $ toString requestId)
            ]
          policy = Policy pid [Rule Allow Read "*", Rule Allow Write "*"]
          policyJSON = encode policy
          sig = encodeUtf8 $ encodeBase64 $ unSignature $ dsign callerSK stringToSign
          stringToSign = authStringToSign methodPost "/policies" "" requestId
      request methodPost "/policies" headers policyJSON `shouldRespondWith` 201
      r <- liftIO $ runExceptT $ deletePolicy db pid
      liftIO $ r `shouldBe` Right policy
