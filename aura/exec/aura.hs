{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE MonoLocalBinds    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}

{-

Copyright 2012 - 2019 Colin Woodbury <colin@fosskers.ca>

This file is part of Aura.

Aura is free s

             oftwar
        e:youcanredist
     ributeitand/ormodify
    itunderthetermsoftheGN
   UGeneralPublicLicenseasp
  ublishedbytheFreeSoftw
 areFoundation,either     ver        sio        n3o        fth
 eLicense,or(atyou       ropti      on)an      ylate      rvers
ion.Auraisdistr         ibutedi    nthehop    ethatit    willbeu
 seful,butWITHOUTA       NYWAR      RANTY      ;with      outev
 entheimpliedwarranty     ofM        ERC        HAN        TAB
  ILITYorFITNESSFORAPART
   ICULARPURPOSE.SeetheGNUG
    eneralPublicLicensefor
     moredetails.Youshoul
        dhavereceiveda
             copyof

the GNU General Public License
along with Aura.  If not, see <http://www.gnu.org/licenses/>.

-}

module Main ( main ) where

import           Aura.Colour (dtot)
import           Aura.Commands.A as A
import           Aura.Commands.B as B
import           Aura.Commands.C as C
import           Aura.Commands.L as L
import           Aura.Commands.O as O
import           Aura.Core
import           Aura.Languages
import           Aura.Logo
import           Aura.Pacman
import           Aura.Settings
import           Aura.Types
import           BasePrelude hiding (Version)
import           Control.Monad.Freer
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Reader
import qualified Data.Set as S
import qualified Data.Set.NonEmpty as NES
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           Data.Text.Prettyprint.Doc
import           Data.Text.Prettyprint.Doc.Render.Terminal
import           Flags
import           Options.Applicative (execParser)
import           Settings
import           System.Path (toFilePath)
import           System.Process.Typed (proc, runProcess)
import           Text.Pretty.Simple (pPrintNoColor)

---

auraVersion :: T.Text
auraVersion = "2.0.0"

main :: IO ()
main = do
  options   <- execParser opts
  esettings <- getSettings options
  case esettings of
    Left err -> T.putStrLn . dtot . ($ English) $ failure err
    Right ss -> execute ss options >>= exit ss

execute :: Settings -> Program -> IO (Either (Doc AnsiStyle) ())
execute ss p = first (($ langOf ss) . failure) <$> (runM . runReader ss . runError . executeOpts $ _operation p)

exit :: Settings -> Either (Doc AnsiStyle) () -> IO a
exit ss (Left e)  = scold ss e *> exitFailure
exit _  (Right _) = exitSuccess

executeOpts :: Either (PacmanOp, S.Set MiscOp) AuraOp -> Eff '[Error Failure, Reader Settings, IO] ()
executeOpts ops = do
  ss <- ask
  when (shared ss Debug) $ do
    pPrintNoColor ops
    pPrintNoColor (buildConfigOf ss)
    pPrintNoColor (commonConfigOf ss)
  let p (ps, ms) = liftEitherM . pacman $
        asFlag ps
        ++ foldMap asFlag ms
        ++ asFlag (commonConfigOf ss)
        ++ bool [] ["--quiet"] (switch ss LowVerbosity)
  case ops of
    Left o@(Sync (Left (SyncUpgrade _)) _, _) -> sudo (send $ B.saveState ss) *> p o
    Left o -> p o
    Right (AurSync o _) ->
      case o of
        Right ps              -> bool (trueRoot . sudo) id (switch ss DryRun) $ A.install ps
        Left (AurDeps ps)     -> A.displayPkgDeps ps
        Left (AurInfo ps)     -> A.aurPkgInfo ps
        Left (AurPkgbuild ps) -> A.displayPkgbuild ps
        Left (AurSearch s)    -> A.aurPkgSearch s
        Left (AurUpgrade ps)  -> bool (trueRoot . sudo) id (switch ss DryRun) $ A.upgradeAURPkgs ps
        Left (AurJson ps)     -> A.aurJson ps
    Right (Backup o) ->
      case o of
        Nothing              -> sudo . send $ B.saveState ss
        Just (BackupClean n) -> sudo . send $ B.cleanStates ss n
        Just BackupRestore   -> sudo B.restoreState
        Just BackupList      -> send B.listStates
    Right (Cache o) ->
      case o of
        Right ps                -> sudo $ C.downgradePackages ps
        Left (CacheSearch s)    -> C.searchCache s
        Left (CacheClean n)     -> sudo $ C.cleanCache n
        Left CacheCleanNotSaved -> sudo C.cleanNotSaved
        Left (CacheBackup pth)  -> sudo $ C.backupCache pth
    Right (Log o) ->
      case o of
        Nothing            -> L.viewLogFile
        Just (LogInfo ps)  -> L.logInfoOnPkg ps
        Just (LogSearch s) -> ask >>= send . flip L.searchLogFile s
    Right (Orphans o) ->
      case o of
        Nothing               -> send O.displayOrphans
        Just OrphanAbandon    -> sudo $ send orphans >>= traverse_ removePkgs . NES.fromSet
        Just (OrphanAdopt ps) -> O.adoptPkg ps
    Right Version   -> send $ getVersionInfo >>= animateVersionMsg ss auraVersion
    Right Languages -> displayOutputLanguages
    Right ViewConf  -> viewConfFile

displayOutputLanguages :: (Member (Reader Settings) r, Member IO r) => Eff r ()
displayOutputLanguages = do
  ss <- ask
  send . notify ss . displayOutputLanguages_1 $ langOf ss
  send $ traverse_ print [English ..]

viewConfFile :: (Member (Reader Settings) r, Member IO r) => Eff r ()
viewConfFile = do
  pth <- asks (either id id . configPathOf . commonConfigOf)
  send . void . runProcess @IO $ proc "less" [toFilePath pth]
