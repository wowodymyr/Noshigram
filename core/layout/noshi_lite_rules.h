#ifndef NOSHI_LITE_RULES_H
#define NOSHI_LITE_RULES_H

#include <stdint.h>

/* the rules of the power saving screen; a setting is one integer of flags, one bit for each animation that can be
   switched off, with the numbers gives them so that a stored value means the same there */

#define NOSHI_LITE_STICKERS_KEYBOARD 1u
#define NOSHI_LITE_STICKERS_CHAT 2u
#define NOSHI_LITE_EMOJI_KEYBOARD_PREMIUM 4u
#define NOSHI_LITE_EMOJI_REACTIONS_PREMIUM 8u
#define NOSHI_LITE_EMOJI_CHAT_PREMIUM 16u
#define NOSHI_LITE_CHAT_BACKGROUND 32u
#define NOSHI_LITE_CHAT_FORUM_TWOCOLUMN 64u
#define NOSHI_LITE_CHAT_SPOILER 128u
#define NOSHI_LITE_CHAT_BLUR 256u
#define NOSHI_LITE_CALLS 512u
#define NOSHI_LITE_AUTOPLAY_VIDEOS 1024u
#define NOSHI_LITE_AUTOPLAY_GIFS 2048u
#define NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM 4096u
#define NOSHI_LITE_EMOJI_REACTIONS_NOT_PREMIUM 8192u
#define NOSHI_LITE_EMOJI_KEYBOARD_NOT_PREMIUM 16384u
#define NOSHI_LITE_CHAT_SCALE 32768u
#define NOSHI_LITE_CHAT_THANOS 65536u
#define NOSHI_LITE_PARTICLES (1u << 17)

#define NOSHI_LITE_EMOJI_CHAT (NOSHI_LITE_EMOJI_CHAT_PREMIUM | NOSHI_LITE_EMOJI_CHAT_NOT_PREMIUM)

/* the classes of device, from the weakest */
typedef enum {
    NOSHI_LITE_CLASS_LOW = 0,
    NOSHI_LITE_CLASS_AVERAGE = 1,
    NOSHI_LITE_CLASS_HIGH = 2
} noshi_lite_class;

/* what a person who never opened the screen gets, by the class of the device */
uint32_t noshi_lite_default_value(noshi_lite_class device_class);

/* the class of a device from its memory and its cores */
noshi_lite_class noshi_lite_measure_class(uint64_t memory_bytes, unsigned cores);

/* the premium flag a stored emoji flag stands for */
uint32_t noshi_lite_for_account(uint32_t flag, int premium);

/* whether the animation of flag runs: it is off while the power saver is applied, whatever was chosen, and otherwise it is what value says */
int noshi_lite_enabled(uint32_t value, int power_saver_applied, uint32_t flag, int premium);

/* value with all bits of flag set, or cleared */
uint32_t noshi_lite_with(uint32_t value, uint32_t flag, int on);

/* the power saver applies when a level above zero is set and the battery has fallen to it; a battery that cannot be read (below zero) never applies it */
int noshi_lite_power_saver_applied(int level, int battery_percent);

/* a level from the slider, kept in 0 to 100 */
int noshi_lite_clamp_level(int level);

#define NOSHI_POWER_NOTICE_LOW 1u
#define NOSHI_POWER_NOTICE_SAVER 2u

typedef struct noshi_power_notice_state {
    int low;
    int saver;
} noshi_power_notice_state;

/* reports entries into low battery or the saver once, and rearms after each state ends */
uint32_t noshi_power_notice_update(noshi_power_notice_state *state, int battery_percent, int saver);

#endif
