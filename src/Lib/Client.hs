{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Lib.Client
  ( listUsers
  , createUser
  , mkUserClient
  , listGroups
  , createGroup
  , mkGroupClient
  , listPolicies
  , createPolicy
  , mkPolicyClient
  , createMembership
  , deleteMembership
  , UserClient(..)
  , UserPolicyClient(..)
  , GroupClient(..)
  , GroupPolicyClient(..)
  , PolicyClient(..)
  ) where

import Servant
import Servant.Client
import Data.UUID (UUID)
import Lib.API
import Lib.IAM


type UsersClientM
  = ClientM [UserId]
  :<|> (UserPrincipal -> ClientM UserPrincipal)
  :<|> (UserId -> UserClientM)


type UserClientM =
    ClientM User
    :<|> ClientM UserId
    :<|> (UUID -> UserPolicyClientM)


type UserPolicyClientM = ClientM UserPolicyAttachment :<|> ClientM UserPolicyAttachment


type GroupsClientM
  = ClientM [GroupId]
  :<|> (Group -> ClientM Group)
  :<|> (GroupId -> GroupClientM)


type GroupClientM =
    ClientM Group
    :<|> ClientM GroupId
    :<|> (UUID -> GroupPolicyClientM)


type GroupPolicyClientM =
  ClientM GroupPolicyAttachment :<|> ClientM GroupPolicyAttachment


type PoliciesClientM
  = ClientM [Policy]
  :<|> (Policy -> ClientM Policy)
  :<|> (UUID -> PolicyClientM)


type PolicyClientM =
    ClientM Policy
    :<|> ClientM Policy


type MembershipsClientM
  = (Membership -> ClientM Membership)
  :<|> (GroupId -> UserId -> ClientM Membership)


data UserClient = UserClient
  { getUser :: !(ClientM User)
  , deleteUser :: !(ClientM UserId)
  , userPolicyClient :: !(UUID -> UserPolicyClient)
  }


data UserPolicyClient = UserPolicyClient
  { attachUserPolicy :: !(ClientM UserPolicyAttachment)
  , detachUserPolicy :: !(ClientM UserPolicyAttachment)
  }


data GroupClient = GroupClient
  { getGroup :: !(ClientM Group)
  , deleteGroup :: !(ClientM GroupId)
  , groupPolicyClient :: !(UUID -> GroupPolicyClient)
  }


data GroupPolicyClient = GroupPolicyClient
  { attachGroupPolicy :: !(ClientM GroupPolicyAttachment)
  , detachGroupPolicy :: !(ClientM GroupPolicyAttachment)
  }


data PolicyClient = PolicyClient
  { getPolicy :: !(ClientM Policy)
  , deletePolicy :: !(ClientM Policy)
  }


usersClient :: UsersClientM
groupsClient :: GroupsClientM
policiesClient :: PoliciesClientM
membershipsClient :: MembershipsClientM


usersClient :<|> groupsClient :<|> policiesClient :<|> membershipsClient = client iamAPI


listUsers :: ClientM [UserId]
createUser :: UserPrincipal -> ClientM UserPrincipal
userClient :: UserId -> UserClientM


(listUsers :<|> createUser :<|> userClient) = usersClient


mkUserClient :: UserId -> UserClient
mkUserClient uid =
  let (getUser' :<|> deleteUser' :<|> userPolicyClient') = userClient uid
  in UserClient getUser' deleteUser' (mkUserPolicyClient userPolicyClient')
  where
  mkUserPolicyClient :: (UUID -> UserPolicyClientM) -> UUID -> UserPolicyClient
  mkUserPolicyClient userPolicyClient' pid =
    let (attachUserPolicy' :<|> detachUserPolicy') = userPolicyClient' pid
    in UserPolicyClient attachUserPolicy' detachUserPolicy'


listGroups :: ClientM [GroupId]
createGroup :: Group -> ClientM Group
groupClient :: GroupId -> GroupClientM


(listGroups :<|> createGroup :<|> groupClient) = groupsClient


mkGroupClient :: GroupId -> GroupClient
mkGroupClient gid =
  let (getGroup' :<|> deleteGroup' :<|> groupPolicyClient') = groupClient gid
  in GroupClient getGroup' deleteGroup' (mkGroupPolicyClient groupPolicyClient')
  where
  mkGroupPolicyClient :: (UUID -> GroupPolicyClientM) -> UUID -> GroupPolicyClient
  mkGroupPolicyClient groupPolicyClient' pid =
    let (attachGroupPolicy' :<|> detachGroupPolicy') = groupPolicyClient' pid
    in GroupPolicyClient attachGroupPolicy' detachGroupPolicy'


listPolicies :: ClientM [Policy]
createPolicy :: Policy -> ClientM Policy
policyClient :: UUID -> PolicyClientM


listPolicies :<|> createPolicy :<|> policyClient = policiesClient


mkPolicyClient :: UUID -> PolicyClient
mkPolicyClient pid =
  let (getPolicy' :<|> deletePolicy') = policyClient pid
  in PolicyClient getPolicy' deletePolicy'


createMembership :: Membership -> ClientM Membership
deleteMembership :: GroupId -> UserId -> ClientM Membership


createMembership :<|> deleteMembership = membershipsClient