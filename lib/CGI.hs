module CGI where
import Control.Exception
import Numeric
import System.Environment
import Codec.Binary.UTF8.String

catchErrorsToHTML :: IO () -> IO ()
catchErrorsToHTML = handle f where
    f (SomeException e) = do
        putStrLn "Status: 500 Internal Server Error"
        putStrLn "Content-Type: text/html; charset=UTF-8"
        putStrLn ""
        putStrLn $ "<!-- Error! --><div class=\"server-error\">" ++ show e ++ "</div>"

unescURI = decodeString . f . encodeString where
    f [] = []
    f ('%' : a : b : r) = toEnum (fst (head (readHex [a,b]))) : f r
    f (c:r) = c : f r

readQuery :: [Char] -> [([Char], [Char])]
readQuery s = case break (\c -> c == '&' || c == ';' || c == '=') s of
    (pre,[]) -> [(unescURI pre, "")]
    (pre,'=':post) -> case break (\c -> c == '&' || c == ';') post of
        (rpre,[]) -> [(unescURI pre, unescURI rpre)]
        (rpre,_:post) -> (unescURI pre, unescURI rpre) : readQuery post
    (pre,_:post) -> (unescURI pre, "") : readQuery post

getQuery :: IO [([Char], [Char])]
getQuery = lookupEnv "QUERY_STRING" >>= return . f where
    f Nothing = []
    f (Just string) = readQuery string
