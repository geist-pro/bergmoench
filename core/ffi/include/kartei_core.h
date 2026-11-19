// C interface to Anki's backend for Kartei. License: GNU AGPL v3 or later.
#ifndef KARTEI_CORE_H
#define KARTEI_CORE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct KarteiBackend KarteiBackend;
typedef struct { uint8_t *ptr; size_t len; bool ok; } KarteiBytes;

KarteiBackend *kartei_open(const uint8_t *init, size_t len, KarteiBytes *err);
KarteiBytes kartei_command(const KarteiBackend *backend, uint32_t service, uint32_t method, const uint8_t *data, size_t len);
void kartei_free(KarteiBytes bytes);
void kartei_close(KarteiBackend *backend);
KarteiBytes kartei_anki_version(void);
KarteiBytes kartei_cap_states(const uint8_t *states, size_t len, int32_t days_left);
#endif
