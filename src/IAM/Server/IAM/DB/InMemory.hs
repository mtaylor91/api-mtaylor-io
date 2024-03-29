{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TupleSections #-}
module IAM.Server.IAM.DB.InMemory ( inMemory, InMemory(..) ) where

import Control.Concurrent.STM
import Control.Monad.IO.Class
import Control.Monad.Except
import Crypto.Sign.Ed25519
import Data.UUID

import IAM.IAM
import IAM.Server.IAM.DB


data InMemoryState = InMemoryState
  { users :: ![UserId]
  , groups :: ![GroupId]
  , policies :: ![Policy]
  , memberships :: ![(UserId, GroupId)]
  , userPolicyAttachments :: ![(UserId, UUID)]
  , groupPolicyAttachments :: ![(GroupId, UUID)]
  , usersPublicKeys :: ![(UserId, PublicKey)]
  }


-- | InMemory is an in-memory implementation of the DB typeclass.
-- It uses an IORef to store a list of users.
newtype InMemory = InMemory (TVar InMemoryState)


inMemory :: IO InMemory
inMemory = InMemory <$> newTVarIO (InMemoryState [] [] [] [] [] [] [])


instance DB InMemory where

  getUser (InMemory tvar) uid = do
    maybeUser <- liftIO $ atomically $ do
      s <- readTVar tvar
      if uid `elem` users s
        then return $ Just $ user s
        else return Nothing
    maybe (throwError NotFound) return maybeUser
    where
      user s = User
        { userId = uid
        , userGroups = map snd $ filter ((== uid) . fst) $ memberships s
        , userPolicies = map snd $ filter ((== uid) . fst) $ userPolicyAttachments s
        , userPublicKeys = map snd $ filter ((== uid) . fst) $ usersPublicKeys s
        }

  listUsers (InMemory tvar) =
    liftIO $ atomically $ users <$> readTVar tvar

  createUser (InMemory tvar) u = do
    let uid = userId u
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if uid `elem` users s
        then return $ Left AlreadyExists
        else do
          modifyTVar' tvar addUser
          return $ Right u
    either throwError return result
    where
      addUser s = s
        { users = userId u : users s
        , memberships = memberships s ++ ((userId u, ) <$> userGroups u)
        , userPolicyAttachments = userPolicyAttachments s ++ ((userId u, ) <$> userPolicies u)
        , usersPublicKeys = usersPublicKeys s ++ ((userId u, ) <$> userPublicKeys u)
        }

  deleteUser (InMemory tvar) uid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if uid `elem` users s
        then do
          modifyTVar' tvar delUser
          return $ Right uid
        else return $ Left NotFound
    either throwError return result
    where
      delUser s = s
        { users = filter (/= uid) $ users s
        , memberships = filter ((/= uid) . fst) $ memberships s
        , userPolicyAttachments = filter ((/= uid) . fst) $ userPolicyAttachments s
        , usersPublicKeys = filter ((/= uid) . fst) $ usersPublicKeys s
        }

  getGroup (InMemory tvar) gid = do
    maybeGroup <- liftIO $ atomically $ do
      s <- readTVar tvar
      if gid `elem` groups s
        then return $ Just $ group s
        else return Nothing
    maybe (throwError NotFound) return maybeGroup
    where
      group s = Group
        { groupId = gid
        , groupUsers = map fst $ filter ((== gid) . snd) $ memberships s
        , groupPolicies = map snd $ filter ((== gid) . fst) $ groupPolicyAttachments s
        }

  listGroups (InMemory tvar) =
    liftIO $ atomically $ groups <$> readTVar tvar

  createGroup (InMemory tvar) group = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if groupId group `elem` groups s
        then return $ Left AlreadyExists
        else do
          modifyTVar' tvar addGroup
          return $ Right group
    either throwError return result
    where
      addGroup s = s
        { groups = groupId group : groups s
        , memberships = memberships s ++ ((, groupId group) <$> groupUsers group)
        , groupPolicyAttachments =
          groupPolicyAttachments s ++ ((groupId group, ) <$> groupPolicies group)
        }

  deleteGroup (InMemory tvar) gid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if gid `elem` groups s
        then do
          modifyTVar' tvar delGroup
          return $ Right ()
        else return $ Left NotFound
    either throwError return result
    where
      delGroup s = s
        { groups = filter (/= gid) $ groups s
        , memberships = filter ((/= gid) . snd) $ memberships s
        , groupPolicyAttachments = filter ((/= gid) . fst) $ groupPolicyAttachments s
        }

  getPolicy (InMemory tvar) pid = do
    maybePolicy <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== pid) . policyId) $ policies s of
        [] -> return Nothing
        p:_ -> return $ Just p
    maybe (throwError NotFound) return maybePolicy

  listPolicies (InMemory tvar) =
    liftIO $ atomically $ fmap policyId . policies <$> readTVar tvar

  listPoliciesForUser (InMemory tvar) uid =
    liftIO $ atomically $ do
      s <- readTVar tvar
      return $ filter ((`elem` policyIds s) . policyId) $ policies s
    where
      grps s =
        map snd $ filter ((== uid) . fst) $ memberships s
      policyIds s =
        userPolicyIds s ++ groupPolicyIds s
      userPolicyIds s =
        map snd $ filter ((== uid) . fst) $ userPolicyAttachments s
      groupPolicyIds s =
        map snd $ filter ((`elem` grps s) . fst) $ groupPolicyAttachments s

  createPolicy (InMemory tvar) policy = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== policyId policy) . policyId) $ policies s of
        [] -> do
          modifyTVar' tvar addPolicy
          return $ Right policy
        _:_ -> return $ Left AlreadyExists
    either throwError return result
    where
      addPolicy s = s { policies = policy : policies s }

  updatePolicy (InMemory tvar) policy = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== policyId policy) . policyId) $ policies s of
        [] -> return $ Left NotFound
        _:_ -> do
          modifyTVar' tvar updatePolicy'
          return $ Right policy
    either throwError return result
    where
      updatePolicy' s =
        s { policies = policy : filter ((/= policyId policy) . policyId) (policies s) }

  deletePolicy (InMemory tvar) pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== pid) . policyId) $ policies s of
        [] -> return $ Left NotFound
        policy:_ -> do
          modifyTVar' tvar delPolicy
          return $ Right policy
    either throwError return result
    where
      delPolicy s = s
        { policies = filter ((/= pid) . policyId) $ policies s
        , userPolicyAttachments = filter ((/= pid) . snd) $ userPolicyAttachments s
        , groupPolicyAttachments = filter ((/= pid) . snd) $ groupPolicyAttachments s
        }

  createMembership (InMemory tvar) uid gid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if uid `elem` users s && gid `elem` groups s
        then if (uid, gid) `notElem` memberships s
          then do
            modifyTVar' tvar addMembership
            return $ Right $ Membership uid gid
          else return $ Left AlreadyExists
        else return $ Left NotFound
    either throwError return result
    where
      addMembership s = s { memberships = (uid, gid) : memberships s }

  deleteMembership (InMemory tvar) uid gid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if (uid, gid) `elem` memberships s
        then do
          modifyTVar' tvar delMembership
          return $ Right $ Membership uid gid
        else return $ Left NotFound
    either throwError return result
    where
      delMembership s = s { memberships = filter (/= (uid, gid)) $ memberships s }

  createUserPolicyAttachment (InMemory tvar) uid pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== uid) . fst) $ userPolicyAttachments s of
        [] -> do
          modifyTVar' tvar addUserPolicyAttachment
          return $ Right $ UserPolicyAttachment uid pid
        _:_ -> return $ Left AlreadyExists
    either throwError return result
    where
      addUserPolicyAttachment s =
        s { userPolicyAttachments = (uid, pid) : userPolicyAttachments s }

  deleteUserPolicyAttachment (InMemory tvar) uid pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if (uid, pid) `elem` userPolicyAttachments s
        then do
          modifyTVar' tvar delUserPolicyAttachment
          return $ Right $ UserPolicyAttachment uid pid
        else return $ Left NotFound
    either throwError return result
    where
      delUserPolicyAttachment s =
        s { userPolicyAttachments = filter (/= (uid, pid)) $ userPolicyAttachments s }

  createGroupPolicyAttachment (InMemory tvar) gid pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      case filter ((== gid) . fst) $ groupPolicyAttachments s of
        [] -> do
          modifyTVar' tvar addGroupPolicyAttachment
          return $ Right $ GroupPolicyAttachment gid pid
        _:_ -> return $ Left AlreadyExists
    either throwError return result
    where
      addGroupPolicyAttachment s =
        s { groupPolicyAttachments = (gid, pid) : groupPolicyAttachments s }

  deleteGroupPolicyAttachment (InMemory tvar) gid pid = do
    result <- liftIO $ atomically $ do
      s <- readTVar tvar
      if (gid, pid) `elem` groupPolicyAttachments s
        then do
          modifyTVar' tvar delGroupPolicyAttachment
          return $ Right $ GroupPolicyAttachment gid pid
        else return $ Left NotFound
    either throwError return result
    where
      delGroupPolicyAttachment s =
        s { groupPolicyAttachments = filter (/= (gid, pid)) $ groupPolicyAttachments s }
