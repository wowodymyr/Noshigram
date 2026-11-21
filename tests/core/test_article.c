#include "test_util.h"
#include "noshi_article.h"

static void check_html(const char *input, const char *expected) {
    uint8_t output[4096];
    size_t written = 0;
    size_t length = strlen(input);
    CHECK_EQ_INT(noshi_article_readonly((const uint8_t *)input, length, output, sizeof(output), &written), NOSHI_OK);
    CHECK_EQ_INT(written, strlen(expected));
    CHECK(!memcmp(output, expected, written));
}

int main(void) {
    uint8_t output[64];
    size_t written = 99;
    check_html("<h1>title</h1><article><p>text</p></article><script src='/quill.js'></script><script>document.body.innerHTML='';</script>",
               "<h1>title</h1><article><p>text</p></article>");
    check_html("<SCRIPT type='text/javascript' data-x='>'>x</ScRiPt ><p>kept</p>", "<p>kept</p>");
    check_html("<!-- <script>x</script> --><p title='<script>'>a &lt; b</p><style>x:before{content:'<script>'}</style>",
               "<!-- <script>x</script> --><p title='<script>'>a &lt; b</p><style>x:before{content:'<script>'}</style>");
    check_html("<textarea><script>words</script></textarea><title><script>title</script></title><scripture>keep</scripture>",
               "<textarea><script>words</script></textarea><title><script>title</script></title><scripture>keep</scripture>");
    check_html("<p>текст <a href='https://example.com'>link</a><img src='/file.jpg'></p>",
               "<p>текст <a href='https://example.com'>link</a><img src='/file.jpg'></p>");
    check_html("", "");
    CHECK_EQ_INT(noshi_article_readonly((const uint8_t *)"<script>x", 9, output, sizeof(output), &written), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(written, 0);
    CHECK_EQ_INT(noshi_article_readonly((const uint8_t *)"<script src='x", 14, output, sizeof(output), &written), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(written, 0);
    CHECK_EQ_INT(noshi_article_readonly((const uint8_t *)"hello", 5, output, 4, &written), NOSHI_E_LIMIT);
    CHECK_EQ_INT(written, 0);
    CHECK_EQ_INT(noshi_article_readonly(NULL, 1, output, sizeof(output), &written), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_article_readonly((const uint8_t *)"x", 1, output, sizeof(output), NULL), NOSHI_E_ARG);
    return test_finish("test_article");
}
