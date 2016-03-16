import Prelude hiding (readFile, writeFile, putStrLn)
import System.Environment
import Data.Time.Format
import Data.Time.LocalTime
import Database.HDBC
import Database.HDBC.Sqlite3
import System.IO.UTF8
import Template
import CGI

Just x // _ = x
Nothing // x = x

get_item_html :: Connection -> IO ([Char] -> IO [Char])
get_item_html db = do
    st <- prepare db "SELECT html FROM items WHERE path = ?"
    return $ \p -> do
        execute st [toSql p]
        fetchAllRows' st >>= return . fromSql . head . head

type Item = ([Char], [Char], [Char], Maybe [Char], Maybe [Char], Bool, Maybe Int)
newItem path = do
    now <- getZonedTime
    let time = formatTime defaultTimeLocale "%FT%T%z" now
    return (path, time, time, Nothing, Nothing, False, Nothing)

lookupPath :: Connection -> String -> IO Statement
lookupPath db path = do
    template <- readFile "view/item.html"
    st <- prepare db
        "SELECT path, created_at, updated_at, title, html, deleted, prev_id\n\
        \FROM items WHERE path = ?\n\
        \ORDER BY updated_at DESC LIMIT 1"
    execute st [toSql path]
    return st
lookupID :: Connection -> Int -> IO Statement
lookupID db id = do
    template <- readFile "view/item.html"
    st <- prepare db
        "SELECT path, created_at, updated_at, title, html, deleted, prev_id\n\
        \FROM items WHERE id = ?"
    execute st [toSql id]
    return st

fetchItem :: Statement -> IO Item
fetchItem st = do
    [[sp, sc, su, st, sh, sd, spr]] <- fetchAllRows' st
    return (fromSql sp, fromSql sc, fromSql su, fromSql st, fromSql sh, fromSql sd, fromSql spr)

fillItem :: Item -> Fillings
fillItem (p,c,u,t,h,d,pr) = [
    fill "path" p,
    fill "title" (t // p),
    fillBool "canonical" False,
    fillBool "deleted" d,
    fillBool "not_deleted" (not d),
    fill "created_at" c,
    fill "updated_at" u,
    fillHTML "html" (h // "<p>No content.</p>"),
    fillBool "have_prev" (pr /= Nothing),
    fill "prev" (show (pr // 0)),
    fillList "links" [],
    fillList "linked" []]

main = catchErrorsToHTML $ do
    db <- connectSqlite3 "../db/db.sqlite3"
    req <- lookupEnv "REQUEST_METHOD"
    case req of
        Nothing -> return ()
        Just "GET" -> return ()
    query <- getQuery
    let mpath = lookup "path" query
        mnew = lookup "new" query
        mid = lookup "id" query
    item <- case (mpath, mnew, mid) of
        (Just path, Nothing, Nothing) -> lookupPath db path >>= fetchItem
        (Nothing, Just path, Nothing) -> newItem path
        (Nothing, Nothing, Just id) -> lookupID db (read id) >>= fetchItem
        (Nothing, Nothing, Nothing) -> error "No parameters given."
        _ -> error "Inconsistent query parameters."
    template <- readFile "../view/item.html"
    putStrLn $ "Status: 200 OK"
    putStrLn $ "Content-Type: text/html; charset=UTF-8"
    putStrLn $ ""
    env <- getEnvironment
    sequence $ map (\(k,v)->putStrLn $ "<!-- " ++ k ++ "=" ++ v ++ " -->") env
    putStr $ runTemplate (fillItem item) template




