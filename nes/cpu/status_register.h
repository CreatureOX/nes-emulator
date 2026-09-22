#ifndef NES_STATUS_REGISTER_H
#define NES_STATUS_REGISTER_H

#include <stdint.h>

/* StatusUnion - uses uint32_t instead of a bitfield to avoid MSVC issues */
typedef union {
    uint32_t value;
} StatusUnion;

/* Status flag masks */
#define STATUS_CARRY    0x01  /* C */
#define STATUS_ZERO     0x02  /* Z */
#define STATUS_INTERRUPT 0x04 /* I */
#define STATUS_DECIMAL   0x08 /* D */
#define STATUS_BREAK     0x10 /* B */
#define STATUS_UNUSED    0x20 /* U */
#define STATUS_OVERFLOW  0x40 /* V */
#define STATUS_NEGATIVE  0x80 /* N */

#endif /* NES_STATUS_REGISTER_H */

