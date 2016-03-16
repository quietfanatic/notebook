function show_html (path) {
    var item_html = $("#item-" + path + " .item-html");
    var show_html = $("#show-html");
    if (item_html.attr("data-raw") == "true") {
        if (!show_html[0].checked) {
            item_html.html(item_html.text());
            item_html.attr("data-raw", "false");
        }
    }
    else {
        if (show_html[0].checked) {
            item_html.text(item_html.html());
            item_html.attr("data-raw", "true");
        }
    }
}
