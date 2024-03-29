{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module IAM.Client
  ( getCaller
  , deleteCaller
  , mkCallerPolicyClient
  , listUsers
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
import IAM.API
import IAM.IAM


type UsersClientM
  = ClientM [UserId]
  :<|> (User -> ClientM User)
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
  = ClientM [UUID]
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


callerClient :: UserClientM
usersClient :: UsersClientM
groupsClient :: GroupsClientM
policiesClient :: PoliciesClientM
membershipsClient :: MembershipsClientM


callerClient
  :<|> usersClient
  :<|> groupsClient
  :<|> policiesClient
  :<|> membershipsClient
  = client iamAPI


getCaller :: ClientM User
deleteCaller :: ClientM UserId
callerPolicyClient :: UUID -> UserPolicyClientM


(getCaller :<|> deleteCaller :<|> callerPolicyClient) = callerClient


mkCallerPolicyClient :: UUID -> UserPolicyClient
mkCallerPolicyClient pid =
  let (attachUserPolicy' :<|> detachUserPolicy') = callerPolicyClient pid
  in UserPolicyClient attachUserPolicy' detachUserPolicy'


listUsers :: ClientM [UserId]
createUser :: User -> ClientM User
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


listPolicies :: ClientM [UUID]
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
