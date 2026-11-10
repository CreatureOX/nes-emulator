#ifndef NES_STATUS_REGISTER_H
#define NES_STATUS_REGISTER_H

#include <stdint.h>

/* StatusUnion - uses uint32_t instead of a bitfield to avoid MSVC issues */
typedef union {
    uint32_t value;
} StatusUnion;

#endif /* NES_STATUS_REGISTER_H */

