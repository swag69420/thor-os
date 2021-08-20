[BITS 16]

jmp second_step

%include "intel_16.asm"

FREE_SEGMENT equ 0x5000
FREE_BASE equ 0x4500

KERNEL_Base equ 0x600       ; 0x600:0x0 (0x6000)

DAP:
.size       db 0x10
.null       db 0x0
.count      dw 0
.offset     dw 0
.segment    dw 0x0
.lba        dd 0
.lba48      dd 0

; Perform an extended read using BIOS
; On error, jump to read_failed and never returns