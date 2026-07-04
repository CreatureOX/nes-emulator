#ifndef NES_STATUS_REGISTER_H
#define NES_STATUS_REGISTER_H

#include <stdint.h>

/* StatusUnion - 使用uint32_t而不是位字段，避免MSVC编译问题 */
typedef union {
    uint32_t value;
} StatusUnion;

/* 标志位掩码 */
#define STATUS_CARRY    0x01  /* C */
#define STATUS_ZERO     0x02  /* Z */
#define STATUS_INTERRUPT 0x04 /* I */
#define STATUS_DECIMAL   0x08 /* D */
#define STATUS_BREAK     0x10 /* B */
#define STATUS_UNUSED    0x20 /* U */
#define STATUS_OVERFLOW  0x40 /* V */
#define STATUS_NEGATIVE  0x80 /* N */

#endif /* NES_STATUS_REGISTER_H */

