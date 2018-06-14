{-# LANGUAGE OverloadedStrings #-}

module Flags where

import           Aura.Types (Language(..))
import           BasePrelude hiding (Version, FilePath, option, log)
import qualified Data.Set as S
import qualified Data.Text as T
import           Options.Applicative
import           Shelly hiding (command)

---

-- | A description of a run of Aura to attempt.
data Program = Program {
  -- ^ Whether Aura handles everything, or the ops and input are just passed down to Pacman.
  _operation  :: Either PacmanOp AuraOp
  -- ^ Flags common to both Aura and Pacman.
  , _commons  :: S.Set Common
  -- ^ Exposed flags to be passed to makepkg.
  , _makepkg  :: S.Set Makepkg
  -- ^ Top-level configuation flags (e.g. build user)
  , _config   :: S.Set Config
  -- ^ Other input, usually package names.
  , _input    :: S.Set T.Text
  -- ^ The human language of text output.
  , _language :: Maybe Language }

data Common = NoConfirm | Needed

data Makepkg = IgnoreArch | AllSource

data Config

-- | Inherited operations that are fed down to Pacman.
data PacmanOp = Database
              | Files
              | Query
              | Remove
              | Sync
              | TestDeps
              | Upgrade

-- | Operations unique to Aura.
data AuraOp = AurSync (Either AurOp [T.Text])
            | Backup  (Maybe  BackupOp)
            | Cache   (Either CacheOp [T.Text])
            | Log     (Maybe  LogOp)
            | Orphans (Maybe  OrphanOp)
            | Version

data AurOp = AurDeps     [T.Text]
           | AurInfo     [T.Text]
           | AurPkgbuild [T.Text]
           | AurSearch    T.Text
           | AurUpgrade
           | AurTarball  [T.Text]

data BackupOp = BackupClean Word | BackupRestore

data CacheOp = CacheBackup FilePath | CacheClean Word | CacheSearch T.Text

data LogOp = LogInfo [T.Text] | LogSearch T.Text

data OrphanOp = OrphanAbandon | OrphanAdopt [T.Text]

opts :: ParserInfo Program
opts = info (program <**> helper) (fullDesc <> header "Aura - Package manager for Arch Linux and the AUR.")

program :: Parser Program
program = Program
  <$> (fmap Right aurOps <|> fmap Left pacOps)
  <*> pure S.empty
  <*> pure S.empty
  <*> pure S.empty
  <*> pure S.empty
  <*> optional language
  where aurOps = aursync <|> backups <|> cache <|> log <|> orphans <|> version
        pacOps = pure undefined

aursync :: Parser AuraOp
aursync = AurSync <$> (bigA *> (fmap Left mods <|> fmap Right someArgs))
  where bigA = flag' () (long "aursync" <> short 'A' <> help "Install packages from the AUR.")
        mods = deps <|> ainfo <|> pkgbuild <|> search <|> upgrade <|> tarball
        deps = AurDeps <$>
          (flag' () (long "deps" <> short 'd' <> help "View dependencies of an AUR package.") *> someArgs)
        ainfo = AurInfo <$>
          (flag' () (long "info" <> short 'i' <> help "View AUR package information.") *> someArgs)
        pkgbuild = AurPkgbuild <$>
          (flag' () (long "pkgbuild" <> short 'p' <> help "View an AUR package's PKGBUILD file.") *> someArgs)
        search = AurSearch <$>
          strOption (long "search" <> short 's' <> metavar "STRING" <> help "Search the AUR via a search string.")
        upgrade = flag' AurUpgrade (long "sysupgrade" <> short 'u' <> help "Upgrade all installed AUR packages.")
        tarball = AurTarball <$>
          (flag' () (long "downloadonly" <> short 'w' <> help "Download a package's source tarball.") *> someArgs)

backups :: Parser AuraOp
backups = Backup <$> (bigB *> optional mods)
  where bigB = flag' () (long "save" <> short 'B' <> help "Save a package state.")
        mods = clean <|> restore
        clean = BackupClean <$>
          option auto (long "clean" <> short 'c' <> metavar "N" <> help "Keep the most recent N states, delete the rest.")
        restore = flag' BackupRestore (long "restore" <> help "Restore a previous package state.")

cache :: Parser AuraOp
cache = Cache <$> (bigC *> (fmap Left mods <|> fmap Right someArgs))
  where bigC = flag' () (long "downgrade" <> short 'C' <> help "Interact with the package cache.")
        mods = backup <|> clean <|> search
        backup = CacheBackup <$>
          strOption (long "backup"
                      <> metavar "PATH"
                      <> help "Backup the package cache to a given directory."
                      <> hidden)
        clean  = CacheClean <$>
          option auto (long "clean"
                        <> short 'c'
                        <> metavar "N"
                        <> help "Save the most recent N versions of a package in the cache, deleting the rest."
                        <> hidden)
        search = CacheSearch <$>
          strOption (long "search"
                      <> short 's'
                      <> metavar "STRING"
                      <> help "Search the package cache via a search string."
                      <> hidden)

log :: Parser AuraOp
log = Log <$> (bigL *> optional mods)
  where bigL = flag' () (long "viewlog" <> short 'L' <> help "View the Pacman log.")
        mods = inf <|> search
        inf  = LogInfo <$>
          (flag' () (long "info"
                      <> short 'i'
                      <> help "Display the installation history for given packages."
                      <> hidden) *> someArgs)
        search = LogSearch <$>
          strOption (long "search"
                      <> short 's'
                      <> metavar "STRING"
                      <> help "Search the Pacman log via a search string."
                      <> hidden)

orphans :: Parser AuraOp
orphans = Orphans <$> (bigO *> optional mods)
  where bigO    = flag' () (long "orphans" <> short 'O' <> help "Display all orphan packages.")
        mods    = abandon <|> adopt
        abandon = flag' OrphanAbandon (long "abandon" <> short 'j' <> help "Uninstall all orphan packages.")
        adopt   = OrphanAdopt <$>
          (flag' () (long "adopt" <> help "Mark some packages' install reason as 'Explicit'.") *> someArgs)

version :: Parser AuraOp
version = flag' Version (long "version" <> short 'V' <> help "Display Aura's version.")

someArgs :: Parser [T.Text]
someArgs = some (argument str (metavar "PACKAGES"))

language :: Parser Language
language = pure English