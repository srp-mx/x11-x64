; Unix domain socket
%define AF_UNIX 1
; Stream-oriented socket
%define SOCK_STREAM 1

%define SYSCALL_READ 0
%define SYSCALL_WRITE 1
%define SYSCALL_POLL 7
%define SYSCALL_SOCKET 41
%define SYSCALL_CONNECT 42
%define SYSCALL_EXIT 60
%define SYSCALL_FCNTL 72

BITS 64                         ; 64 bits
CPU X64                         ; Target the x86_64 family of CPUs


section .rodata

sun_path: db "/tmp/.X11-unix/X0", 0
static sun_path:data

%define TEXT_MESSAGE_LENGTH 13
text_message: db "Hello, world!"
static text_message:data


section .data

id: dd 0
static id:data

id_base: dd 0
static id_base:data

id_mask: dd 0
static id_mask:data

root_visual_id: dd 0
static root_visual_id:data


section .text

global _start:
_start:
    call x11_connect_to_server
    mov r15, rax                ; Store in r15 the file descriptor

    mov rdi, rax
    call x11_send_handshake
    mov r12d, eax               ; Store window root id in r12
    
    call x11_next_id
    mov r13d, eax               ; Store gc_id in r13

    call x11_next_id
    mov r14d, eax               ; Store font_id in r14

    mov rdi, r15
    mov esi, r14d
    call x11_open_font

    mov rdi, r15
    mov esi, r13d
    mov edx, r12d
    mov ecx, r14d
    call x11_create_gc

    call x11_next_id
    mov ebx, eax                ; Store window id in ebx

    mov rdi, r15
    mov esi, eax
    mov edx, r12d
    mov ecx, [root_visual_id]
    %define WINDOW_X 200
    %define WINDOW_Y 200
    mov r8d, WINDOW_X | (WINDOW_Y << 16)
    %define WINDOW_W 800
    %define WINDOW_H 600
    mov r9d, WINDOW_W | (WINDOW_H << 16)
    call x11_create_window

    mov rdi, r15
    mov esi, ebx
    call x11_map_window

    mov rdi, r15
    call set_fd_non_blocking

    mov rdi, r15
    mov esi, ebx
    mov edx, r13d
    call poll_messages

    ; Terminate gracefully
    jmp terminate
                                ; System V ABI: System call code goes in rax
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

; Create a UNIX domain socket and connect to the X11 server.
; @return The socket file descriptor
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
; @return The window root id (uint32_t) in rax
x11_send_handshake:
static x11_send_handshake:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Reserve a lot of stack for server response
    sub rsp, 1<<15
    mov BYTE [rsp + 0], 'l'       ; Set order to little-endian
    mov WORD [rsp + 2], 11        ; Set major version to 11 (X11)

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
    cmp BYTE [rsp], 1
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

; Increment the global id
; @return The new id
x11_next_id:
static x11_next_id:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    mov eax, DWORD [id]         ; Load global id
    mov edi, DWORD [id_base]    ; Load global id_base
    mov edx, DWORD [id_mask]    ; Load global id_mask

    ; Return: (id_mask & id) | id_base
    and eax, edx
    or eax, edi

    ; Increment id
    add DWORD [id], 1

    ; End stack frame
    pop rbp
    ret

