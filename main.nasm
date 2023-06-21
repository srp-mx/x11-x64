%define SYSCALL_EXIT 60
%define SYSCALL_WRITE 1
%define STDOUT 1
%define AF_UNIX 1               ; Unix domain socket
%define SOCK_STREAM 1           ; Stream-oriented socket
%define SYSCALL_SOCKET 41

BITS 64                         ; 64 bits
CPU X64                         ; Target the x86_64 family of CPUs

section .text
global _start:
_start:
    ; Open a unix socket
    mov rax, SYSCALL_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    mov rdx, 0                  ; Automatic protocol
    syscall

    ; Terminate gracefully
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
