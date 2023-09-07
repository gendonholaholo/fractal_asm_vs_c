%define STRING_BUFFER_SIZE 1024
%define PX_CHUNK_SIZE      24 

%define STACK_SIZE         PX_CHUNK_SIZE * 3 ; 3 bytes per pixel
%define ITERATIONS         800
%define DP_ITERATIONS  __float64__(800.0)
%define DP_VIEW_LEFT   __float64__(-0.711580)
%define DP_VIEW_RIGHT  __float64__(-0.711562)
%define DP_VIEW_TOP    __float64__(-0.252133)
%define DP_VIEW_BOTTOM __float64__(-0.252143)

section .bss ; bss dimulai dari 0

futex          resd 1
current_px_idx resd 1
pixel_count    resd 1
num_threads    resd 1
argc           resd 1
image_width    resd 1
image_height   resd 1
string_buffer  resb STRING_BUFFER_SIZE
buffer         resq 1

section .data

msg_default db "rendering at a default resolution 1920x1080px", 0xa
msg_error   db "1 or 3 arguments required - num_threads, width, height", 0xa
msg_P6      db "P6 "
filename    db "fractal.ppm", 0

section .text

global _start

_start:
    ; menerima threads, width & height dari command line args
    pop rax
    mov dword [argc], eax
    pop rdi ; skip argc[0] (nama program)

    cmp rax, 2
    je .get_thread_arg
    cmp rax, 4
    je .get_thread_arg

    ; mengembalikan error
    mov rsi, msg_error
    mov rdx, 55
    syscall
    jmp exit

.get_thread_arg:

    pop rax
    call str_to_int
    mov dword [num_threads], eax

    cmp dword [argc], 4
    je .custom_resolution

    mov dword [image_width], 1920
    mov dword [image_height], 1080
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_default
    mov rdx, 46
    syscall
    jmp .arg_done ; skip .custom_resolution step

.custom_resolution:

    pop rax ; width
    call str_to_int
    mov dword [image_width], eax
    pop rax ; height
    call str_to_int
    mov dword [image_height], eax

.arg_done:

    ; alokasi image buffer dengan mmap

    ; kalkulasi size yang dibutuhkan 
    mov eax, dword [image_width]
    mov edi, dword [image_height]
    mul edi
    mov dword [pixel_count], eax
    mov edi, 3
    mul edi

    add eax, 7

    mov esi, eax ; store results ke dalam rsi

    mov rax, 9
    mov rdi, 0 ; address - null
    ; rsi is already set - size
    mov rdx, 0x3 ; permission - read | write
    mov r10, 0x22 ; flags - private | anonymous
    mov r8, -1 ; fd - must be -1 saat flag anonymous ter-set
    mov r9, 0 ; offset - must be 0 saat flag anonymous ter-set
    syscall
    mov qword [buffer], rax ; mengembalikan adress sebagai ys_mmap

    mov r12d, dword [num_threads]
    mov rbx, 0 ; iterator

.create_threads:

    ; mmap - allocate thread stack
    mov rax, 9
    mov rdi, 0
    mov rsi, STACK_SIZE
    mov rdx, 0x3
    mov r10, 0x22
    mov r8, -1
    mov r9, 0
    syscall

    mov rsi, rax
    add rsi, STACK_SIZE

    mov rax, 56 ; clone
    mov rdi, 10900h ; CLONE_THREAD | CLONE_VM | CLONE_SIGHAND
    syscall

    ; child thread path
    cmp rax, 0
    je thread_work

    inc rbx
    cmp rbx, r12
    jl .create_threads

    mov rax, 202
    mov rdi, futex
    mov rsi, 128 ; FUTEX_PRIVATE_FLAG | FUTEX_WAIT

    mov rdx, 0   
    mov r10, 0   ; timespec* timeout
    syscall

    ; open file
    mov rax, 2
    mov rdi, filename
    mov rsi, 1101o ; truncate, create, write only
    mov rdx, 644o  ; mode (permissions)
    syscall

    mov edi, eax ; save the file descriptor

    mov rax, 1

    mov rsi, msg_P6
    mov rdx, 3
    syscall

    mov eax, dword [image_width]
    call write_int_space
    mov eax, dword [image_height]
    call write_int_space
    mov eax, 255
    call write_int_space

    ; calculate byte size
    mov eax, dword [pixel_count]
    mov esi, 3
    mul esi
    mov edx, eax

    mov rax, 1
    ; rdi is already set
    mov rsi, [buffer]
    ; rdx is already set
    syscall

    ; close file
    mov rax, 3
    ; rdi is already set
    syscall
    
exit:
    mov rax, 60
    mov rdi, 0
    syscall

thread_work:

    sub rsp, PX_CHUNK_SIZE * 3

    mov r9d, dword [pixel_count]
    xor r13, r13 

