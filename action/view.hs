import Prelude hiding (readFile, writeFile, putStrLn)
import System.Environment
import Database.HDBC
import Database.HDBC.Sqlite3
import System.IO.UTF8
import CGI
import Item
import Stuff
import Template

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
    putStr $ runTemplate (fillItem item) template




