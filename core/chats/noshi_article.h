#ifndef NOSHI_ARTICLE_H
#define NOSHI_ARTICLE_H

#include <stddef.h>
#include <stdint.h>
#include "noshi_status.h"

/* removes script elements from a bounded HTML document for the read-only article view */
noshi_status noshi_article_readonly(const uint8_t *html, size_t length, uint8_t *out, size_t capacity, size_t *written);

#endif
