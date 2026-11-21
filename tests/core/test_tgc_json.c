#include "noshi_tgc_json.h"
#include "test_util.h"

static noshi_json_doc *parse_ok(const char *text) {
    noshi_json_doc *doc = NULL;
    CHECK_EQ_INT(noshi_json_parse(text, strlen(text), &doc), NOSHI_OK);
    CHECK(doc != NULL);
    return doc;
}

static void parse_bad(const char *text, noshi_status want) {
    noshi_json_doc *doc = (noshi_json_doc *)1;
    noshi_status got = noshi_json_parse(text, strlen(text), &doc);
    if (got != want) fprintf(stderr, "  input: %s\n", text);
    CHECK_EQ_INT(got, want);
    CHECK(doc == NULL);
}

static void values_and_lookup(void) {
    noshi_json_doc *doc = parse_ok(
        " {\"@type\":\"NegotiateChannels\",\"exchangeId\":\"123\",\"n\":-42,\"big\":9223372036854775807,\"low\":-9223372036854775808,"
        "\"yes\":true,\"no\":false,\"nothing\":null,\"list\":[1,\"two\",[3],{\"k\":4}],\"obj\":{\"a\":{\"b\":[]}},\"e\":{}}\n ");
    const noshi_json *root = noshi_json_root(doc), *list, *item;
    const char *s;
    size_t len = 0;
    int64_t i = 0;
    int b = 7;
    CHECK_EQ_INT(noshi_json_kind(root), NOSHI_JSON_OBJECT);
    CHECK_EQ_INT(noshi_json_count(root), 11);
    s = noshi_json_string(noshi_json_get(root, "@type"), &len);
    CHECK(s && strcmp(s, "NegotiateChannels") == 0 && len == 17);
    CHECK_EQ_INT(noshi_json_int(noshi_json_get(root, "n"), &i), NOSHI_OK);
    CHECK_EQ_INT(i, -42);
    CHECK_EQ_INT(noshi_json_int(noshi_json_get(root, "big"), &i), NOSHI_OK);
    CHECK(i == INT64_MAX);
    CHECK_EQ_INT(noshi_json_int(noshi_json_get(root, "low"), &i), NOSHI_OK);
    CHECK(i == INT64_MIN);
    CHECK_EQ_INT(noshi_json_bool(noshi_json_get(root, "yes"), &b), NOSHI_OK);
    CHECK_EQ_INT(b, 1);
    CHECK_EQ_INT(noshi_json_bool(noshi_json_get(root, "no"), &b), NOSHI_OK);
    CHECK_EQ_INT(b, 0);
    CHECK_EQ_INT(noshi_json_kind(noshi_json_get(root, "nothing")), NOSHI_JSON_NULL);
    CHECK(noshi_json_get(root, "missing") == NULL);
    CHECK(noshi_json_get(noshi_json_get(root, "list"), "k") == NULL);
    /* kind checks: a string is no number, a number no string */
    CHECK_EQ_INT(noshi_json_int(noshi_json_get(root, "exchangeId"), &i), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(i, 0);
    CHECK(noshi_json_string(noshi_json_get(root, "n"), &len) == NULL);
    CHECK_EQ_INT(noshi_json_bool(noshi_json_get(root, "n"), &b), NOSHI_E_MALFORMED);
    list = noshi_json_get(root, "list");
    CHECK_EQ_INT(noshi_json_count(list), 4);
    item = noshi_json_first(list);
    CHECK_EQ_INT(noshi_json_int(item, &i), NOSHI_OK);
    CHECK_EQ_INT(i, 1);
    item = noshi_json_next(item);
    CHECK(strcmp(noshi_json_string(item, &len), "two") == 0);
    item = noshi_json_next(item);
    CHECK_EQ_INT(noshi_json_kind(item), NOSHI_JSON_ARRAY);
    CHECK(noshi_json_key(item) == NULL);
    item = noshi_json_next(item);
    CHECK_EQ_INT(noshi_json_kind(item), NOSHI_JSON_OBJECT);
    CHECK(noshi_json_next(item) == NULL);
    CHECK(noshi_json_first(noshi_json_get(root, "e")) == NULL);
    /* members come back in document order with their keys */
    item = noshi_json_first(root);
    CHECK(strcmp(noshi_json_key(item), "@type") == 0);
    CHECK(strcmp(noshi_json_key(noshi_json_next(item)), "exchangeId") == 0);
    noshi_json_free(doc);
    /* null handling of every accessor */
    CHECK(noshi_json_root(NULL) == NULL);
    CHECK_EQ_INT(noshi_json_kind(NULL), NOSHI_JSON_NULL);
    CHECK(noshi_json_get(NULL, "a") == NULL);
    CHECK(noshi_json_first(NULL) == NULL && noshi_json_next(NULL) == NULL);
    CHECK_EQ_INT(noshi_json_count(NULL), 0);
    CHECK(noshi_json_key(NULL) == NULL);
    noshi_json_free(NULL);
}

static void bare_values_and_duplicates(void) {
    noshi_json_doc *doc = parse_ok("\"just text\"");
    size_t len;
    CHECK(strcmp(noshi_json_string(noshi_json_root(doc), &len), "just text") == 0);
    noshi_json_free(doc);
    doc = parse_ok("17");
    {
        int64_t i;
        CHECK_EQ_INT(noshi_json_int(noshi_json_root(doc), &i), NOSHI_OK);
        CHECK_EQ_INT(i, 17);
    }
    noshi_json_free(doc);
    /* the last of two members with one key wins, as in the std::map of json11 */
    doc = parse_ok("{\"a\":1,\"a\":2}");
    {
        int64_t i;
        CHECK_EQ_INT(noshi_json_int(noshi_json_get(noshi_json_root(doc), "a"), &i), NOSHI_OK);
        CHECK_EQ_INT(i, 2);
        CHECK_EQ_INT(noshi_json_count(noshi_json_root(doc)), 2);
    }
    noshi_json_free(doc);
}

static void numbers(void) {
    static const struct { const char *text; int is_int; long long value; } cases[] = {
        {"0", 1, 0}, {"-0", 1, 0}, {"7", 1, 7}, {"-7", 1, -7}, {"1234567890123", 1, 1234567890123LL},
        {"1.5", 0, 0}, {"1e3", 0, 0}, {"1E+3", 0, 0}, {"-2.5e-2", 0, 0}, {"0.0", 0, 0},
        {"9223372036854775808", 0, 0}, {"-9223372036854775809", 0, 0}, {"99999999999999999999999999", 0, 0},
        {"1234567890123456789012345678901234567890", 0, 0}
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        noshi_json_doc *doc = parse_ok(cases[i].text);
        int64_t v = 0;
        noshi_status s = noshi_json_int(noshi_json_root(doc), &v);
        CHECK_EQ_INT(noshi_json_kind(noshi_json_root(doc)), NOSHI_JSON_NUMBER);
        if (cases[i].is_int) {
            CHECK_EQ_INT(s, NOSHI_OK);
            CHECK_EQ_INT(v, cases[i].value);
        } else {
            CHECK_EQ_INT(s, NOSHI_E_MALFORMED);
        }
        noshi_json_free(doc);
    }
    parse_bad("01", NOSHI_E_MALFORMED);
    parse_bad("-", NOSHI_E_MALFORMED);
    parse_bad("+1", NOSHI_E_MALFORMED);
    parse_bad(".5", NOSHI_E_MALFORMED);
    parse_bad("1.", NOSHI_E_MALFORMED);
    parse_bad("1e", NOSHI_E_MALFORMED);
    parse_bad("1e+", NOSHI_E_MALFORMED);
    parse_bad("0x10", NOSHI_E_MALFORMED);
    parse_bad("1 2", NOSHI_E_MALFORMED);
    parse_bad("NaN", NOSHI_E_MALFORMED);
    parse_bad("Infinity", NOSHI_E_MALFORMED);
}

static void strings(void) {
    noshi_json_doc *doc = parse_ok("[\"a\\\"b\\\\c\\/d\\b\\f\\n\\r\\t\",\"\\u0041\\u00e9\\u20ac\\ud83d\\ude00\",\"caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80\",\"\"]");
    const noshi_json *item = noshi_json_first(noshi_json_root(doc));
    size_t len = 0;
    const char *s = noshi_json_string(item, &len);
    CHECK(strcmp(s, "a\"b\\c/d\b\f\n\r\t") == 0);
    item = noshi_json_next(item);
    s = noshi_json_string(item, &len);
    CHECK(strcmp(s, "A\xC3\xA9\xE2\x82\xAC\xF0\x9F\x98\x80") == 0);
    CHECK_EQ_INT(len, 1 + 2 + 3 + 4);
    item = noshi_json_next(item);
    CHECK(strcmp(noshi_json_string(item, &len), "caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80") == 0);
    item = noshi_json_next(item);
    CHECK(noshi_json_string(item, &len) != NULL);
    CHECK_EQ_INT(len, 0);
    noshi_json_free(doc);

    parse_bad("\"unterminated", NOSHI_E_MALFORMED);
    parse_bad("\"bad \\x escape\"", NOSHI_E_MALFORMED);
    parse_bad("\"tab\there\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\u12\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\u12g4\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\u0000\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\ud800\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\ud800\\u0041\"", NOSHI_E_MALFORMED);
    parse_bad("\"\\udc00\"", NOSHI_E_MALFORMED);
    /* invalid UTF-8: a lone continuation byte, a truncated sequence, an overlong form, a surrogate, past U+10FFFF */
    parse_bad("\"\x80\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xC3\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xC0\xAF\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xE0\x80\xAF\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xED\xA0\x80\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xF4\x90\x80\x80\"", NOSHI_E_MALFORMED);
    parse_bad("\"\xFF\"", NOSHI_E_MALFORMED);
    /* a NUL byte inside the text */
    {
        noshi_json_doc *bad = (noshi_json_doc *)1;
        const char text[] = "\"a\0b\"";
        CHECK_EQ_INT(noshi_json_parse(text, sizeof(text) - 1, &bad), NOSHI_E_MALFORMED);
        CHECK(bad == NULL);
    }
}

static void structure(void) {
    parse_bad("", NOSHI_E_MALFORMED);
    parse_bad("   ", NOSHI_E_MALFORMED);
    parse_bad("{", NOSHI_E_MALFORMED);
    parse_bad("}", NOSHI_E_MALFORMED);
    parse_bad("[", NOSHI_E_MALFORMED);
    parse_bad("[1,]", NOSHI_E_MALFORMED);
    parse_bad("[,1]", NOSHI_E_MALFORMED);
    parse_bad("[1 2]", NOSHI_E_MALFORMED);
    parse_bad("{\"a\"}", NOSHI_E_MALFORMED);
    parse_bad("{\"a\":}", NOSHI_E_MALFORMED);
    parse_bad("{\"a\":1,}", NOSHI_E_MALFORMED);
    parse_bad("{a:1}", NOSHI_E_MALFORMED);
    parse_bad("{\"a\" 1}", NOSHI_E_MALFORMED);
    parse_bad("{1:2}", NOSHI_E_MALFORMED);
    parse_bad("[1}", NOSHI_E_MALFORMED);
    parse_bad("{\"a\":1]", NOSHI_E_MALFORMED);
    parse_bad("tru", NOSHI_E_MALFORMED);
    parse_bad("truex", NOSHI_E_MALFORMED);
    parse_bad("nul", NOSHI_E_MALFORMED);
    parse_bad("fals", NOSHI_E_MALFORMED);
    parse_bad("{} {}", NOSHI_E_MALFORMED);
    parse_bad("[] x", NOSHI_E_MALFORMED);
    parse_bad("// c\n{}", NOSHI_E_MALFORMED);
}

static void limits(void) {
    char text[NOSHI_JSON_MAX_TEXT + 2];
    size_t i, n;
    noshi_json_doc *doc = NULL;
    /* depth: 12 levels pass, 13 do not */
    for (i = 0; i < 12; ++i) text[i] = '[';
    for (i = 0; i < 12; ++i) text[12 + i] = ']';
    text[24] = '\0';
    doc = parse_ok(text);
    noshi_json_free(doc);
    for (i = 0; i < 13; ++i) text[i] = '[';
    for (i = 0; i < 13; ++i) text[13 + i] = ']';
    text[26] = '\0';
    parse_bad(text, NOSHI_E_LIMIT);
    /* a very deep document must not run the stack out: the parser refuses it at the cap */
    memset(text, '[', 60000);
    text[60000] = '\0';
    parse_bad(text, NOSHI_E_LIMIT);
    /* the text size */
    memset(text, ' ', sizeof(text));
    text[0] = '1';
    CHECK_EQ_INT(noshi_json_parse(text, NOSHI_JSON_MAX_TEXT, &doc), NOSHI_OK);
    noshi_json_free(doc);
    CHECK_EQ_INT(noshi_json_parse(text, NOSHI_JSON_MAX_TEXT + 1, &doc), NOSHI_E_LIMIT);
    CHECK(doc == NULL);
    /* the number of values: an array of 4095 ones is the root and 4095 children, one more is too many */
    n = 0;
    text[n++] = '[';
    for (i = 0; i < 4095; ++i) {
        if (i) text[n++] = ',';
        text[n++] = '1';
    }
    text[n++] = ']';
    text[n] = '\0';
    doc = parse_ok(text);
    CHECK_EQ_INT(noshi_json_count(noshi_json_root(doc)), 4095);
    noshi_json_free(doc);
    n = 0;
    text[n++] = '[';
    for (i = 0; i < 4096; ++i) {
        if (i) text[n++] = ',';
        text[n++] = '1';
    }
    text[n++] = ']';
    text[n] = '\0';
    parse_bad(text, NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_json_parse(NULL, 5, &doc), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_json_parse("1", 1, NULL), NOSHI_E_ARG);
}

static void writer(void) {
    char buf[256];
    noshi_json_out o;
    size_t len = 0;
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_object(&o);
    noshi_json_out_key(&o, "@type");
    noshi_json_out_string(&o, "InitialSetup");
    noshi_json_out_key(&o, "renomination");
    noshi_json_out_bool(&o, 1);
    noshi_json_out_key(&o, "list");
    noshi_json_out_array(&o);
    noshi_json_out_int(&o, -5);
    noshi_json_out_string(&o, "a\"b\\c\n\x01");
    noshi_json_out_object(&o);
    noshi_json_out_end(&o);
    noshi_json_out_array(&o);
    noshi_json_out_end(&o);
    noshi_json_out_end(&o);
    noshi_json_out_key(&o, "n");
    noshi_json_out_int(&o, 9223372036854775807LL);
    noshi_json_out_end(&o);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_OK);
    CHECK(strcmp(buf, "{\"@type\":\"InitialSetup\",\"renomination\":true,\"list\":[-5,\"a\\\"b\\\\c\\n\\u0001\",{},[]],\"n\":9223372036854775807}") == 0);
    CHECK_EQ_INT(len, strlen(buf));
    /* what the writer makes the reader takes back */
    {
        noshi_json_doc *doc = parse_ok(buf);
        const char *s = noshi_json_string(noshi_json_first(noshi_json_get(noshi_json_root(doc), "list")), &len);
        CHECK(s == NULL);
        CHECK_EQ_INT(noshi_json_count(noshi_json_get(noshi_json_root(doc), "list")), 4);
        noshi_json_free(doc);
    }
    /* misuse sticks */
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_object(&o);
    noshi_json_out_string(&o, "value with no key");
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_array(&o);
    noshi_json_out_key(&o, "k");
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_object(&o);
    noshi_json_out_key(&o, "k");
    noshi_json_out_end(&o);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_end(&o);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_int(&o, 1);
    noshi_json_out_int(&o, 2);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    /* unfinished and empty */
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_array(&o);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    noshi_json_out_init(&o, buf, sizeof(buf));
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_STATE);
    /* a buffer that is too small, to the byte */
    noshi_json_out_init(&o, buf, 8);
    noshi_json_out_string(&o, "abcdef");
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_LIMIT);
    noshi_json_out_init(&o, buf, 9);
    noshi_json_out_string(&o, "abcdef");
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_OK);
    CHECK_EQ_INT(len, 8);
    noshi_json_out_init(&o, NULL, 9);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_ARG);
    noshi_json_out_init(&o, buf, 1);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_ARG);
    /* nesting of the writer is bounded too */
    noshi_json_out_init(&o, buf, sizeof(buf));
    {
        int i;
        for (i = 0; i < 13; ++i) noshi_json_out_array(&o);
    }
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_LIMIT);
    noshi_json_out_init(&o, buf, sizeof(buf));
    noshi_json_out_string(&o, NULL);
    CHECK_EQ_INT(noshi_json_out_finish(&o, &len), NOSHI_E_ARG);
}

int main(void) {
    values_and_lookup();
    bare_values_and_duplicates();
    numbers();
    strings();
    structure();
    limits();
    writer();
    return test_finish("test_tgc_json");
}
