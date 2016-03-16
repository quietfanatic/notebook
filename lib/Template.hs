module Template where
import Data.Char

data FillItem = FIStr [Char]
              | FIHTML [Char]
              | FIList [Fillings]
              | FIBool Bool
              deriving (Show)
type Fillings = [([Char], FillItem)]
fillType x = case x of
    FIStr _ -> "string"
    FIHTML _ -> "html"
    FIList _ -> "list"
    FIBool _ -> "bool"

data TemplateItem = TILit [Char]
                  | TIStr [Char]
                  | TIHTML [Char]
                  | TICond [Char] [TemplateItem]
                  | TIList [Char] [TemplateItem]
                  deriving (Show)
type Template = [TemplateItem]

escHTML :: [Char] -> [Char]
escHTML = concatMap f where
    f '<' = "&lt;"
    f '>' = "&gt;"
    f '"' = "&quot;"
    f '&' = "&ampl;"
    f c = [c]

compileTemplate :: [Char] -> Template
compileTemplate = fst . f 0 where
    f :: Int -> [Char] -> (Template, [Char])
    f i s = case break (\c -> c == '{' || c == '}') s of
        (pre,[]) | i == 0 -> (TILit pre:[],[])
                 | otherwise -> error $ "Unterminated list template directive"
        (pre,'}':post) | i == 0 -> error $ "Extra }"
                       | otherwise -> (TILit pre:[],post)
        (pre,'{':post) -> case break (\c -> isSpace c || c == '}') post of
            (item,[]) -> error $ "Unterminated template directive"
            (item,'}':post) -> (TILit pre : this_item : nextres, nextpost) where
                (nextres, nextpost) = f i post
                this_item = case item of
                    '!':itemr -> TIHTML itemr
                    _ -> TIStr item
            (item,_:post) -> (TILit pre : this_item : nextres, nextpost) where
                this_item = case item of
                    '?':itemr -> TICond itemr innerres
                    _ -> TIList item innerres
                (innerres, innerpost) = f (i+1) post
                (nextres, nextpost) = f i innerpost

fillTemplate :: Fillings -> Template -> [Char]
fillTemplate fs = foldl (++) "" . map fillItem where
    fillItem (TILit str) = str
    fillItem (TIStr item) = case lookup item fs of
        Just (FIStr str) -> escHTML str
        Just other -> error $ "Expected string filling for " ++ item ++ " but got " ++ fillType other
        Nothing -> error $ "Unfilled template directive " ++ item
    fillItem (TIHTML item) = case lookup item fs of
        Just (FIHTML str) -> str
        Just other -> error $ "Expected html filling for " ++ item ++ " but got " ++ fillType other
        Nothing -> error $ "Unfilled template directive " ++ item
    fillItem (TICond item inner) = case lookup item fs of
        Just (FIBool bool) -> if bool then fillTemplate fs inner else ""
        Just other -> error $ "Expected bool filling for " ++ item ++ " but got " ++ fillType other
        Nothing -> error $ "Unfilled conditional template directive " ++ item
    fillItem (TIList item inner) = case lookup item fs of
        Just (FIList list) -> foldl (++) "" (map (flip fillTemplate inner) list)
        Just other -> error $ "Expected list filling for " ++ item ++ " but got " ++ fillType other
        Nothing -> error $ "Unfilled list template directive " ++ item

fill item str = (item, FIStr str)
fillHTML item str = (item, FIHTML str)
fillBool item bool = (item, FIBool bool)
fillList item list = (item, FIList list)

runTemplate fs = fillTemplate fs . compileTemplate

