section .text
    global _exit
    _exit:
        mov eax, 1               ; syscall number: exit
        mov ebx, 10               ; exit status
        int 0x80
