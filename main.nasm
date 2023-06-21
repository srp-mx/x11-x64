%define SYSCALL_EXIT 60
%define SYSCALL_WRITE 1
%define STDOUT 1
%define AF_UNIX 1               ; Unix domain socket
%define SOCK_STREAM 1           ; Stream-oriented socket
%define SYSCALL_SOCKET 41
%define SYSCALL_CONNECT 42

BITS 64                         ; 64 bits
CPU X64                         ; Target the x86_64 family of CPUs


section .rodata

sun_path: db "/tmp/.X11-unix/X0", 0
static sun_path:data


section .text
global _start:
_start:
    call x11_connect_to_server

    ; Terminate gracefully
    mov rax, SYSCALL_EXIT       ; System V ABI: System call code goes in rax
                                ; Function parameters go, in order, on:
                                ; - rdi
                                ; - rsi
                                ; - rdx
                                ; - rcx (on Linux it's r10 instead for syscalls)
                                ; - r8
                                ; - r9
                                ; - Additional parameters go on the stack
                                ; Return value goes on rax
                                ;     0 meaning no error, usually
    mov rdi, 0
    syscall                     ; Meaning, we exit with 0

; Create a UNIX domain socket and connect to the X11 server.
; @returns The socket file descriptor
x11_connect_to_server:
static x11_connect_to_server:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Open a unix socket: socket(2)
    mov rax, SYSCALL_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    mov rdx, 0                  ; Automatic protocol
    syscall

    ; Check for errors
    cmp rax, 0
    jle die

    ; Store the resulting socket file descriptor in rdi
    mov rdi, rax

    ; Store 110-byte structure sockaddr_un on the stack (16-byte aligned)
    sub rsp, 112
    mov WORD [rsp], AF_UNIX     ; Set sockaddr_un.sun_family to AF_UNIX
    lea rsi, sun_path           ; Place a pointer to sun_path on rsi
    mov r12, rdi                ; Save the socket fd in r12
    lea rdi, [rsp + 2]          ; Get a pointer to sockaddr_un.sun_path
    cld                         ; Set direction flag to forward for movsb
    mov ecx, 19                 ; Length is 19 with null terminator
    rep movsb                   ; Copy the string
                                ; - rep: repeats string operation ecx times
                                ; - movsb: copies rsi to rdi and increments or
                                ;    decrements pointers according to dir flag

    ; Connect to the server: connect(2)
    mov rax, SYSCALL_CONNECT
    mov rdi, r12
    lea rsi, [rsp]
    %define SIZEOF_SOCKADDR_UN 2+108
    mov rdx, SIZEOF_SOCKADDR_UN
    syscall

    ; Check for errors
    cmp rax, 0
    jne die

    ; Return the socket file descriptor
    mov rax, rdi

    ; End stack frame
    add rsp, 112
    pop rbp
    ret

; Terminates the program with exit code 1
die:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall

