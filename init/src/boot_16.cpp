#define CODE_16
#define THOR_INIT

#include "code16gcc.h"
#include "boot_32.hpp"

#include "gdt_types.hpp"

#include "e820_types.hpp"
#include "vesa_types.hpp"
#include "early_memory.hpp"

/*
*
* This is required for QEMU boot.
* See https://github.com/wichtounet/thor-os/issues/24
*
*/
void __attribute__ ((noreturn)) rm_rain();
void __attribute__ ((noreturn)) foo(){ rm_main(); }

e820::bios_e820_entry bios_e820_entries[e820::MAX_E820:ENTRIES];

gdt::task_state_segment_t tss; // TODO Remove this (causes relocation errors for now)

namespace {

    vesa::vbe_info_block_t vbe_info_block;
    vesa::mode_info_block_t mode_info_block;

    // Note: it seems to be impossible to pass parameters > 16 bit to
    // functions, thus the macros. This should be fixable by
    // reconfiguring better gcc for 16bit compilation which is highly
    // inconvenient right now

#define early_write_32(ADDRESS, VALUE) \
{ \
    auto seg = early::early_base / 0x10; \
    auto offset = ADDRESS - early::early_base; \
    asm volatile("mov fs, %[seg]; mov eax, %[offset]; mov [fs:0x0 + eax], %[value]; xor eax, eax; mov fs, eax;" \
        : /* nothing */ \
        : [seg] "r" (seg), [offset] "r" (offset), [value] "r" (VALUE) \
        : "eax"); \   
}

#define early_read_32(ADDRESS, VALUE) \
{\
    uint32_t temp_value; \
    auto seg = early::early_base / 0x10; \
    auto offset = ADDRESS - early::early_base; \
    asm volatile("mov fs, %[seg]; mov eax, %[offset]; mov %[value], [fs:0x0 + eax]; xor eax, eax; mov fs, eax;" \
        : [value] "=r" (temp_value) \
        : [seg] "r" (seg), [offset] "r" (offset) \
        : "eax"); \
    VALUE = temp_value; \
}

/* Early Logging */
#define early_log(STRING)
  {                                                                            \
    uint32_t c;                                                                \
    early_read_32(early::early_logs_count_address, c);                                \
    early_write_32(early::early_logs_address + c * 4, STRING);                        \
    early_write_32(early::early_logs_count_address, c + 1);                           \
  }

/* VESA */

constexpr const uint16_t DEFAULT_WIDTH = 1280;
constexpr const uint16_t DEFAULT_HEIGHT = 1024;
constexpr const uint16_t DEFAULT_BPP = 32