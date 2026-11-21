#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include "noshi_update.h"
#include "test_util.h"
#include "zip_fixture.h"

static char g_dir[64];

static void path_of(char *out, size_t cap, const char *a, const char *b) {
    snprintf(out, cap, "%s/%s%s%s", g_dir, a, b[0] ? "/" : "", b);
}

static void put(const char *dir, const char *name, const char *text) {
    char path[256];
    path_of(path, sizeof(path), dir, name);
    CHECK(fx_write(path, (const uint8_t *)text, strlen(text)));
}

static int has_text(const char *dir, const char *name, const char *text) {
    char path[256], buf[256];
    FILE *f;
    size_t got;
    path_of(path, sizeof(path), dir, name);
    f = fopen(path, "rb");
    if (!f) return 0;
    got = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[got] = 0;
    return !strcmp(buf, text);
}

static int exists(const char *dir, const char *name) {
    char path[256];
    path_of(path, sizeof(path), dir, name);
    return access(path, F_OK) == 0;
}

/* an installed app: a program, a plist, a resource that stays and one that changes */
static void install_old(void) {
    char path[256], cmd[320];
    path_of(path, sizeof(path), "App", "");
    snprintf(cmd, sizeof(cmd), "rm -rf %s", path);
    CHECK_EQ_INT(system(cmd), 0);
    CHECK_EQ_INT(mkdir(path, 0755), 0);
    put("App", "Noshigram", "old program");
    put("App", "Info.plist", "old plist");
    put("App", "keep.png", "same bytes");
    put("App", "change.png", "old picture");
    put("App", "stale.txt", "not in the new ipa");
    path_of(path, sizeof(path), "App", "Noshigram");
    CHECK_EQ_INT(chmod(path, 0755), 0);
}

static void write_ipa(const char *name, const fx_entry *e, size_t count) {
    char path[256];
    path_of(path, sizeof(path), name, "");
    CHECK(fx_write_zip(path, e, count));
}

#define E(n, d) {n, (const uint8_t *)d, sizeof(d) - 1, 1, 0, 0, 0, 0, 0, 0}
#define EX(n, d) {n, (const uint8_t *)d, sizeof(d) - 1, 1, 0755, 0, 0, 0, 0, 0}

static noshi_status apply(const char *ipa, noshi_update_progress progress, void *ctx) {
    char ipa_path[256], bundle[256];
    path_of(ipa_path, sizeof(ipa_path), ipa, "");
    path_of(bundle, sizeof(bundle), "App", "");
    return noshi_update_apply(ipa_path, bundle, "Noshigram.app", "Noshigram", progress, ctx);
}

typedef struct seen { uint64_t last[3]; uint64_t total[3]; int calls[3]; int ordered; int stop_in_stage; } seen;

static noshi_status watch(void *ctx, noshi_update_phase phase, uint64_t done, uint64_t total) {
    seen *s = (seen *)ctx;
    if (done < s->last[phase] || done > total) s->ordered = 0;
    s->last[phase] = done;
    s->total[phase] = total;
    ++s->calls[phase];
    return s->stop_in_stage && phase == NOSHI_UPDATE_STAGE ? NOSHI_E_RETRY : NOSHI_OK;
}

