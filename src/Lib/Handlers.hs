module Lib.Handlers
  ( getUserHandler
  , listUsersHandler
  , createUserHandler
  , deleteUserHandler
  , getGroupHandler
  , listGroupsHandler
  , createGroupHandler
  , deleteGroupHandler
  , getPolicyHandler
  , listPoliciesHandler
  , createPolicyHandler
  , deletePolicyHandler
  , createMembershipHandler
  , deleteMembershipHandler
  ) where

import Control.Monad.IO.Class
import Control.Monad.Except
import Data.UUID
import Servant

import Lib.Auth
import Lib.IAM
import Lib.IAM.DB
import Lib.IAM.Policy

dbError :: DBError -> ServerError
dbError AlreadyExists = err409
dbError NotFound      = err404
dbError InternalError = err500

getUserHandler :: DB db => db -> Auth -> UserId -> Handler User
getUserHandler db _ uid = do
  result <- liftIO $ runExceptT $ getUser db uid
  case result of
    Right user' -> return user'
    Left err    -> throwError $ dbError err

listUsersHandler :: DB db => db -> Auth -> Handler [UserId]
listUsersHandler db _ = do
  result <- liftIO $ runExceptT $ listUsers db
  case result of
    Right users' -> return users'
    Left err     -> throwError $ dbError err

createUserHandler :: DB db => db -> Auth -> UserPrincipal -> Handler UserPrincipal
createUserHandler db _ userPrincipal = do
  result <- liftIO $ runExceptT $ createUser db userPrincipal
  case result of
    Right user' -> return user'
    Left err    -> throwError $ dbError err

deleteUserHandler :: DB db => db -> Auth -> UserId -> Handler UserId
deleteUserHandler db _ uid = do
  result <- liftIO $ runExceptT $ deleteUser db uid
  case result of
    Right user' -> return user'
    Left err    -> throwError $ dbError err

getGroupHandler :: DB db => db -> Auth -> GroupId -> Handler Group
getGroupHandler db _ gid = do
  result <- liftIO $ runExceptT $ getGroup db gid
  case result of
    Right group' -> return group'
    Left err     -> throwError $ dbError err

listGroupsHandler :: DB db => db -> Auth -> Handler [GroupId]
listGroupsHandler db _ = do
  result <- liftIO $ runExceptT $ listGroups db
  case result of
    Right groups' -> return groups'
    Left err      -> throwError $ dbError err

createGroupHandler :: DB db => db -> Auth -> Group -> Handler Group
createGroupHandler db _ group = do
  result <- liftIO $ runExceptT $ createGroup db group
  case result of
    Right group' -> return group'
    Left err -> throwError $ dbError err

deleteGroupHandler :: DB db => db -> Auth -> GroupId -> Handler GroupId
deleteGroupHandler db _ gid = do
  result <- liftIO $ runExceptT $ deleteGroup db gid
  case result of
    Right () -> return gid
    Left err -> throwError $ dbError err

getPolicyHandler :: DB db => db -> Auth -> UUID -> Handler Policy
getPolicyHandler db _ policy = do
  result <- liftIO $ runExceptT $ getPolicy db policy
  case result of
    Right policy' -> return policy'
    Left err      -> throwError $ dbError err

listPoliciesHandler :: DB db => db -> Auth -> Handler [Policy]
listPoliciesHandler db _ = do
  result <- liftIO $ runExceptT $ listPolicies db
  case result of
    Right policies' -> return policies'
    Left err        -> throwError $ dbError err

createPolicyHandler :: DB db => db -> Auth -> Policy -> Handler Policy
createPolicyHandler db auth policy = do
  let callerPolicies = authPolicies $ authorization auth
  if policy `isAllowedBy` policyRules callerPolicies
    then createPolicy'
    else throwError err403
  where
    createPolicy' = do
      result <- liftIO $ runExceptT $ createPolicy db policy
      case result of
        Right policy' -> return policy'
        Left err      -> throwError $ dbError err

deletePolicyHandler :: DB db => db -> Auth -> UUID -> Handler Policy
deletePolicyHandler db _ policy = do
  result <- liftIO $ runExceptT $ deletePolicy db policy
  case result of
    Right policy' -> return policy'
    Left err      -> throwError $ dbError err

createMembershipHandler :: DB db => db -> Auth -> Membership -> Handler Membership
createMembershipHandler db _ (Membership uid gid) = do
  result <- liftIO $ runExceptT $ createMembership db uid gid
  case result of
    Right membership -> return membership
    Left err         -> throwError $ dbError err

deleteMembershipHandler :: DB db => db -> Auth -> GroupId -> UserId -> Handler Membership
deleteMembershipHandler db _ gid uid = do
  result <- liftIO $ runExceptT $ deleteMembership db uid gid
  case result of
    Right membership -> return membership
    Left err         -> throwError $ dbError err
