#ifndef NOSHI_PHONE_H
#define NOSHI_PHONE_H

#include <stddef.h>

#include "noshi_status.h"

#define NOSHI_PHONE_MAX_DIGITS 15
#define NOSHI_COUNTRY_CODE_MAX 4
#define NOSHI_COUNTRY_MAX 320

typedef struct noshi_country {
    char code[NOSHI_COUNTRY_CODE_MAX + 1];
    char iso[3];
    char name[48];
    char pattern[24];
} noshi_country;

/* keeps the ascii digits of in, at most cap - 1 of them; returns how many it kept */
size_t noshi_phone_digits(const char *in, char *out, size_t cap);

/* pattern letters X take digits, other characters only appear when a digit follows them */
noshi_status noshi_phone_format(const char *pattern, const char *digits, char *out, size_t cap);

int noshi_phone_valid(size_t code_digits, size_t national_digits);

/* lines of code;ISO;name or code;ISO;name;pattern */
noshi_status noshi_country_parse(const char *text, size_t len, noshi_country *out, size_t cap,
                                     size_t *count);

/* longest dial code that starts digits; among equal codes the later entry wins, which is the main country */
const noshi_country *noshi_country_match(const noshi_country *list, size_t count,
                                             const char *digits, size_t *code_len);

/* a number as a profile shows it: "+", the dial code, then the national digits grouped by the pattern of the matched country; the dial code 1 is shown as
   "+1 (572) 228-07-71" whatever its country says, and a number with no known code or no pattern is "+" and the digits. digits holds ascii digits only */
noshi_status noshi_phone_display(const noshi_country *list, size_t count, const char *digits, char *out, size_t cap);

#endif
