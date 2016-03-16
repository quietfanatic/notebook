module JSON where

data JSON = JSNull
          | JSBool Bool
          | JSNumber Double
          | JSString [Char]
          | JSArray [JSON]
          | JSObject [([Char], JSON)]

showJSON v = case v of
    JSNull -> "null"
    JSBool True -> "true"
    JSBool False -> "false"
    JSNumber n -> show n  -- Is this right?  Close enough.
    JSString s -> show s  -- I know this isn't right, haha
    JSArray a -> "[" ++ intercalate "," (map showJSON a) ++ "]"
    JSObject o -> "{" ++ intercalate "," (map showPair a) ++ "]"
        where showPair (s, v) = show s ++ ":" ++ showJSON v

readJSON = fst . f where
    f v = case v of
        [] -> (Left "Expected value but got EOF",[])
        'n':'u':'l':'l':rest -> (Right JSNull,[]
