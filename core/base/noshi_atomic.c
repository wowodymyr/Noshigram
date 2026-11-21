/* the atomic library calls that clang emits for 64 bit and odd sized atomics on armv7 and that compiler-rt would give; openssl 3 needs
   them, the armv7 runtime of ios 7 does not have them, and the theos toolchain links no compiler-rt. one lock serves them all, as the locked
   implementation of compiler-rt does; arm64 and the host builds have the real ones */

#if defined(__arm__) && defined(__APPLE__)

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/* the c names are not the builtin ones, which clang will not let a file define; the labels give the linker the names it looks for */
uint64_t noshi_atomic_fetch_add_8(volatile void *p, uint64_t v, int order) __asm__("___atomic_fetch_add_8");
uint64_t noshi_atomic_fetch_sub_8(volatile void *p, uint64_t v, int order) __asm__("___atomic_fetch_sub_8");
uint64_t noshi_atomic_fetch_and_8(volatile void *p, uint64_t v, int order) __asm__("___atomic_fetch_and_8");
uint64_t noshi_atomic_fetch_or_8(volatile void *p, uint64_t v, int order) __asm__("___atomic_fetch_or_8");
uint64_t noshi_atomic_load_8(const volatile void *p, int order) __asm__("___atomic_load_8");
void noshi_atomic_store_8(volatile void *p, uint64_t v, int order) __asm__("___atomic_store_8");
void noshi_atomic_load(size_t size, const volatile void *src, void *dst, int order) __asm__("___atomic_load");
void noshi_atomic_store(size_t size, volatile void *dst, void *src, int order) __asm__("___atomic_store");
bool noshi_atomic_compare_exchange(size_t size, volatile void *p, void *expected, void *desired, int success, int failure)
    __asm__("___atomic_compare_exchange");
bool noshi_atomic_is_lock_free(size_t size, const volatile void *p) __asm__("___atomic_is_lock_free");

static pthread_mutex_t noshi_atomic_lock = PTHREAD_MUTEX_INITIALIZER;

#define NOSHI_ATOMIC_FETCH(name, op)                                         \
    uint64_t noshi_atomic_fetch_##name##_8(volatile void *p, uint64_t v, int order) { \
        uint64_t old;                                                         \
        (void)order;                                                          \
        pthread_mutex_lock(&noshi_atomic_lock);                               \
        old = *(volatile uint64_t *)p;                                        \
        *(volatile uint64_t *)p = old op v;                                   \
        pthread_mutex_unlock(&noshi_atomic_lock);                             \
        return old;                                                           \
    }

NOSHI_ATOMIC_FETCH(add, +)
NOSHI_ATOMIC_FETCH(sub, -)
NOSHI_ATOMIC_FETCH(and, &)
NOSHI_ATOMIC_FETCH(or, |)

uint64_t noshi_atomic_load_8(const volatile void *p, int order) {
    uint64_t v;
    (void)order;
    pthread_mutex_lock(&noshi_atomic_lock);
    v = *(const volatile uint64_t *)p;
    pthread_mutex_unlock(&noshi_atomic_lock);
    return v;
}

void noshi_atomic_store_8(volatile void *p, uint64_t v, int order) {
    (void)order;
    pthread_mutex_lock(&noshi_atomic_lock);
    *(volatile uint64_t *)p = v;
    pthread_mutex_unlock(&noshi_atomic_lock);
}

void noshi_atomic_load(size_t size, const volatile void *src, void *dst, int order) {
    (void)order;
    pthread_mutex_lock(&noshi_atomic_lock);
    memcpy(dst, (const void *)src, size);
    pthread_mutex_unlock(&noshi_atomic_lock);
}

void noshi_atomic_store(size_t size, volatile void *dst, void *src, int order) {
    (void)order;
    pthread_mutex_lock(&noshi_atomic_lock);
    memcpy((void *)dst, src, size);
    pthread_mutex_unlock(&noshi_atomic_lock);
}

bool noshi_atomic_compare_exchange(size_t size, volatile void *p, void *expected, void *desired, int success, int failure) {
    bool same;
    (void)success;
    (void)failure;
    pthread_mutex_lock(&noshi_atomic_lock);
    same = memcmp((const void *)p, expected, size) == 0;
    if (same) memcpy((void *)p, desired, size);
    else memcpy(expected, (const void *)p, size);
    pthread_mutex_unlock(&noshi_atomic_lock);
    return same;
}

/* only what fits a word is free of locks here; openssl then takes its own lock for the rest */
bool noshi_atomic_is_lock_free(size_t size, const volatile void *p) {
    (void)p;
    return size <= 4;
}

#else

/* a translation unit may not be empty in c99 */
typedef int noshi_atomic_unused;

#endif
