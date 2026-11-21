#ifndef NOSHI_FOLDERS_H
#define NOSHI_FOLDERS_H

#include "noshi_dialogs.h"
#include "noshi_messages.h"

#define NOSHI_FOLDERS_MAX 100
#define NOSHI_FOLDER_PEERS_MAX 1000

/* these bits describe rules, not the flags of a serialized DialogFilter */
enum {
    NOSHI_FOLDER_CONTACTS = 1,
    NOSHI_FOLDER_NON_CONTACTS = 2,
    NOSHI_FOLDER_GROUPS = 4,
    NOSHI_FOLDER_CHANNELS = 8,
    NOSHI_FOLDER_BOTS = 16,
    NOSHI_FOLDER_SKIP_MUTED = 32,
    NOSHI_FOLDER_SKIP_READ = 64,
    NOSHI_FOLDER_SKIP_ARCHIVED = 128
};

typedef struct noshi_folder_rules {
    uint32_t flags;
    const noshi_peer_ref *included;
    size_t included_count;
    const noshi_peer_ref *excluded;
    size_t excluded_count;
    const noshi_peer_ref *pinned;
    size_t pinned_count;
} noshi_folder_rules;

int noshi_folder_contains(const noshi_folder_rules *rules, const noshi_dialog_row *dialog);
int noshi_folder_scans_dialogs(uint32_t flags, int archived);
/* SIZE_MAX means that this chat is not pinned in the folder */
size_t noshi_folder_pin_index(const noshi_folder_rules *rules, const noshi_dialog_row *dialog);

/* preserve an emoji outside an edit, moving its UTF-16 offset when the edit comes first */
int noshi_folder_shift_emoji(size_t *offset, size_t length, size_t start, size_t removed, size_t inserted);
noshi_status noshi_folder_title_build(noshi_arena *arena, const char *text, const noshi_send_entity *entities,
                                          size_t count, noshi_tl_value **out);

#endif
