{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -O2 -ddump-splices #-}
import Data.Int (Int64)
import System.Environment (getArgs)
import Control.Monad.Par.Meta.Dist (longSpawn, Par, get, shutdownDist, WhichTransport(Pipes,TCP),
				   runParDistWithTransport, runParSlaveWithTransport)
import Control.Monad.IO.Class (liftIO)
-- Tweaked version of CloudHaskell's closures:
import Remote2.Call (mkClosureRec, remotable)

import Control.Concurrent   (myThreadId)
import System.Process       (readProcess)
import System.Posix.Process (getProcessID)
import Data.Char            (isSpace)

--------------------------------------------------------------------------------

type FibType = Int64

-- Par monad version + distributed execution:
parfib1 :: FibType -> Par FibType
parfib1 n | n < 2 = return 1
parfib1 n = do 
    liftIO $ do 
       mypid <- getProcessID
       mytid <- myThreadId
--       host  <- hostName
       let host = ""
#if 0
       putStrLn $ " [host "++host++" pid "++show mypid++" "++show mytid++"] PARFIB "++show n
#endif
       return ()
    xf <- longSpawn $ $(mkClosureRec 'parfib1) (n-1)
    y  <-             parfib1 (n-2)
    x  <- get xf
    return (x+y)

hostName = do s <- readProcess "hostname" [] ""
	      return (trim s)
 where 
  -- | Trim whitespace from both ends of a string.
  trim :: String -> String
  trim = f . f
     where f = reverse . dropWhile isSpace


-- Generate stub code for RPC:
remotable ['parfib1]

-- transport = Pipes
transport = TCP

main = do 
    args <- getArgs
    let (version, size, cutoff) = case args of 
            []      -> ("master", 3, 1)
            [v]     -> (v,        3, 1)
            [v,n]   -> (v, read n,   1)
            [v,n,c] -> (v, read n, read c)

    case version of 
        "slave" -> runParSlaveWithTransport [__remoteCallMetaData] TCP
        "master" -> do 
		       putStrLn "Using non-thresholded version:"
		       ans <- (runParDistWithTransport [__remoteCallMetaData] TCP
			       (parfib1 size) :: IO FibType)
		       putStrLn $ "Final answer: " ++ show ans
		       putStrLn $ "Calling SHUTDOWN..."
                       shutdownDist
		       putStrLn $ "... returned from shutdown, apparently successful."

        str -> error$"Unhandled mode: " ++ str