; Open a font on the server side
; @param rdi The socket file descriptor
; @param esi The font id
x11_open_font:
static x11_open_font:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    %define OPEN_FONT_NAME_BYTE_COUNT 5
    %define OPEN_FONT_PADDING ((4 - (OPEN_FONT_NAME_BYTE_COUNT % 4)) % 4)
    %define OPEN_FONT_PACKET_U32_COUNT (3 + (OPEN_FONT_NAME_BYTE_COUNT + OPEN_FONT_PADDING) / 4)
    %define X11_OP_REQ_OPEN_FONT 0x2d

    ; Store font request message on the stack
    sub rsp, 6*8
    mov DWORD [rsp + 0*4], X11_OP_REQ_OPEN_FONT | (OPEN_FONT_NAME_BYTE_COUNT << 16)
    mov DWORD [rsp + 1*4], esi
    mov DWORD [rsp + 2*4], OPEN_FONT_NAME_BYTE_COUNT
    mov BYTE [rsp + 3*4 + 0], 'f'
    mov BYTE [rsp + 3*4 + 1], 'i'
    mov BYTE [rsp + 3*4 + 2], 'x'
    mov BYTE [rsp + 3*4 + 3], 'e'
    mov BYTE [rsp + 3*4 + 4], 'd'

    ; Request the font
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, OPEN_FONT_PACKET_U32_COUNT*4
    syscall

    ; Check for errors
    cmp rax, OPEN_FONT_PACKET_U32_COUNT*4
    jnz die

    ; End stack frame
    add rsp, 6*8
    pop rbp
    ret

; Create an X11 graphical context
; @param rdi The socket file descriptor
; @param esi The graphical context id
; @param edx The window root id
; @param ecx The font id
x11_create_gc:
static x11_create_gc:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Reserve 64 bytes for the graphical context request on the stack
    sub rsp, 8*8

    %define X11_OP_REQ_CREATE_GC 0x37
    %define X11_FLAG_GC_BG 0x00000004
    %define X11_FLAG_GC_FG 0x00000008
    %define X11_FLAG_GC_FONT 0x00004000
    %define X11_FLAG_GC_EXPOSE 0x00010000

    %define CREATE_GC_FLAGS X11_FLAG_GC_BG | X11_FLAG_GC_FG | X11_FLAG_GC_FONT
    %define CREATE_GC_PACKET_FLAG_COUNT 3
    %define CREATE_GC_PACKET_U32_COUNT (4 + CREATE_GC_PACKET_FLAG_COUNT)
    %define MY_COLOR_RGB 0x0000ffff

    ; Copy graphical context request to the stack
    mov DWORD [rsp + 0*4], X11_OP_REQ_CREATE_GC | (CREATE_GC_PACKET_U32_COUNT<<16)
    mov DWORD [rsp + 1*4], esi
    mov DWORD [rsp + 2*4], edx
    mov DWORD [rsp + 3*4], CREATE_GC_FLAGS
    mov DWORD [rsp + 4*4], MY_COLOR_RGB
    mov DWORD [rsp + 5*4], 0
    mov DWORD [rsp + 6*4], ecx

    ; Send the graphical context request
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, CREATE_GC_PACKET_U32_COUNT*4
    syscall

    ; Check for errors
    cmp rax, CREATE_GC_PACKET_U32_COUNT*4
    jnz die

    ; End stack frame
    add rsp, 8*8
    pop rbp
    ret

; Create the X11 window
; @param rdi The socket file descriptor
; @param esi The new window id
; @param edx The window root id
; @param ecx The root visual id
; @param r8d Packed x and y
; @param r9d Packed w and h
x11_create_window:
static x11_create_window:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    %define X11_OP_REQ_CREATE_WINDOW 0x01
    %define X11_FLAG_WIN_BG_COLOR 0x00000002
    %define X11_EVENT_FLAG_KEY_RELEASE 0x0002
    %define X11_EVENT_FLAG_EXPOSURE 0x8000
    %define X11_FLAG_WIN_EVENT 0x00000800

    %define CREATE_WINDOW_FLAG_COUNT 2
    %define CREATE_WINDOW_PACKET_U32_COUNT (8 + CREATE_WINDOW_FLAG_COUNT)
    %define CREATE_WINDOW_BORDER 1
    %define CREATE_WINDOW_GROUP 1

    ; Construct the window creation message on the stack
    sub rsp, 12*8
    mov DWORD [rsp + 0*4], X11_OP_REQ_CREATE_WINDOW | (CREATE_WINDOW_PACKET_U32_COUNT << 16)
    mov DWORD [rsp + 1*4], esi
    mov DWORD [rsp + 2*4], edx
    mov DWORD [rsp + 3*4], r8d
    mov DWORD [rsp + 4*4], r9d
    mov DWORD [rsp + 5*4], CREATE_WINDOW_GROUP | (CREATE_WINDOW_BORDER << 16)
    mov DWORD [rsp + 6*4], ecx
    mov DWORD [rsp + 7*4], X11_FLAG_WIN_BG_COLOR | X11_FLAG_WIN_EVENT
    mov DWORD [rsp + 8*4], 0
    mov DWORD [rsp + 9*4], X11_EVENT_FLAG_KEY_RELEASE | X11_EVENT_FLAG_EXPOSURE

    ; Send the message
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, CREATE_WINDOW_PACKET_U32_COUNT*4
    syscall

    ; Check error
    cmp rax, CREATE_WINDOW_PACKET_U32_COUNT*4
    jnz die

    ; End stack frame
    add rsp, 12*8
    pop rbp
    ret