static void good_update(void) {
    fx_entry e[] = {
        {"Payload/", NULL, 0, 0, 0, 0, 0, 0, 0, 0},
        {"Payload/Noshigram.app/", NULL, 0, 0, 0, 0, 0, 0, 0, 0},
        EX("Payload/Noshigram.app/Noshigram", "new program"),
        E("Payload/Noshigram.app/Info.plist", "new plist"),
        E("Payload/Noshigram.app/keep.png", "same bytes"),
        E("Payload/Noshigram.app/change.png", "new picture!"),
        E("Payload/Noshigram.app/fresh/deep/added.txt", "added")
    };
    char kept[256];
    struct stat before, after, st;
    seen s;
    memset(&s, 0, sizeof(s));
    s.ordered = 1;
    install_old();
    write_ipa("good.ipa", e, 7);
    path_of(kept, sizeof(kept), "App", "keep.png");
    CHECK_EQ_INT(stat(kept, &before), 0);
    CHECK_EQ_INT(apply("good.ipa", watch, &s), NOSHI_OK);
    CHECK(has_text("App", "Noshigram", "new program"));
    CHECK(has_text("App", "Info.plist", "new plist"));
    CHECK(has_text("App", "change.png", "new picture!"));
    CHECK(has_text("App", "fresh/deep/added.txt", "added"));
    CHECK(has_text("App", "keep.png", "same bytes"));
    CHECK(has_text("App", "stale.txt", "not in the new ipa"));
    CHECK(!exists("App", ".update"));
    /* the unchanged file was not rewritten */
    CHECK_EQ_INT(stat(kept, &after), 0);
    CHECK(before.st_ino == after.st_ino);
    path_of(kept, sizeof(kept), "App", "Noshigram");
    CHECK_EQ_INT(stat(kept, &st), 0);
    CHECK_EQ_INT(st.st_mode & 0777, 0755);
    path_of(kept, sizeof(kept), "App", "change.png");
    CHECK_EQ_INT(stat(kept, &st), 0);
    CHECK_EQ_INT(st.st_mode & 0777, 0644);
    CHECK(s.ordered);
    CHECK(s.calls[NOSHI_UPDATE_COMPARE] >= 5 && s.calls[NOSHI_UPDATE_STAGE] >= 4 && s.calls[NOSHI_UPDATE_COMMIT] == 4);
    CHECK_EQ_INT(s.last[NOSHI_UPDATE_COMMIT], 4);
    CHECK_EQ_INT(s.last[NOSHI_UPDATE_STAGE], s.total[NOSHI_UPDATE_STAGE]);
    CHECK_EQ_INT(s.total[NOSHI_UPDATE_STAGE], sizeof("new program") - 1 + sizeof("new plist") - 1 + sizeof("new picture!") - 1 + sizeof("added") - 1);
    /* the same ipa again has nothing to change */
    memset(&s, 0, sizeof(s));
    s.ordered = 1;
    CHECK_EQ_INT(apply("good.ipa", watch, &s), NOSHI_OK);
    CHECK_EQ_INT(s.total[NOSHI_UPDATE_STAGE], 0);
    CHECK_EQ_INT(s.calls[NOSHI_UPDATE_COMMIT], 0);
    CHECK(!exists("App", ".update"));
}

static int untouched(void) {
    return has_text("App", "Noshigram", "old program") && has_text("App", "Info.plist", "old plist") && has_text("App", "change.png", "old picture") &&
           !exists("App", ".update");
}

