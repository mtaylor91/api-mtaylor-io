{-# LANGUAGE OverloadedStrings #-}
module IAM.Server.DB.InMemory ( inMemory, InMemory(..) ) where

import Control.Concurrent.STM
import Control.Lens
import Control.Monad.IO.Class
import Control.Monad.Except
import Data.UUID (toText)

import IAM.Group
import IAM.GroupPolicy
import IAM.Identifiers
import IAM.Membership
import IAM.Policy
import IAM.Range
import IAM.Server.DB
import IAM.Server.DB.InMemory.State
import IAM.User
import IAM.UserPolicy


-- | InMemory is an in-memory implementation of the DB typeclass.
newtype InMemory = InMemory (TVar InMemoryState)


inMemory :: IO InMemory
inMemory = InMemory <$> newTVarIO (InMemoryState [] [] [] [] [] [] [] [] [])


instance DB InMemory where

  getUser (InMemory tvar) uid = do
    s <- liftIO $ readTVarIO tvar
    case s ^. userState uid of
      Just u -> return u
      Nothing -> throwError $ NotFound "user" $ userIdentifierToText uid

  getUserId (InMemory tvar) uid = do
    s <- liftIO $ readTVarIO tvar
    case resolveUserIdentifier s uid of
      Just uid' -> return uid'
      Nothing -> throwError $ NotFound "user" $ userIdentifierToText uid

  listUsers (InMemory tvar) (Range offset maybeLimit) = do
    s <- liftIO $ readTVarIO tvar
    let users' = resolveUser s <$> users s
     in return $ case maybeLimit of
      Just limit -> Prelude.take limit $ Prelude.drop offset users'
      Nothing -> Prelude.drop offset users'
    where
      resolveUser :: InMemoryState -> UserId -> UserIdentifier
      resolveUser s uid = case s ^. userState (UserId uid) of
        Nothing -> UserId uid
        Just u ->
          case userEmail u of
            Nothing -> UserId uid
            Just email -> UserIdAndEmail uid email

  createUser (InMemory tvar) u@(User uid _ _ _ _) = do
    liftIO $ atomically $ do
      s <- readTVar tvar
      writeTVar tvar $ s & userState (UserId uid) ?~ u
    return u

  deleteUser (InMemory tvar) uid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case s ^. userState uid of
        Just u -> do
          writeTVar tvar $ s & userState uid .~ Nothing
          return $ Right u
        Nothing ->
          return $ Left $ NotFound "user" $ userIdentifierToText uid
    either throwError return result

  getGroup (InMemory tvar) gid = do
    s <- liftIO $ readTVarIO tvar
    case s ^. groupState gid of
      Just g -> return g
      Nothing -> throwError $ NotFound "group" $ groupIdentifierToText gid

  listGroups (InMemory tvar) (Range offset maybeLimit) = do
    s <- liftIO $ readTVarIO tvar
    let gs = resolveGroup s <$> groups s
    case maybeLimit of
      Just limit -> return $ Prelude.take limit $ Prelude.drop offset gs
      Nothing -> return $ Prelude.drop offset gs
    where
      resolveGroup :: InMemoryState -> GroupId -> GroupIdentifier
      resolveGroup s gid = case s ^. groupState (GroupId gid) of
        Nothing -> GroupId gid
        Just g ->
          case groupName g of
            Nothing -> GroupId gid
            Just name -> GroupIdAndName gid name

  createGroup (InMemory tvar) g@(Group gid _ _ _) = do
    liftIO $ atomically $ do
      s <- readTVar tvar
      writeTVar tvar $ s & groupState (GroupId gid) ?~ g
    return g

  deleteGroup (InMemory tvar) gid = do
    result <- liftIO $ atomically $
      readTVar tvar >>= \s -> case s ^. groupState gid of
        Just g -> do
          writeTVar tvar $ s & groupState gid .~ Nothing
          return $ Right g
        Nothing ->
          return $ Left $ NotFound "group" $ groupIdentifierToText gid
    either throwError return result

  getPolicy (InMemory tvar) pid = do
    s <- liftIO $ readTVarIO tvar
    case s ^. policyState pid of
      Just p -> return p
      Nothing -> throwError $ NotFound "policy" $ toText pid

  listPolicyIds (InMemory tvar) (Range offset maybeLimit) = do
    s <- liftIO $ readTVarIO tvar
    let policyIds = policyId <$> policies s
    case maybeLimit of
      Just limit -> return $ Prelude.take limit $ Prelude.drop offset policyIds
      Nothing -> return $ Prelude.drop offset policyIds

  listPoliciesForUser (InMemory tvar) uid host = do
    s <- liftIO $ readTVarIO tvar
    let gs = [gid | (uid', gid) <- memberships s, uid' == uid]
    let gps = [pid | (gid, pid) <- groupPolicyAttachments s, gid `Prelude.elem` gs]
    let ups = [pid | (uid', pid) <- userPolicyAttachments s, uid' == uid]
    let pids = Prelude.foldr (:) gps ups
    return $
      [ p | p <- policies s
      , hostname p == host
      , policyId p `Prelude.elem` pids
      ]

  createPolicy (InMemory tvar) p = do
    liftIO $ atomically $ do
      s <- readTVar tvar
      writeTVar tvar $ s & policyState (policyId p) ?~ p
    return p

  updatePolicy (InMemory tvar) p = do
    liftIO $ atomically $ do
      s <- readTVar tvar
      writeTVar tvar $ s & policyState (policyId p) ?~ p
      return p

  deletePolicy (InMemory tvar) pid = do
    result <- liftIO $ atomically $
      readTVar tvar >>= \s -> case s ^. policyState pid of
        Just p -> do
          writeTVar tvar $ s & policyState pid .~ Nothing
          return $ Right p
        Nothing ->
          return $ Left $ NotFound "policy" $ toText pid
    either throwError return result

  createMembership (InMemory tvar) uid gid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case (resolveUserIdentifier s uid, resolveGroupIdentifier s gid) of
        (Just uid', Just gid') -> do
          case Prelude.filter (== (uid', gid')) $ memberships s of
            [] -> do
              writeTVar tvar $ s { memberships = (uid', gid') : memberships s }
              return $ Right $ Membership uid' gid'
            _:_ ->
              return $ Left AlreadyExists
        (Nothing, _) ->
          return $ Left $ NotFound "user" $ userIdentifierToText uid
        (_, Nothing) ->
          return $ Left $ NotFound "group" $ groupIdentifierToText gid
    either throwError return result

  deleteMembership (InMemory tvar) uid gid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case (resolveUserIdentifier s uid, resolveGroupIdentifier s gid) of
        (Just uid', Just gid') -> do
          case Prelude.filter (== (uid', gid')) $ memberships s of
            [] ->
              return $ Left $ NotFound "membership" $ userIdentifierToText uid
                <> " " <> groupIdentifierToText gid
            _:_ -> do
              writeTVar tvar $ s { memberships =
                Prelude.filter (/= (uid', gid')) $ memberships s }
              return $ Right $ Membership uid' gid'
        (Nothing, _) ->
          return $ Left $ NotFound "user" $ userIdentifierToText uid
        (_, Nothing) ->
          return $ Left $ NotFound "group" $ groupIdentifierToText gid
    either throwError return result

  createUserPolicyAttachment (InMemory tvar) uid pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case resolveUserIdentifier s uid of
        Just uid' -> do
          case Prelude.filter (== (uid', pid)) $ userPolicyAttachments s of
            [] -> do
              writeTVar tvar $ s { userPolicyAttachments =
                (uid', pid) : userPolicyAttachments s }
              return $ Right $ UserPolicyAttachment uid' pid
            _:_ ->
              return $ Left AlreadyExists
        Nothing ->
          return $ Left $ NotFound "user" $ userIdentifierToText uid
    either throwError return result

  deleteUserPolicyAttachment (InMemory tvar) uid pid = do
    result <- liftIO $ atomically $
      readTVar tvar >>= \s -> case resolveUserIdentifier s uid of
        Just uid' -> do
          case Prelude.filter (== (uid', pid)) $ userPolicyAttachments s of
            [] ->
              return $ Left $ NotFound "user policy attachment" $
                userIdentifierToText uid <> " " <> toText pid
            _:_ -> do
              writeTVar tvar $ s { userPolicyAttachments =
                Prelude.filter (/= (uid', pid)) $ userPolicyAttachments s }
              return $ Right $ UserPolicyAttachment uid' pid
        Nothing ->
          return $ Left $ NotFound "user" $ userIdentifierToText uid
    either throwError return result

  createGroupPolicyAttachment (InMemory tvar) gid pid = do
    result <- liftIO $ atomically $
      readTVar tvar >>= \s -> case resolveGroupIdentifier s gid of
        Just gid' -> do
          case Prelude.filter (== (gid', pid)) $ groupPolicyAttachments s of
            [] -> do
              writeTVar tvar $ s { groupPolicyAttachments =
                (gid', pid) : groupPolicyAttachments s }
              return $ Right $ GroupPolicyAttachment gid' pid
            _:_ ->
              return $ Left AlreadyExists
        Nothing ->
          return $ Left $ NotFound "group" $ groupIdentifierToText gid
    either throwError return result

  deleteGroupPolicyAttachment (InMemory tvar) gid pid = do
    result <- liftIO $ atomically $
      readTVar tvar >>= \s -> case resolveGroupIdentifier s gid of
        Just gid' -> do
          case Prelude.filter (== (gid', pid)) $ groupPolicyAttachments s of
            [] ->
              return $ Left $ NotFound "group policy attachment" $
                groupIdentifierToText gid <> " " <> toText pid
            _:_ -> do
              writeTVar tvar $ s { groupPolicyAttachments =
                Prelude.filter (/= (gid', pid)) $ groupPolicyAttachments s }
              return $ Right $ GroupPolicyAttachment gid' pid
        Nothing ->
          return $ Left $ NotFound "group" $ groupIdentifierToText gid
    either throwError return result
