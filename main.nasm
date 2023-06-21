%define SYSCALL_EXIT 60
%define SYSCALL_WRITE 1
%define STDOUT 1

; Comments start with a semicolon!
BITS 64 ; 64 bits
CPU X64 ; Target the x86_64 family of CPUs

section .text
global _start:
_start:
    call print_hello

    mov rax, SYSCALL_EXIT       ; System V ABI: System call code goes in rax.
                                ; Function parameters go, in order, on:
                                ; - rdi
                                ; - rsi
                                ; - rdx
                                ; - rcx (on Linux it's r10 instead for syscalls)
                                ; - r8
                                ; - r9
                                ; - Additional parameters go on the stack
                                ; Return value goes on rax.
                                ;     0 meaning no error, usually.
    mov rdi, 0
    syscall                     ; Meaning, we exit with 0.

print_hello:
    push rbp                    ; Push rbp to the stack to restore it at the end
                                ;     of the function. It remembers where the
                                ;     stack frame begins.
    mov rbp, rsp                ; Set rbp to rsp.

    sub rsp, 16                 ; Reserve 16 bytes of space on the stack.
                                ;     the stack needs to be 16-byte aligned.
    mov BYTE [rsp + 0], 'H'     ; Put the characters on the stack.
    mov BYTE [rsp + 1], 'e'
    mov BYTE [rsp + 2], 'l'
    mov BYTE [rsp + 3], 'l'
    mov BYTE [rsp + 4], 'o'

    ; Make the write syscall
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT             ; Write to stdout.
    lea rsi, [rsp]              ; Address on the stack of the string
                                ;     lea is load effective address: C pointer.
    mov rdx, 5                  ; Pass the length of the string, which is 5.
    syscall

    call print_world

    add rsp, 16                 ; Restore the stack to its original value.

    pop rbp                     ; Restore rbp.
    ret

print_world:
    push rbp
    mov rbp, rsp

    sub rsp, 16
    mov BYTE [rsp + 0], ' '
    mov BYTE [rsp + 1], 'w'
    mov BYTE [rsp + 2], 'o'
    mov BYTE [rsp + 3], 'r'
    mov BYTE [rsp + 4], 'l'
    mov BYTE [rsp + 5], 'd'
    mov BYTE [rsp + 6], 10      ; Line feed

    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [rsp]
    mov rdx, 7
    syscall

    add rsp, 16
    pop rbp
    ret
