#include "noshi_lite_rules.h"

/* the animated stickers run on the weakest class too: an ipad with 512 MB (the ipad 2, the first mini) sat on this preset and its stickers never moved, with a switch on the screen of the
   animations that the person had no reason to look for. the person who wants them still can turn them off there */
#define LOW_PRESET (NOSHI_LITE_STICKERS_KEYBOARD | NOSHI_LITE_STICKERS_CHAT | NOSHI_LITE_EMOJI_CHAT_PREMIUM | NOSHI_LITE_EMOJI_KEYBOARD_PREMIUM | \
                    NOSHI_LITE_EMOJI_REACTIONS_PREMIUM | NOSHI_LITE_AUTOPLAY_GIFS | NOSHI_LITE_CHAT_THANOS | NOSHI_LITE_PARTICLES)
#define MEDIUM_PRESET (NOSHI_LITE_STICKERS_KEYBOARD | NOSHI_LITE_STICKERS_CHAT | NOSHI_LITE_EMOJI_KEYBOARD_PREMIUM | NOSHI_LITE_EMOJI_REACTIONS_PREMIUM | \
                       NOSHI_LITE_EMOJI_CHAT_PREMIUM | NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM | NOSHI_LITE_CHAT_FORUM_TWOCOLUMN | NOSHI_LITE_CALLS | \
                       NOSHI_LITE_AUTOPLAY_VIDEOS | NOSHI_LITE_AUTOPLAY_GIFS | NOSHI_LITE_CHAT_THANOS | NOSHI_LITE_PARTICLES)
#define HIGH_PRESET (NOSHI_LITE_STICKERS_KEYBOARD | NOSHI_LITE_STICKERS_CHAT | NOSHI_LITE_EMOJI_KEYBOARD_PREMIUM | NOSHI_LITE_EMOJI_REACTIONS_PREMIUM | \
                     NOSHI_LITE_EMOJI_CHAT_PREMIUM | NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM | NOSHI_LITE_EMOJI_REACTIONS_NOT_PREMIUM | \
                     NOSHI_LITE_EMOJI_KEYBOARD_NOT_PREMIUM | NOSHI_LITE_CHAT_BACKGROUND | NOSHI_LITE_CHAT_FORUM_TWOCOLUMN | NOSHI_LITE_CHAT_SPOILER | \
                     NOSHI_LITE_CHAT_BLUR | NOSHI_LITE_CHAT_SCALE | NOSHI_LITE_CHAT_THANOS | NOSHI_LITE_CALLS | NOSHI_LITE_AUTOPLAY_VIDEOS | \
                     NOSHI_LITE_AUTOPLAY_GIFS | NOSHI_LITE_PARTICLES)

uint32_t noshi_lite_default_value(noshi_lite_class device_class) {
    switch (device_class) {
    case NOSHI_LITE_CLASS_LOW: return LOW_PRESET;
    case NOSHI_LITE_CLASS_AVERAGE: return MEDIUM_PRESET;
    default: return HIGH_PRESET;
    }
}

noshi_lite_class noshi_lite_measure_class(uint64_t memory_bytes, unsigned cores) {
    if (cores <= 1 || memory_bytes <= 512ull * 1024 * 1024) return NOSHI_LITE_CLASS_LOW;
    if (memory_bytes <= 1024ull * 1024 * 1024) return NOSHI_LITE_CLASS_AVERAGE;
    return NOSHI_LITE_CLASS_HIGH;
}

uint32_t noshi_lite_for_account(uint32_t flag, int premium) {
    static const uint32_t pairs[][2] = {
        {NOSHI_LITE_EMOJI_KEYBOARD_PREMIUM, NOSHI_LITE_EMOJI_KEYBOARD_NOT_PREMIUM},
        {NOSHI_LITE_EMOJI_REACTIONS_PREMIUM, NOSHI_LITE_EMOJI_REACTIONS_NOT_PREMIUM},
        {NOSHI_LITE_EMOJI_CHAT_PREMIUM, NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM}
    };
    unsigned i;
    for (i = 0; i < sizeof(pairs) / sizeof(pairs[0]); ++i) {
        uint32_t both = pairs[i][0] | pairs[i][1];
        if (flag & both) flag = (flag & ~both) | (premium ? pairs[i][0] : pairs[i][1]);
    }
    return flag;
}

int noshi_lite_enabled(uint32_t value, int power_saver_applied, uint32_t flag, int premium) {
    if (power_saver_applied) return 0;
    /* the panel of stickers has no switch on the screen of the animations: the one that says animated stickers is the chat's, and the stickers of the panel follow it. the panel kept
       the bit its preset gave it however the person moved the switch, and stickers turned on there never moved in the panel */
    if (flag == NOSHI_LITE_STICKERS_KEYBOARD) flag = NOSHI_LITE_STICKERS_CHAT;
    return (value & noshi_lite_for_account(flag, premium)) != 0;
}

uint32_t noshi_lite_with(uint32_t value, uint32_t flag, int on) {
    return on ? (value | flag) : (value & ~flag);
}

int noshi_lite_power_saver_applied(int level, int battery_percent) {
    return level > 0 && battery_percent >= 0 && battery_percent <= level;
}

int noshi_lite_clamp_level(int level) {
    return level < 0 ? 0 : (level > 100 ? 100 : level);
}

uint32_t noshi_power_notice_update(noshi_power_notice_state *state, int battery_percent, int saver) {
    uint32_t events = 0;
    int low;
    if (!state) return 0;
    if (battery_percent >= 0 && battery_percent <= 100) {
        low = battery_percent <= 20;
        if (low && !state->low) events |= NOSHI_POWER_NOTICE_LOW;
        state->low = low;
    }
    saver = saver != 0;
    if (saver && !state->saver) events |= NOSHI_POWER_NOTICE_SAVER;
    state->saver = saver;
    return events;
}