; Map an X11 window
; @param rdi The socket file descriptor
; @param esi The window id
x11_map_window:
static x11_map_window:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Store the map window message on the stack
    sub rsp, 16
    %define X11_OP_REQ_MAP_WINDOW 0x08
    mov DWORD [rsp + 0*4], X11_OP_REQ_MAP_WINDOW | (2<<16)
    mov DWORD [rsp + 1*4], esi

    ; Send the message
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 2*4
    syscall

    ; Check errors
    cmp rax, 2*4
    jnz die

    ; End stack frame
    add rsp, 16
    pop rbp
    ret

; Set a file descriptor in non-blocking mode
; @param rdi The file descriptor
set_fd_non_blocking:
static set_fd_non_blocking:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Get current file status
    %define F_GETFL 3
    %define F_SETFL 4
    %define O_NONBLOCK 2048
    mov rax, SYSCALL_FCNTL
    mov rdi, rdi
    mov rsi, F_GETFL
    mov rdx, 0
    syscall

    ; Check error
    cmp rax, 0
    jl die

    ; OR the current file status flag with O_NONBLOCK
    mov rdx, rax
    or rdx, O_NONBLOCK

    ; Update file status to non-blocking
    mov rax, SYSCALL_FCNTL
    mov rdi, rdi
    mov rsi, F_SETFL
    mov rdx, rdx
    syscall

    ; Check error
    cmp rax, 0
    jl die

    ; End stack frame
    pop rbp
    ret

; Read the X11 server reply
; @return The message code in al
x11_read_reply:
static x11_read_reply:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Store the reply on the stack
    sub rsp, 32
    mov rax, SYSCALL_READ
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 32
    syscall

    ; Check error, and annoylingly enough, this could be a normal close but x11
    ;     has no way of telling them apart
    cmp rax, 1
    jle die

    ; Store the first byte of the reply on rax
    mov al, BYTE [rsp]

    ; End stack frame
    add rsp, 32
    pop rbp
    ret

; Poll indefinitely messages from the X11 server: poll(2)
; @param rdi The socket file descriptor
; @param esi The window id
; @param edx The gc id
poll_messages:
static poll_messages:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; The data to poll for, stored on the stack
    sub rsp, 32
    %define POLLIN 0x001
    %define POLLPRI 0x002
    %define POLLOUT 0x004
    %define POLLERR 0x008
    %define POLLHUP 0x010
    %define POLLNVAL 0x020
    mov DWORD [rsp + 0*4], edi
    mov DWORD [rsp + 1*4], POLLIN
    mov DWORD [rsp + 16], esi   ; window id
    mov DWORD [rsp + 20], edx   ; gc id
    mov BYTE [rsp + 24], 0      ; is exposed boolean

    ; Loop indefinitely
    .loop:
        ; The polling
        mov rax, SYSCALL_POLL
        lea rdi, [rsp]
        mov rsi, 1
        mov rdx, -1
        syscall

        ; Check errors
        cmp rax, 0
        jle die
        
        cmp DWORD [rsp + 2*4], POLLERR
        je die

        cmp DWORD [rsp + 2*4], POLLHUP
        je die

        ; Read the server reply
        mov rdi, [rsp + 0*4]
        call x11_read_reply

        %define X11_EVENT_EXPOSURE 0xc
        cmp eax, X11_EVENT_EXPOSURE
        jnz .received_other_event

        .received_exposed_event:
        mov BYTE [rsp + 24], 1  ; Mark as exposed

        .received_other_event:

        cmp BYTE [rsp + 24], 1  ; is exposed?
        jnz .loop               ; if it's not exposed, don't try to draw

        .draw_text:
            mov rdi, [rsp + 0*4]            ; socket fd
            lea rsi, [text_message]         ; string
            mov edx, TEXT_MESSAGE_LENGTH    ; length
            mov ecx, [rsp + 16]             ; window id
            mov r8d, [rsp + 20]             ; gc id
            mov r9d, 100                    ; x
            shl r9d, 16
            or r9d, 100                     ; y
            call x11_draw_text

        jmp .loop

    ; End stack frame
    add rsp, 32
    pop rbp
    ret

