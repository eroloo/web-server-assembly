.intel_syntax noprefix
.global _start

.section .text

#zmienne
# connection_fd - connection fd
# socket_fd - socket fd

#pamiec
# post_file_fd = fd for opened file for POST
# get_file_fd = fd for opened file for GET


#funkcje


_start:
  # socket syscall
  mov rdi, 0x2 # first param 2=AF_INET
  mov rax, 0x29 # syscall number socket
  mov rsi, 0x1 # second param
  mov rdx, 0x0 # third param
  syscall
  mov qword [rip+socket_fd], rax

  # bind syscall
  mov rdi, rax # socket FD
  mov qword [rip+connection_fd], rax # save for later use
  lea rsi, [ rip + sockaddr ] #sockaddr?
  mov rdx, 16 #16bitow dla adresu
  mov rax, 49 #syscall bind
  syscall

  # listen socket
  mov rax, 50
  mov rdi, qword [rip+socket_fd]
  mov rsi, 0
  syscall

accept:
  # accept connection
  mov rdi, qword [rip+socket_fd]
  mov rax, 43
  mov rsi, 0x0
  mov rdx, 0x0
  syscall
  mov qword [rip + connection_fd], rax # newfd

  #fork()
  mov rax, 57
  syscall

  #child go to responding, parent go to close and wait for accept
  cmp rax, 0x0 # child go to create a response, parent goes close fd and listen for another socket
  je child

  #close fd in parent
  mov rax, 0x3
  mov rdi, qword [ rip + connection_fd ]
  syscall
  jmp accept

child:
  #CHILD BELOW
  #child close socket
  mov rax, 3
  mov rdi, qword [rip+socket_fd]
  syscall

  #read request
  lea rsi, [ rip + request_data ]
  mov rdi, qword [ rip + connection_fd ]
  mov rdx, 600
  mov rax, 0x0
  syscall

  #recognize type of request and redirect flow
  mov al, byte ptr [rip + request_data]
  cmp al, 0x50 # POST request_data
  je handle_post_request
  cmp al, 0x47
  je handle_get_request

handle_post_request:
  #open ( file from request )
  lea rdi, [rip+request_data+5] # beggining of filename offset 5 as 'POST ' is
  mov rcx, 0
  mov r9, 0x20
  jmp post_returns_numbytes_to_space

post_open_filename:
  #open file from disk
  mov rax, 0x2 # open syscall number
  lea r13, [rdi+rcx] # filename
  mov byte ptr [r13], 0x0
  lea rdi, [rip+request_data+5]
  mov rsi, 65 #flag O_WRONLY|O_CREAT
  mov rdx, 0777
  syscall

  #write post data to a file
  mov qword [rip + post_file_fd], rax # fd for opened file
  lea rsi, [ rip + request_data ] # *buf
  mov rcx, 0
  jmp get_post_data_start # retruns offset to start of data in rcx

get_post_data_start_back:
  lea rsi, [rip + request_data + 4]
  lea rsi, [rsi + rcx ]
  mov rcx, 0
  jmp returns_numbytes_to_space_2
post_data_write:
  mov rax, 0x1
  mov rdi, qword [rip + post_file_fd]
  mov rdx, rcx
  syscall

  #close fd as we do need it anymore
  mov rax, 0x3
  mov rdi, 3
  syscall

  #write response
  mov rax, 0x1
  mov rdi, 4#[rip+connection_fd]
  lea rsi, [ rip + write_data ]
  mov rdx, 19
  syscall

jmp close_response_exit

handle_get_request:
  #open ( file from request )
  lea rdi, [rip+request_data+4] # beggining of filename offset 4 as 'GET ' is
  mov rcx, 0
  mov r9, 0x20
  jmp get_returns_numbytes_to_space

get_open_filename:
  #open file from disk
  mov rax, 0x2 # open syscall number
  lea r13, [rdi+rcx] # filename
  mov byte ptr [r13], 0x0 # add null byte to exit string
  lea rdi, [rip+request_data+4]
  mov rsi, 0 # 0_RDONLY
  syscall

  #read data from a file
  mov rcx, rax # fd of opened file
  lea rsi, [ rip + read_file_buf ] # *buf
  mov rdi, rcx
  mov rdx, 256
  mov rax, 0
  syscall
  mov r14, rax

  #close fd as we do need it anymore
  mov rax, 0x3
  mov rdi, 3
  syscall

  #write response
  mov rax, 0x1
  mov rdi, 4#[rip+connection_fd]
  lea rsi, [ rip + write_data ]
  mov rdx, 19
  syscall

  #write readed data to opened connection
  mov rdi, qword [ rip + connection_fd ] # connectiion fd
  lea rsi, [rip+read_file_buf] # buffer for readed file
  mov rdx, r14 # count returned from read() syscall
  mov rax, 1
  syscall
  jmp close_response_exit



close_response_exit:
  # exit syscall
  mov rax, 60
  mov rdi, 0
  syscall

#returns number of bytes to char specified in r9
#assumes that pointer to request is in rdi
#returns length in rcx
get_returns_numbytes_to_space:
  lea rbx, [rdi+rcx]
  xor rax, rax
  mov al, byte ptr [rbx]
  cmp al, r9b
  je get_open_filename
  inc rcx
  jmp get_returns_numbytes_to_space

#returns number of bytes to char specified in r9
#assumes that pointer to request is in rdi
#returns length in rcx
post_returns_numbytes_to_space:
  lea rbx, [rdi+rcx]
  xor rax, rax
  mov al, byte ptr [rbx]
  cmp al, r9b
  je post_open_filename
  inc rcx
  jmp post_returns_numbytes_to_space


#returns number of bytes to chars to null byte
#start in rsi, zeroed rcx
returns_numbytes_to_space_2:
  lea rbx, [rsi+rcx]
  xor rax, rax
  mov al, byte ptr [rbx]
  cmp al, 0x00
  je post_data_write
  inc rcx
  jmp returns_numbytes_to_space_2


#returns how many bytes should be written
#rsi points to request data
#isolation beetwen headers and data should be \r\n\r\n = 0x0d0a0d0a
get_post_data_start:
  inc rcx
  mov al, byte ptr [rsi + rcx]
  cmp al, 0x0d
  jne get_post_data_start
  mov al, byte ptr [rsi + rcx + 2]
  cmp al, 0x0d
  je get_post_data_start_back
  jne get_post_data_start




.section .data
  sockaddr:
    .2byte 0x0002
    .2byte 0x5000
    .4byte 0x00000000
    .byte 0x00
  request_data:
    .space 600
  write_data:
    .string "HTTP/1.0 200 OK\r\n\r\n"
    .space 100
  connection_fd: # fd for accept
    .8byte 0x0000000000000000
    .space 50
  read_file_buf:
    .space 500
  socket_fd: # fd for socket
    .space 200
  get_file_fd:
    .space 200
  post_file_fd:
    .space 200
