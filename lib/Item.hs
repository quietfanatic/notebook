module Item where

import Data.Time.Format
import Data.Time.Localtime
import Database.HDBC

type Item =  (Int,  [Char], [Char],       [Char],       Maybe [Char], Maybe [Char], Bool,      Maybe Int)
itemFields = ["id", "path", "created_at", "updated_at", "title",      "html",       "deleted", "prev_id"]
itemFieldsSQL = intercalate ", " itemFields

newItem :: String -> IO Item
newItem path = do
    now <- getZonedTime
    let time = formatTime defaultTimeLocale "%FT%T%z" now
    return (path, time, time, Nothing, Nothing, False, Nothing)

itemFromSQL :: [SqlValue] -> Item
itemFromSQL [sp, sc, su, st, sh, sd, sv] =
    (fromSql sp, fromSql sc, fromSql su, fromSql st, fromSql sh, fromSql sd, fromSql sv)
itemFromSQL _ = error $ "row is wrong length for item"

itemFromQuery :: [([Char], [Char])] -> Either String Item
itemFromQuery query = do
    let getStr name = case lookup name query of
        Just val -> Right val
        Nothing -> Left $ "No " + name + " in parameters."
    path <- getStr "path"
    created_at <- getStr "created_at"
    updated_at <- getStr "updated_at"
    title <- lookup "title" query
    html <- lookup "html" query
    deleted <- case lookup "deleted" query of
        Nothing -> Right False
        Just "" -> Right False
        Just "0" -> Right False
        Just _ -> Right True
    prev_id = case lookup "prev_id" query of
        Nothing -> Left "no prev_id in parameters"
        Just s | all isDigit s -> Right (read s :: Int)
               | otherwise -> Left "prev_id is not an integer"
    return (0, path, created_at, updated_at, title, html, deleted, prev_id)

getItemById db id = do
    st <- prepare db ("SELECT " ++ itemFieldsSQL ++ " FROM items WHERE id = ?")
    execute st [toSql id]
    [r] <- fetchAllRows' st
    return $ itemFromSQL r

getItemByPath db path = do
    st <- prepare db ("SELECT " ++ itemFieldsSQL ++ " FROM items WHERE path = ? ORDER BY updated_at DESC LIMIT 1")
    execute st [toSql path]
    rs <- fetchAllRows' st
    return $ case rs of
        [r] -> Just $ itemFromSQL r
        [] -> Nothing