static void refused_before_any_move(void) {
    static const uint8_t pic[] = "new picture!";
    seen s;
    {
        /* the second changed file is damaged: nothing may reach the bundle, not even the first */
        fx_entry e[] = {
            EX("Payload/Noshigram.app/Noshigram", "new program"),
            E("Payload/Noshigram.app/Info.plist", "new plist"),
            {"Payload/Noshigram.app/change.png", pic, sizeof(pic) - 1, 1, 0, 0, 1, 0, 0, 0}
        };
        install_old();
        write_ipa("badcrc.ipa", e, 3);
        CHECK_EQ_INT(apply("badcrc.ipa", NULL, NULL), NOSHI_E_MALFORMED);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/change.png", "new picture!")};
        install_old();
        write_ipa("noplist.ipa", e, 2);
        CHECK_EQ_INT(apply("noplist.ipa", NULL, NULL), NOSHI_E_MALFORMED);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {E("Payload/Noshigram.app/Info.plist", "new plist"), E("Payload/Noshigram.app/change.png", "new picture!")};
        install_old();
        write_ipa("noexec.ipa", e, 2);
        CHECK_EQ_INT(apply("noexec.ipa", NULL, NULL), NOSHI_E_MALFORMED);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/Info.plist", "new plist"), E("Other/file", "x")};
        install_old();
        write_ipa("elsewhere.ipa", e, 3);
        CHECK_EQ_INT(apply("elsewhere.ipa", NULL, NULL), NOSHI_E_UNSUPPORTED);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/Info.plist", "new plist"),
                        E("Payload/Noshigram.app/.update/x", "x")};
        install_old();
        write_ipa("reserved.ipa", e, 3);
        CHECK_EQ_INT(apply("reserved.ipa", NULL, NULL), NOSHI_E_MALFORMED);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/Info.plist", "new plist"),
                        E("Payload/Noshigram.app/change.png", "new picture!")};
        install_old();
        write_ipa("stop.ipa", e, 3);
        memset(&s, 0, sizeof(s));
        s.ordered = 1;
        s.stop_in_stage = 1;
        CHECK_EQ_INT(apply("stop.ipa", watch, &s), NOSHI_E_RETRY);
        CHECK(untouched());
        CHECK_EQ_INT(s.calls[NOSHI_UPDATE_COMMIT], 0);
    }
    {
        /* a stage left by an update that died is cleared, and a file in the way of a folder is refused */
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/Info.plist", "new plist"),
                        E("Payload/Noshigram.app/stale.txt/inner", "x")};
        install_old();
        write_ipa("blocked.ipa", e, 3);
        CHECK_EQ_INT(apply("blocked.ipa", NULL, NULL), NOSHI_E_STATE);
        CHECK(untouched());
    }
    {
        fx_entry e[] = {EX("Payload/Noshigram.app/Noshigram", "new program"), E("Payload/Noshigram.app/Info.plist", "new plist")};
        char junk[256], leftover[256];
        install_old();
        path_of(junk, sizeof(junk), "App", ".update");
        CHECK_EQ_INT(mkdir(junk, 0755), 0);
        put("App/.update", "Noshigram", "half written");
        path_of(leftover, sizeof(leftover), "App/.update", "dir");
        CHECK_EQ_INT(mkdir(leftover, 0755), 0);
        write_ipa("clean.ipa", e, 2);
        CHECK_EQ_INT(apply("clean.ipa", NULL, NULL), NOSHI_OK);
        CHECK(has_text("App", "Noshigram", "new program"));
        CHECK(!exists("App", ".update"));
    }
}

static void bad_arguments(void) {
    char ipa[256], bundle[256], absent[256];
    path_of(ipa, sizeof(ipa), "good.ipa", "");
    path_of(bundle, sizeof(bundle), "App", "");
    path_of(absent, sizeof(absent), "no-such-bundle", "");
    CHECK_EQ_INT(noshi_update_apply(NULL, bundle, "Noshigram.app", "Noshigram", NULL, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_update_apply(ipa, bundle, "a/b", "Noshigram", NULL, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_update_apply(ipa, bundle, "Noshigram.app", "../Noshigram", NULL, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_update_apply(ipa, bundle, "", "Noshigram", NULL, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_update_apply(ipa, absent, "Noshigram.app", "Noshigram", NULL, NULL), NOSHI_E_STATE);
    {
        char missing[256];
        path_of(missing, sizeof(missing), "missing.ipa", "");
        CHECK_EQ_INT(noshi_update_apply(missing, bundle, "Noshigram.app", "Noshigram", NULL, NULL), NOSHI_E_NOTFOUND);
    }
    if (geteuid() != 0) {
        /* a bundle the process cannot write is the state of an app installed by root */
        CHECK_EQ_INT(chmod(bundle, 0555), 0);
        CHECK_EQ_INT(noshi_update_apply(ipa, bundle, "Noshigram.app", "Noshigram", NULL, NULL), NOSHI_E_STATE);
        CHECK_EQ_INT(chmod(bundle, 0755), 0);
    }
}

int main(void) {
    snprintf(g_dir, sizeof(g_dir), "/tmp/noshigram-update-XXXXXX");
    if (!mkdtemp(g_dir)) {
        perror("mkdtemp");
        return 2;
    }
    good_update();
    refused_before_any_move();
    bad_arguments();
    {
        char cmd[96];
        snprintf(cmd, sizeof(cmd), "rm -rf %s", g_dir);
        if (system(cmd) != 0) fprintf(stderr, "could not remove %s\n", g_dir);
    }
    return test_finish("test_update");
}
