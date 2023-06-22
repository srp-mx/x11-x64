%define SYSCALL_EXIT 60
%define SYSCALL_READ 0
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


section .data

id: dd 0
static id:data

id_base: dd 0
static id_base:data

id_mask: dd 0
static id_mask:data

root_visual_id: dd 0
static visual_id:data


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

; Send the handshake to the X11 server and read the returned system information
; @param rdi The socket file descriptor
; @returns The window root id (uint32_t) in rax
x11_send_handshake:
static x11_send_handshake:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Reserve a lot of stack for server response
    sub rsp, 1<<15
    mov BYTE [rsp+0], 'l'       ; Set order to little-endian
    mov WORD [rsp+2], 11        ; Set major version to 11 (X11)

    ; Send the handshake to the server: write(2)
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 12*8
    syscall

    ; Check that all bytes were written
    cmp rax, 12*8
    jnz die

    ; Read the server response: read(2)
    ; Use the stack for the read buffer
    ; The X11 server first replies with 8 bytes. Once these are read, it replies
    ;     with a much bigger message.
    mov rax, SYSCALL_READ
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 8
    syscall

    ; Check for 8 byte reply
    cmp rax, 8
    jnz die

    ; Check for success server message (first byte should be 1)
    cmp BYTE[rsp], 1
    jnz die

    ; Read the rest of the server response: read(2)
    ; Use the stack for the read buffer
    mov rax, SYSCALL_READ
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 1<<15
    syscall

    ; Check for reply
    cmp rax, 0
    jle die

    ; Set id_base globally
    mov edx, DWORD [rsp + 4]
    mov DWORD [id_base], edx

    ; Set id_mask globally
    mov edx, DWORD [rsp + 8]
    mov DWORD [id_mask], edx
    
    ; Read the info we need and skip the rest
    lea rdi, [rsp]              ; Pointer to the stuff we care about

    mov cx, WORD [rsp + 16]     ; Vendor length
    movzx rcx, cx               ; Zero-extend rcx as 16-bit

    mov al, BYTE [rsp + 21]     ; Number of formats
    movzx rax, al               ; Zero-extend rax as 8-bit
    imul rax, 8                 ; Each format is 8 bytes

    add rdi, 32                 ; Skip connection setup
    add rdi, rcx                ; Skip over vendor info
    add rdi, rax                ; Skip over format info

    ; Store and return the window root id
    mov eax, DWORD [rdi]

    ; Set the root_visual_id globally
    mov edx, DWORD [rdi + 32]
    mov DWORD [root_visual_id], edx

    ; End stack frame
    add rsp, 1<<15
    pop rbp
    ret

; Terminates the program with exit code 1
die:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall

