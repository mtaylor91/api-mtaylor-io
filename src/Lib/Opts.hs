{-# LANGUAGE OverloadedStrings #-}
module Lib.Opts ( options, run, ServerOptions(..) ) where

import Options.Applicative

import Lib.Command.Keypair
import Lib.Command.Create
import Lib.Command.Get
import Lib.Command.Server


data Command
  = Create !CreateCommand
  | Get !GetCommand
  | Keypair !KeypairOptions
  | Server !ServerOptions
  deriving (Show)


newtype Options = Options Command deriving (Show)


options :: Parser Options
options = Options <$> hsubparser
  ( command "create"
    (info (Create <$> createCommand) (progDesc "Create resources"))
  <> command "get"
    (info (Get <$> getCommand) (progDesc "Get resources"))
  <> command "keypair"
    (info (Keypair <$> keypairOptions) (progDesc "Generate a keypair"))
  <> command "server"
    (info (Server <$> serverOptions) (progDesc "Start the server"))
  )


runOptions :: Options -> IO ()
runOptions opts =
  case opts of
    Options (Create cmd) ->
      create cmd
    Options (Get cmd) ->
      get cmd
    Options (Keypair opts') ->
      keypair opts'
    Options (Server opts') ->
      server opts'


run :: IO ()
run = execParser opts >>= runOptions
  where
    opts = info (options <**> helper)
      ( fullDesc
     <> header "api-mtaylor-io - API server for api.mtaylor.io service."
      )
