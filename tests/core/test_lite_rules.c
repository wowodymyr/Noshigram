#include "test_util.h"
#include "noshi_lite_rules.h"

static void test_presets(void) {
    /* the numbers writes beside its presets */
    CHECK_EQ_INT(noshi_lite_default_value(NOSHI_LITE_CLASS_LOW), 198687);
    CHECK_EQ_INT(noshi_lite_default_value(NOSHI_LITE_CLASS_AVERAGE), 204383);
    CHECK_EQ_INT(noshi_lite_default_value(NOSHI_LITE_CLASS_HIGH), 262143);
    CHECK_EQ_INT(noshi_lite_default_value((noshi_lite_class)9), 262143);
}

static void test_class(void) {
    const uint64_t mb = 1024ull * 1024;
    CHECK_EQ_INT(noshi_lite_measure_class(512 * mb, 2), NOSHI_LITE_CLASS_LOW);
    CHECK_EQ_INT(noshi_lite_measure_class(4096 * mb, 1), NOSHI_LITE_CLASS_LOW);
    CHECK_EQ_INT(noshi_lite_measure_class(0, 0), NOSHI_LITE_CLASS_LOW);
    CHECK_EQ_INT(noshi_lite_measure_class(513 * mb, 2), NOSHI_LITE_CLASS_AVERAGE);
    CHECK_EQ_INT(noshi_lite_measure_class(1024 * mb, 2), NOSHI_LITE_CLASS_AVERAGE);
    CHECK_EQ_INT(noshi_lite_measure_class(1025 * mb, 2), NOSHI_LITE_CLASS_HIGH);
    CHECK_EQ_INT(noshi_lite_measure_class(4096 * mb, 6), NOSHI_LITE_CLASS_HIGH);
}

static void test_account_bits(void) {
    CHECK_EQ_INT(noshi_lite_for_account(NOSHI_LITE_EMOJI_CHAT, 1), NOSHI_LITE_EMOJI_CHAT_PREMIUM);
    CHECK_EQ_INT(noshi_lite_for_account(NOSHI_LITE_EMOJI_CHAT, 0), NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM);
    CHECK_EQ_INT(noshi_lite_for_account(NOSHI_LITE_EMOJI_CHAT_PREMIUM, 0), NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM);
    /* a flag with no pair, and a mask of both kinds, keep what is not an emoji flag */
    CHECK_EQ_INT(noshi_lite_for_account(NOSHI_LITE_STICKERS_CHAT, 1), NOSHI_LITE_STICKERS_CHAT);
    CHECK_EQ_INT(noshi_lite_for_account(NOSHI_LITE_STICKERS_CHAT | NOSHI_LITE_EMOJI_CHAT, 1), NOSHI_LITE_STICKERS_CHAT | NOSHI_LITE_EMOJI_CHAT_PREMIUM);
}

static void test_enabled(void) {
    uint32_t low = noshi_lite_default_value(NOSHI_LITE_CLASS_LOW), high = noshi_lite_default_value(NOSHI_LITE_CLASS_HIGH);
    /* the animated stickers run on the low preset, in the chat and in the keyboard; what is heavier stays off */
    CHECK(noshi_lite_enabled(low, 0, NOSHI_LITE_STICKERS_CHAT, 0));
    CHECK(noshi_lite_enabled(low, 0, NOSHI_LITE_STICKERS_KEYBOARD, 0));
    /* the panel of stickers has no switch of its own and follows the one of the chat, whatever its own bit says */
    CHECK(noshi_lite_enabled(NOSHI_LITE_STICKERS_CHAT, 0, NOSHI_LITE_STICKERS_KEYBOARD, 0));
    CHECK(!noshi_lite_enabled(NOSHI_LITE_STICKERS_KEYBOARD, 0, NOSHI_LITE_STICKERS_KEYBOARD, 0));
    CHECK(!noshi_lite_enabled(NOSHI_LITE_STICKERS_CHAT, 1, NOSHI_LITE_STICKERS_KEYBOARD, 0));
    CHECK(!noshi_lite_enabled(low, 0, NOSHI_LITE_CHAT_BACKGROUND, 0));
    CHECK(!noshi_lite_enabled(low, 0, NOSHI_LITE_AUTOPLAY_VIDEOS, 0));
    CHECK(noshi_lite_enabled(high, 0, NOSHI_LITE_STICKERS_CHAT, 0));
    CHECK(noshi_lite_enabled(high, 0, NOSHI_LITE_CHAT_BACKGROUND, 0));
    CHECK(!noshi_lite_enabled(low, 0, NOSHI_LITE_CALLS, 1));
    /* the low preset has the emoji of the chat for Premium only */
    CHECK(noshi_lite_enabled(low, 0, NOSHI_LITE_EMOJI_CHAT, 1));
    CHECK(!noshi_lite_enabled(low, 0, NOSHI_LITE_EMOJI_CHAT, 0));
    /* the power saver turns everything off, whatever was chosen */
    CHECK(!noshi_lite_enabled(high, 1, NOSHI_LITE_STICKERS_CHAT, 1));
    CHECK(!noshi_lite_enabled(high, 1, NOSHI_LITE_EMOJI_CHAT, 0));
}

static void test_with(void) {
    uint32_t v = 0;
    v = noshi_lite_with(v, NOSHI_LITE_EMOJI_CHAT, 1);
    CHECK_EQ_INT(v, NOSHI_LITE_EMOJI_CHAT);
    v = noshi_lite_with(v, NOSHI_LITE_CALLS, 1);
    v = noshi_lite_with(v, NOSHI_LITE_EMOJI_CHAT, 0);
    CHECK_EQ_INT(v, NOSHI_LITE_CALLS);
    CHECK_EQ_INT(noshi_lite_with(v, NOSHI_LITE_CALLS, 1), NOSHI_LITE_CALLS);
}

static void test_power_saver(void) {
    CHECK(!noshi_lite_power_saver_applied(0, 5));
    CHECK(!noshi_lite_power_saver_applied(50, 51));
    CHECK(noshi_lite_power_saver_applied(50, 50));
    CHECK(noshi_lite_power_saver_applied(50, 3));
    CHECK(noshi_lite_power_saver_applied(100, 100));
    CHECK(noshi_lite_power_saver_applied(1, 0));
    /* no reading, no saving */
    CHECK(!noshi_lite_power_saver_applied(100, -1));
    CHECK(!noshi_lite_power_saver_applied(-5, 0));
    CHECK_EQ_INT(noshi_lite_clamp_level(-3), 0);
    CHECK_EQ_INT(noshi_lite_clamp_level(42), 42);
    CHECK_EQ_INT(noshi_lite_clamp_level(300), 100);
}

static void test_power_notice(void) {
    noshi_power_notice_state state = {0, 0};
    CHECK_EQ_INT(noshi_power_notice_update(&state, 21, 0), 0);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 20, 0), NOSHI_POWER_NOTICE_LOW);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 19, 1), NOSHI_POWER_NOTICE_SAVER);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 10, 1), 0);
    CHECK_EQ_INT(noshi_power_notice_update(&state, -1, 1), 0);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 101, 1), 0);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 30, 0), 0);
    CHECK_EQ_INT(noshi_power_notice_update(&state, 5, 1), NOSHI_POWER_NOTICE_LOW | NOSHI_POWER_NOTICE_SAVER);
    CHECK_EQ_INT(noshi_power_notice_update(NULL, 5, 1), 0);
}

int main(void) {
    test_presets();
    test_class();
    test_account_bits();
    test_enabled();
    test_with();
    test_power_saver();
    test_power_notice();
    return test_finish("test_lite_rules");
}