.render_chunk:

    mov eax, PX_CHUNK_SIZE
    lock xadd dword [current_px_idx], eax
    cmp rax, r9
    jge .thread_exit
    mov r15, rax ; save the index

    mov rax, r9
    sub rax, r15

    xor r10, r10 ; iterator

    cmp rax, PX_CHUNK_SIZE
    jle .last_chunk

    mov r14, PX_CHUNK_SIZE 
    jmp .render_px ; skip .last_chunk

.last_chunk:
    mov r14, rax
    mov r13, 1

.render_px:

    mov edx, 0
    mov eax, r15d
    add eax, r10d
    mov edi, dword [image_width]
    div edi

    cvtsi2sd xmm0, edx
    cvtsi2sd xmm1, eax 
    mov eax, dword [image_width]
    cvtsi2sd xmm2, eax
    mov edi, [image_height]
    cvtsi2sd xmm3, edi

    divsd xmm0, xmm2
    divsd xmm1, xmm3

    ; x0
    mov rbx, __float64__(1.0)
    movq xmm2, rbx
    subsd xmm2, xmm0
    mov rax, DP_VIEW_LEFT
    movq xmm3, rax
    mulsd xmm2, xmm3
    
    movsd xmm3, xmm0
    mov rax, DP_VIEW_RIGHT
    movq xmm4, rax
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    movsd xmm0, xmm2

    ; y0
    movq xmm2, rbx 
    subsd xmm2, xmm1
    mov rax, DP_VIEW_TOP
    movq xmm3, rax
    mulsd xmm2, xmm3
    movsd xmm3, xmm1
    mov rax, DP_VIEW_BOTTOM
    movq xmm4, rax
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    movsd xmm1, xmm2

    ; now xmm1 contains y0

    mov r11d, 0      ; iteration variable
    xorps xmm2, xmm2 ; x variable, zero
    movsd xmm3, xmm2 ; y variable

.escape_px:

    movsd xmm4, xmm2
    mulsd xmm4, xmm2
    movsd xmm5, xmm3
    mulsd xmm5, xmm3
    movsd xmm6, xmm4
    addsd xmm6, xmm5
    
    mov rax, __float64__(4.0)
    movq xmm7, rax
    ucomisd xmm6, xmm7
    jae .done_escape_px

    cmp r11d, ITERATIONS
    je .done_escape_px

    movsd xmm6, xmm4
    subsd xmm6, xmm5
    addsd xmm6, xmm0
    mov rax, __float64__(2.0)
    movq xmm4, rax
    mulsd xmm3, xmm4
    mulsd xmm3, xmm2
    addsd xmm3, xmm1
    movsd xmm2, xmm6

    inc r11d ; ++iteration
    jmp .escape_px

.done_escape_px:

    ; calculate color - iteration / iterations
    cvtsi2sd xmm0, r11d
    mov rax, DP_ITERATIONS
    movq xmm1, rax
    divsd xmm0, xmm1
    mov rax, __float64__(255.0)
    movq xmm1, rax
    mulsd xmm0, xmm1

    cvtsd2si esi, xmm0

    mov eax, r10d
    mov edi, 3
    mul edi
    ; address
    mov rdi, rsp
    add rdi, rax

    mov byte [rdi]    , sil
    mov byte [rdi + 1], sil
    mov byte [rdi + 2], sil

    inc r10
    cmp r10, r14
    jne .render_px

    mov rdi, rsp 

    mov eax, r15d
    mov ebx, 3
    mul ebx
    mov rbx, [buffer]
    add rbx, rax

    mov eax, r14d
    mov ecx, 3
    mul ecx
    mov rcx, rsp
    add rcx, rax 

.copy_chunk:

    mov rsi, [rdi]
    mov [rbx], rsi 

    add rdi, 8
    add rbx, 8
    cmp rdi, rcx
    jl .copy_chunk

    jmp .render_chunk

.thread_exit:
    
    cmp r13, 1
    jne exit

    inc dword [futex]
    mov rax, 202
    mov rdi, futex
    mov rsi, 129 
    mov rdx, 1 
    syscall
    jmp exit

str_to_int:

    mov rdi, rax
    mov rsi, 10 
    mov rax, 0  
    mov rbx, 0  

.loop:

    cmp [rdi], byte 0
    je .return
    mov bl, byte [rdi]
    sub bl, 48
    mul rsi
    add rax, rbx
    inc rdi
    jmp .loop

.return:
    ret

; arguments:
; rdi - target file descriptor
; rax - number to print
; menambahkan 1 spasi

write_int_space:

    mov rbx, 10
    mov r9, 0 

    mov r15, string_buffer
    add r15, STRING_BUFFER_SIZE - 1

    mov byte [r15], 32 
    inc r9

.loop:

    mov rdx, 0 

    div rbx 
    add rdx, 48 
    dec r15
    mov byte [r15], dl 
    inc r9
    cmp rax, 0
    jne .loop

    mov rax, 1
    mov rsi, r15
    mov rdx, r9
    syscall

    ret