; Draw text in an X11 window with server-side text rendering (suboptimal)
; @param rdi The socket file descriptor
; @param rsi The text string
; @param edx The text string length in bytes
; @param ecx The window id
; @param r8d The gc id
; @param r9d Packed x and y
x11_draw_text:
static x11_draw_text:function
    ; Stack frame
    push rbp
    mov rbp, rsp

    ; Store a somewhat large amount of memory on the stack to send the packet
    ;     with the string to display.
    %define DRAW_TEXT_BUFFER_LENGTH 1024
    sub rsp, DRAW_TEXT_BUFFER_LENGTH
    mov DWORD [rsp + 1*4], ecx  ; Store window id in the packet data
    mov DWORD [rsp + 2*4], r8d  ; Store the gc id in the packet data
    mov DWORD [rsp + 3*4], r9d  ; Store x,y in the packet data
    mov r8d, edx                ; Store string len in r8 since edx will change
    mov QWORD [rsp + DRAW_TEXT_BUFFER_LENGTH - 8], rdi

    ; Compute padding and packet u32 count with division and modulo 4
    mov eax, edx                ; Dividend in eax
    mov ecx, 4                  ; Divisor in ecx
    cdq                         ; Sign extend
    idiv ecx                    ; eax / ecx and put remainder in edx
    ; (4-x)%4 == -x & 3
    neg edx
    and edx, 3
    mov r9d, edx                ; Store padding in r9d
    mov eax, r8d
    add eax, r9d
    shr eax, 2                  ; eax >>= 2 (equivalent to eax /= 4)
    add eax, 4                  ; eax now contains the packet u32 count

    ; Build the text to image request
    %define X11_OP_REQ_IMAGE_TEXT8 0x4c
    mov DWORD [rsp + 0*4], r8d
    shl DWORD [rsp + 0*4], 8
    or DWORD [rsp + 0*4], X11_OP_REQ_IMAGE_TEXT8
    mov ecx, eax
    shl ecx, 16
    or [rsp + 0*4], ecx

    ; Copy the string into the packet data
    mov rsi, rsi                ; Source
    lea rdi, [rsp + 4*4]        ; Destination
    cld                         ; Forward
    mov ecx, r8d                ; Length
    rep movsb                   ; Copy

    ; Send the message
    mov rdx, rax                ; Packet u32 count
    imul rdx, 4
    mov rax, SYSCALL_WRITE
    mov rdi, QWORD [rsp + DRAW_TEXT_BUFFER_LENGTH - 8]
    lea rsi, [rsp]
    syscall

    ; Check error
    cmp rax, rdx
    jnz die

    ; End stack frame
    add rsp, DRAW_TEXT_BUFFER_LENGTH
    pop rbp
    ret

; Terminates the program with exit code 1
die:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall

; Terminates the program with exit code 0
terminate:
    mov rax, SYSCALL_EXIT
    mov rdi, 0
    syscall
