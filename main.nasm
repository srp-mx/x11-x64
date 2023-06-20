%define SYSCALL_EXIT 60

; Comments start with a semicolon!
BITS 64 ; 64 bits
CPU X64 ; Target the x86_64 family of CPUs

section .text
global _start:
_start:
    mov rax, SYSCALL_EXIT ; System V ABI: System call code goes in rax
                          ; Function parameters go, in order, on:
                          ; - rdi
                          ; - rsi
                          ; - rdx
                          ; - rcx (on Linux, it's r10 instead for syscalls only)
                          ; - r8
                          ; - r9
                          ; - Additional parameters go on the stack
                          ; Return value goes on rax
                          ;     0 meaning no error, usually
    mov rdi, 0
    syscall               ; Meaning, we exit with 0
    
