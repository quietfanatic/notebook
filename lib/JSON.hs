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


type Parser a = String -> (Int, Int) -> Either String (String, (Int, Int), a)
instance Monad Parser where
    return v s lc = Right (s, lc, v)
    (k >>= f) s lc = case k s lc of
        Left err -> err
        Right (s', lc', v) => f v s' lc'
    fail err = Left err

readJSON str = let
    get :: Parser Char
    get ('\n':r) (l,c) = Right (r, (l+1, 1), '\n')
    get (ch:r) (l,c) = Right (r, (l, c+1), ch)
    while :: (Char -> Bool) -> Parser String
    while f = get >>= \c -> if f c then while f >>= return . (c:) else return []
    ws :: Parser ()
    ws = while isSpace >> return ()
    string_i acc = do
        part <- while (\c -> c /= '\\' && c /= '"')
        (\s lc -> case s of
            '"' -> (s, lc, part ++ acc)
            
    value s lc = case s of
        '"' -> do while (\c -> c /= '\\' && c /= '"')




readJSON = fst . top where
    ws s = case s of
        c:rest | isSpace(c) -> rest
    top s = case value s of
        Left err -> Left err
        Right (v, rest) | all isspace(rest) -> Right v
                        | otherwise -> Left "Extra stuff after value"
    value s = case s of
        [] -> Left "Expected value but got EOF"
        'n':'u':'l':'l':rest -> Right (JSNull, rest)
        't':'r':'u':'e':rest -> Right (JSBool True, rest)
        'f':'a':'l':'s':'e':rest -> Right (JSBool False, rest)
        '"':rest -> case reads rest :: String of
            [] -> Left "Malformed string"
            [(s,rest)] -> Right (s, rest)
        '[':rest -> array rest
        '{':rest -> object rest
        digit:rest | iSDigit(digit) -> number rest
        space:rest | isSpace(space) -> value rest
        _ -> Left "Syntax error"
    array s = case s of
        ']':rest -> Right (JSArray [], rest)
        _ -> case value s of
            Left err -> Left err
            Right (v, rest) -> 
