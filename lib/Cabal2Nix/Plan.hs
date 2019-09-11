{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cabal2Nix.Plan
where

import           Cabal2Nix.Util                           ( quoted
                                                          , bindPath
                                                          )
import           Data.Char                                ( isDigit )
import           Data.HashMap.Strict                      ( HashMap )
import qualified Data.HashMap.Strict           as Map
import           Data.List.NonEmpty                       ( NonEmpty (..) )
import           Data.Text                                ( Text )
import qualified Data.Text                     as Text
import           Nix.Expr

type Version = Text
type Revision = Text -- Can be: rNUM, cabal file sha256, or "default"

data Plan = Plan
  { packages :: HashMap Text (Maybe Package)
  , compilerId :: Text
  , compilerPackages :: HashMap Text (Maybe Version)
  }

data Package = Package
  { packageVersion :: Version
  , packageRevision :: Maybe Revision
  , packageFlags :: HashMap Text Bool
  }

plan2nix :: Plan -> NExpr
plan2nix (Plan { packages, compilerId, compilerPackages }) =
  mkFunction "hackage"
    . mkNonRecSet
    $ [ "packages" $= (mkNonRecSet $ uncurry bind =<< Map.toList quotedPackages)
      , "compiler" $= mkNonRecSet
        [ "version" $= mkStr (Text.dropWhile (not . isDigit) compilerId)
        , "nix-name" $= mkStr nixName
        , "packages" $= mkNonRecSet (fmap (uncurry bind') $ Map.toList $ mapKeys quoted compilerPackages)
        ]
      ]
 where
  nixName =
    let n = Text.filter (`notElem` ['-', '.']) compilerId
    in  if "ghcjs" `Text.isPrefixOf` compilerId
          then Text.take (Text.length "ghcjs" + 2) n -- GHCJS keys in the nix package set are of the form "ghcjs00"
          else n
  quotedPackages = mapKeys quoted packages
  bind pkg (Just (Package { packageVersion, packageRevision, packageFlags })) =
    let verExpr      = mkSym "hackage" @. pkg @. quoted packageVersion
        revExpr      = verExpr @. "revisions" @. maybe "default" quoted packageRevision
        flagBindings = Map.foldrWithKey
          (\fname val acc -> bindPath (pkg :| ["flags", fname]) (mkBool val) : acc)
          []
          packageFlags
    in  revBinding pkg revExpr : flagBindings
  bind pkg Nothing = [revBinding pkg mkNull]
  revBinding pkg revExpr = bindPath (pkg :| ["revision"]) revExpr
  bind' pkg ver = pkg $= maybe mkNull mkStr ver
  mapKeys f = Map.fromList . fmap (\(k, v) -> (f k, v)) . Map.toList
