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
extended_read:
    mov ah, 0x42
    mov si, DAP
    mov dl, 0x80
    int 0x13

    jc read_failed

    ret

; Loaded at 0x410:0x0 ) 0x4100
second_step:
    ; Set datat segmenet
    mov ax, 0x410
    mov ds, ax

    ; Used for disk access
    mov ax, FREE_SEGMENT
    mov gs, ax

    mov si, load_kernel
    call print_line_16

    ; 1. Read the MBR to get the partition table
    
    mov byte [DAP.count], 1
    mov word [DAP.offset], FREE_BASE
    mov word [DAP.segment], FREE_SEGMENT
    mov dword [DAP.lba]m 0

    call extended_read

    mov ax, [gs:(FREE_BASE + 446 +8)]
    mov [partition_start], ax

    ; 2. Read the VBR of the partition to get FAT informations

    mov byte [DAP.count], 1
    mov word [DAP.offset], FREE_BASE
    mov word [DAP.segmenet], FREE_SEGMENT

    mov di, [partition_start]
    mov word [DAP.lba], di

    call extended_read

    mov ah, [gs:(FREE_BASE + 13)]
    mov [sectors_per_cluster], ah

    mov ax, [gs:(FREE_BASE + 14)]
    mov [reserved_sectors], ax

    mov ah, [gs:(FREE_BASE  + 16)]
    mov [number_of_fat], ah

    mov ax, [gs:(FREE_BASE+ 38)]
    test ax, ax
    jne sectors_per_fat_too_high

    ; sectors_per_fat (only low part)
    mov ax, [gs:(FREE_BASE + 36)]
    mov [sectors_per_fat], ax

    mov ax, [gs:(FREE_BASE + 44)]
    mov [root_dir_start], ax

    ; fat_begin = partition_start + reserved_sectors
    mov ax, [partition_start]
    mov bx, [reserved_sectors]
    add ax, bx
    mov [fat_begin], ax

    ; cluster_begin = (number_of_fat * sector_per_fat) + fat_begin
    mov ax, [sectors_per_fat]
    movzx bx, [number_of_fat]
    mul bx
    mov bx, [fat_begin]
    add ax, bx
    mov [cluster_begin], ax

    ; entries per cluster = [512,32] * sectors_per_cluster
    movzx ax, byte [sectors_per_cluster]
    shl ax, 4
    mov [entries_per_cluster], ax

    ; 3. Read the root directory to find the kernel executable

    mov ah, [sectors_per_cluster]
    mov byte [DAP.count], ah
    mov word [DAP.offset], FREE_BASE
    mov word [DAP.segment], FREE_SEGMENT

    ; Compute LBA from root_dir_start
    mov ax, [root_dir_start]
    sub ax, 2
    movzx bx, byte [sectors_per_cluster]
    nul bx
    mov bx, [cluster_begin]
    add ax, bx
    
    mov word [DAP.lba], ax

    call extended_read

    mov si, FREE_BASE
    xor cx, cx

    .next: 
        mov ah, [gs:si]

        ; Test if it is at the end of the directory
        test ah, ah
        je .end_of_directory

        mov ax, [gs:si]
        cmp ax, 0x4E49 ; NI
        jne .continue

        mov ax, [gs:(si+2)]
        cmp ax, 0x5449 ; TI
        jne .continue

        mov ax, [gs:(si+4)]
        cmp ax, 0x2020 ; space space
        jne .continue

        mov ax, [gs:(si+6)]
        cmp ax, 0x2020 ; space space
        jne .continue

        mov ax, [gs:(si+8)]
        cmp ax, 0x4942 ; IB
        jne .continue

        mov ah, [gs:(si+10)]