; ==============================================================================
; PROJETO: Receptor Serial com Display 7 Segmentos
; Microcontrolador: ATmega328P
; Display conectado em PB0-PB6 (segmentos a-g)
; Lógica invertida: 0=ACENDE, 1=APAGA (anodo comum)
; Botão em PD2: envia nome via UART
; ==============================================================================
;
; ==================== VISÃO GERAL DO FLUXO ====================
; - Reset → INICIO: configura stack, GPIO, INT0 e UART e habilita interrupções.
; - LOOP: fica em loop infinito aguardando interrupções.
; - ISR_UART_RX: recebe 1 byte da UART, converte ASCII→índice (0..16),
;   consulta TABELA na Flash via Z/LPM e escreve o padrão em PORTB (display).
; - ISR_BOTAO (INT0): ao pressionar o botão, envia MSG_NOME pela UART.
;
; ==================== CONEXÕES / NOTAS RÁPIDAS ====================
; - Display: PB0..PB6 (a..g). (PB7 não é usado.)
; - Lógica invertida (ânodo comum): escrever '0' no bit ACENDE o segmento.
; - UART: PD0=RX (entrada), PD1=TX (saída).
; - Botão: PD2 (INT0) com pull-up interno.
; - CR/LF (13/10) recebidos pela UART são ignorados.
; - Caractere inválido → índice 16 na tabela → exibe traço '-'.
;
; ==============================================================================

.include "m328Pdef.inc"

.equ VALOR_UBRR = 207                   ; Baud Rate 4800 bps @ 16MHz: UBRR = (16MHz / 16×4800) - 1 = 207

; ==================== REGISTRADORES ESPECIAIS ====================
;
; R0-R15          : Registradores de uso geral (limitados para LDI)
; R16-R31         : Registradores de uso geral (completos)
; R26:R27 (X)     : Ponteiro X (XL:XH)
; R28:R29 (Y)     : Ponteiro Y (YL:YH)
; R30:R31 (Z)     : Ponteiro Z (ZL:ZH) - usado para LPM
;                  Fonte: pdf do AVR
;                  - No AVR, a instrução LPM (Load Program Memory) lê bytes da Flash (memória de programa)
;                    e ela usa (por padrão) o ponteiro Z como endereço de leitura.
;                  - Como TABELA e MSG_NOME estão na Flash (.cseg / .DB), para "ler a tabela" precisamos
;                    apontar Z para o endereço certo e usar LPM/LPM Z+.
; SREG            : Status Register (flags: I T H S V N Z C)
; SP (SPH:SPL)    : Stack Pointer (ponteiro da pilha)
;
; ==============================================================================

; ==================== SEÇÃO DE CÓDIGO (FLASH) + VETORES ====================
.cseg                                   ; Início da seção de código (Flash)
.org 0x0000                             ; Endereço 0x0000 = vetor de reset
	RJMP INICIO                         ; Salta para inicialização no reset
.org INT0addr                           ; Endereço do vetor INT0 (interrupção externa 0)
	RJMP ISR_BOTAO                      ; Salta para tratador do botão
.org URXCaddr                           ; Endereço do vetor USART RX Complete
	RJMP ISR_UART_RX                    ; Salta para tratador de recepção UART
;
; Observação: as ISRs (rotinas de interrupção) devem terminar em RETI (e não RET),
; pois o RETI restaura o contexto do PC e reabilita o bit global de interrupção.


; ==================== TABELA 7 SEGMENTOS ====================
; Índice 0-15 = dígitos 0-F, índice 16 = traço (caractere inválido)
; Lógica invertida: 0=ACENDE, 1=APAGA (anodo comum)
TABELA:
	.DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78  ; 0-7
	.DB 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E  ; 8-F
	.DB 0x3F, 0x00                                       ; traço (idx 16), padding
	; Bits:
	; 0x40 = 01000000
	; 0x79 = 01111001
	; 0x24 = 00100100
	; 0x30 = 00110000
	; 0x19 = 00011001
	; 0x12 = 00010010
	; 0x02 = 00000010
	; 0x78 = 01111000
	; 0x00 = 00000000
	; 0x10 = 00010000
	; 0x08 = 00001000
	; 0x03 = 00000011
	; 0x46 = 01000110
	; 0x21 = 00100001
	; 0x06 = 00000110
	; 0x0E = 00001110
	; 0x3F = 00111111
	; 0x00 = 00000000
MSG_NOME:
	.DB "Aluno: Pedro Lucas Batista dos Santos Araujo", 13, 10, 0, 0  ; String + CR + LF + terminador

; ==================== RESET / INICIALIZAÇÃO ====================
INICIO:
	LDI R16, LOW(RAMEND)                ; R16 = byte baixo do topo da RAM (0xFF)
	OUT SPL, R16                        ; SPL = 0xFF (Stack Pointer Low)
	LDI R16, HIGH(RAMEND)               ; R16 = byte alto do topo da RAM (0x08)
	OUT SPH, R16                        ; SPH = 0x08 → SP = 0x08FF (topo da RAM)
	; ------------------------------------------------------
    ; Configuração do Port B (PB0-PB6)
    ; Implementação atual:
    ; - PB0-PB6 como saída (display)
    ; - Valor escrito: 0b01111111 (0x7F)
	LDI R16, 0x7F                       ; R16 = 0b01111111 (bits 0-6 = 1)
	OUT DDRB, R16                       ; DDRB = 0x7F → PB0-PB6 como saída (display)
	OUT PORTB, R16                      ; PORTB = 0x7F → display apagado (lógica invertida)
	SBI DDRD, 1                         ; DDRD bit 1 = 1 → PD1 como saída (TX UART)
	SBI PORTD, 2                        ; PORTD bit 2 = 1 → habilita pull-up em PD2 (botão)

	; ------------------------------------------------------
    ; Configuração EICRA (External Interrupt Control Register A)
    ; Implementação atual:
    ; - Apenas INT0 é utilizado nesta implementação.
    ; - INT0 sensível à borda de descida (ISC01=1, ISC00=0).
    ; - ISC11/ISC10 não são utilizados (ficam 0).
    ; - Valor escrito: 0b00000010 (0x02)
	LDI R16, (1<<ISC01)                 ; R16 = 0b00000010 → INT0 na borda de descida
	STS EICRA, R16                      ; EICRA = 0x02

    ; ------------------------------------------------------
    ; Configuração EIMSK (External Interrupt Mask Register)
    ; Implementação atual:
    ; - Só INT0 é habilitada (bit 0).
    ; - Valor escrito: 0b00000001 (0x01)
	LDI R16, (1<<INT0)                  ; R16 = 0b00000001 → habilita INT0
	OUT EIMSK, R16                      ; EIMSK = 0x01 → interrupção INT0 habilitada

	; ------------------------------------------------------
    ; Configuração UART
    ; Implementação atual:
    ; - Baud Rate: 4800 bps
    ; - Valor escrito: 0x00 (byte alto de 207), 0xCF (byte baixo de 207)
    ; - RX + TX + interrupção RX
    ; - 8 bits de dados
	LDI R16, HIGH(VALOR_UBRR)           ; R16 = byte alto de 207 = 0x00
	STS UBRR0H, R16                     ; UBRR0H = 0x00
	LDI R16, LOW(VALOR_UBRR)            ; R16 = byte baixo de 207 = 0xCF
	STS UBRR0L, R16                     ; UBRR0L = 0xCF → baud rate = 4800 bps

	; ------------------------------------------------------
    ; Configuração UCSR0B (USART Control and Status Register 0 B)
    ; Implementação atual:
    ; - RX + TX + interrupção RX
	; Ideia geral: cada registrador é 8 bits. Cada "feature" liga/desliga um bit.
	; UCSR0B:
	; - RXEN0  (Receiver ENable): liga o receptor (pode receber dados)
	; - TXEN0  (Transmitter ENable): liga o transmissor (pode enviar dados)
	; - RXCIE0 (RX Complete Interrupt Enable): habilita interrupção quando chega 1 byte (RX complete)
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)  ; liga RX + TX + interrupção de RX
	STS UCSR0B, R16                             ; escreve a máscara no registrador UCSR0B
	;
	; UCSR0C:
	; Esse registrador controla o "formato do frame" (como cada byte vai no fio).
	;
	; Pense no UCSR0C assim (bits mais comuns):
	; - UMSEL01:UMSEL00 = modo USART (00 = assíncrono)          -> aqui fica 00 (não setamos)
	; - UPM01:UPM00     = paridade (00 = sem paridade)          -> aqui fica 00 (não setamos)
	; - USBS0           = stop bit (0 = 1 stop, 1 = 2 stops)    -> aqui fica 0  (não setamos)
	; - UCSZ01:UCSZ00   = tamanho do caractere (junto com UCSZ02 em UCSR0B)
	;
	; Aqui nós SÓ ligamos UCSZ01 e UCSZ00.
	; Isso faz UCSZ01:UCSZ00 = 11, e como UCSZ02 (lá no UCSR0B) fica 0,
	; o tamanho do caractere vira 8 bits.
	;
	; Resultado prático: 8N1
	; - 8 bits de dados (UCSZ02:0 = 0b011)
	; - N = No parity (UPM01:0 = 00)
	; - 1 stop bit (USBS0 = 0)
	LDI R16, (1<<UCSZ01)|(1<<UCSZ00)             ; 0b00000110: liga UCSZ01 e UCSZ00 -> 8 bits
	STS UCSR0C, R16                              ; aplica no UCSR0C (frame format)

	SEI                                 ; Habilita interrupções globais (I=1 no SREG)

; ==================== LAÇO PRINCIPAL ====================
LOOP:
	RJMP LOOP                           ; Loop infinito - aguarda interrupções

; ==================== ISR(Interrupt Service Routine): RECEPÇÃO UART ====================
ISR_UART_RX:
	; ------------------------------------------------------
    ; Salva contexto (registradores usados + SREG)
    ; Implementação atual:
    ; - R16: byte recebido da UART
    ; - R17: flags (salva SREG)
    ; - ZL: byte baixo do endereço da tabela
    ; - ZH: byte alto do endereço da tabela
	PUSH R16                            ; Salva R16 na pilha
	PUSH R17                            ; Salva R17 na pilha
	IN R17, SREG                        ; R17 = SREG (salva flags)
	PUSH R17                            ; Salva SREG na pilha
	PUSH ZL                             ; Salva ZL (R30) na pilha
	PUSH ZH                             ; Salva ZH (R31) na pilha

	LDS R16, UDR0                       ; R16 = byte recebido da UART
	; Importante: ler UDR0 "consome" o byte recebido e limpa a flag de RX Complete.

	; Ignora CR e LF
	CPI R16, 13                         ; Compara R16 com 13 (CR)
	BREQ FIM_RX                         ; Se igual, salta para FIM_RX (ignora CR)
	CPI R16, 10                         ; Compara R16 com 10 (LF)
	BREQ FIM_RX                         ; Se igual, salta para FIM_RX (ignora LF)

	RCALL CONVERTE_HEX                  ; Chama sub-rotina: converte ASCII → índice (0-16)
	; Importante: daqui pra baixo o R16 NÃO é mais ASCII ('0','A'...), é um índice 0..16.

	; Converte ASCII → índice (0-16)
	; Usamos Z (R31:R30) porque o LPM lê da Flash usando o ponteiro Z.
	; O "*2" em TABELA*2 existe porque rótulos na Flash são endereçados por PALAVRA,
	; mas o LPM espera endereço em BYTE.
	LDI ZH, HIGH(TABELA*2)              ; ZH = byte alto do endereço da tabela (×2 pois Flash é em palavras)
	LDI ZL, LOW(TABELA*2)               ; ZL = byte baixo do endereço da tabela
	ADD ZL, R16                         ; Z = endereço base + índice (anda na tabela)
	CLR R17                             ; R17 = 0 (para propagar carry)
	ADC ZH, R17                         ; ZH = ZH + carry (se ZL estourou)
	LPM R16, Z                          ; R16 = tabela[índice] (padrão de segmentos)
	; Resultado: R16 vira um "bitmap" para PB0..PB6 (a..g), já considerando lógica invertida.

	OUT PORTB, R16                      ; PORTB = padrão de segmentos → atualiza display

FIM_RX:
	POP ZH                              ; Restaura ZH da pilha
	POP ZL                              ; Restaura ZL da pilha
	POP R17                             ; Restaura SREG da pilha
	OUT SREG, R17                       ; SREG = R17 (restaura flags)
	POP R17                             ; Restaura R17 da pilha
	POP R16                             ; Restaura R16 da pilha
	RETI                                ; Retorna da interrupção (restaura PC e habilita I)

; ==================== ISR: BOTÃO (INT0) ====================
ISR_BOTAO:
	; ------------------------------------------------------
    ; Salva contexto (registradores usados + SREG)
    ; Implementação atual:
    ; - R16: byte a enviar
    ; - R17: flags (salva SREG)
    ; - ZL: byte baixo do endereço da string
    ; - ZH: byte alto do endereço da string
	PUSH R16                            ; Salva R16 na pilha
	PUSH R17                            ; Salva R17 na pilha
	IN R17, SREG                        ; R17 = SREG (salva flags)
	PUSH R17                            ; Salva SREG na pilha
	PUSH ZL                             ; Salva ZL na pilha
	PUSH ZH                             ; Salva ZH na pilha

	; ------------------------------------------------------
    ; Carrega endereço da string MSG_NOME
    ; Implementação atual:
    ; - ZH: byte alto do endereço da string
    ; - ZL: byte baixo do endereço da string
	LDI ZH, HIGH(MSG_NOME*2)            ; ZH = byte alto do endereço da string
	LDI ZL, LOW(MSG_NOME*2)             ; ZL = byte baixo do endereço da string

ENVIA_LOOP:
	; ------------------------------------------------------
    ; Carrega próximo caractere da string MSG_NOME
    ; Implementação atual:
    ; - R16: próximo caractere
    ; - Z: endereço da string MSG_NOME
	LPM R16, Z+                         ; R16 = próximo caractere, Z++ (pós-incremento)
	CPI R16, 0                          ; Compara R16 com 0 (terminador)
	BREQ FIM_BTN                        ; Se igual, salta para FIM_BTN (fim da string)
	RCALL ENVIA_BYTE                    ; Chama sub-rotina: envia R16 pela UART
	RJMP ENVIA_LOOP                     ; Repete para próximo caractere

FIM_BTN:
	; ------------------------------------------------------
    ; Restaura contexto (registradores usados + SREG)
    ; Implementação atual:
    ; - ZH: byte alto do endereço da string
    ; - ZL: byte baixo do endereço da string
    ; - R16: byte a enviar
    ; - R17: flags (salva SREG)
    ; - SREG: flags (salva SREG)
	POP ZH                              ; Restaura ZH da pilha
	POP ZL                              ; Restaura ZL da pilha
	POP R17                             ; Restaura SREG da pilha
	OUT SREG, R17                       ; SREG = R17 (restaura flags)
	POP R17                             ; Restaura R17 da pilha
	POP R16                             ; Restaura R16 da pilha
	RETI                                ; Retorna da interrupção

; ==================== SUB-ROTINA: CONVERTE ASCII → ÍNDICE ====================
; Entrada: R16 = caractere ASCII ('0'-'9', 'A'-'F', 'a'-'f')
; Saída:   R16 = índice (0-15) ou 16 se inválido
CONVERTE_HEX:
	CPI R16, '0'                        ; Compara R16 com '0' (48)
	BRLO INVALIDO                       ; Se menor, salta para INVALIDO
	CPI R16, '9'+1                      ; Compara R16 com ':' (58)
	BRLO EH_DIGITO                      ; Se menor, é dígito '0'-'9'
	CPI R16, 'A'                        ; Compara R16 com 'A' (65)
	BRLO INVALIDO                       ; Se menor, salta para INVALIDO
	CPI R16, 'F'+1                      ; Compara R16 com 'G' (71)
	BRLO EH_MAIUSCULA                   ; Se menor, é letra 'A'-'F'
	CPI R16, 'a'                        ; Compara R16 com 'a' (97)
	BRLO INVALIDO                       ; Se menor, salta para INVALIDO
	CPI R16, 'f'+1                      ; Compara R16 com 'g' (103)
	BRLO EH_MINUSCULA                   ; Se menor, é letra 'a'-'f'
	RJMP INVALIDO                       ; Caso contrário, inválido

EH_DIGITO:
	SUBI R16, '0'                       ; R16 = R16 - 48 → converte '0'-'9' para 0-9
	RET                                 ; Retorna da sub-rotina

EH_MAIUSCULA:
	SUBI R16, 'A'-10                    ; R16 = R16 - 55 → converte 'A'-'F' para 10-15
	RET                                 ; Retorna da sub-rotina

EH_MINUSCULA:
	SUBI R16, 'a'-10                    ; R16 = R16 - 87 → converte 'a'-'f' para 10-15
	RET                                 ; Retorna da sub-rotina

INVALIDO:
	LDI R16, 16                         ; R16 = 16 → índice do traço na tabela
	RET                                 ; Retorna da sub-rotina

; ==================== SUB-ROTINA: ENVIA BYTE PELA UART ====================
; Entrada: R16 = byte a enviar
ENVIA_BYTE:
	PUSH R17                            ; Salva R17 na pilha (será usado)
	; ------------------------------------------------------
    ; Aguarda buffer TX vazio
    ; Implementação atual:
    ; - R17: registrador de status da UART
    ; - UDRE0: bit 5 do registrador de status da UART (buffer TX vazio)
ESPERA_TX:
	; ------------------------------------------------------
    ; Verifica se buffer TX vazio
    ; Implementação atual:
    ; - R17: registrador de status da UART
    ; - UDRE0: bit 5 do registrador de status da UART (buffer TX vazio)
	LDS R17, UCSR0A                     ; R17 = registrador de status da UART
	SBRS R17, UDRE0                     ; Pula próxima instrução se UDRE0=1 (buffer vazio)
	RJMP ESPERA_TX                      ; Se UDRE0=0, aguarda (buffer cheio)
	STS UDR0, R16                       ; UDR0 = R16 → envia byte pela UART
	POP R17                             ; Restaura R17 da pilha
	RET                                 ; Retorna da sub-rotina

; ==============================================================================
; ==================== REFERÊNCIA DE INSTRUÇÕES (APOIO) ====================
;
; --- TRANSFERÊNCIA DE DADOS ---
; LDI  Rd, K      : Load Immediate - Carrega valor imediato K no registrador Rd
; LDS  Rd, addr   : Load Direct from SRAM - Carrega byte do endereço addr em Rd
; STS  addr, Rr   : Store Direct to SRAM - Armazena Rr no endereço addr
; IN   Rd, A      : In Port - Lê do registrador I/O A para Rd
; OUT  A, Rr      : Out Port - Escreve Rr no registrador I/O A
; MOV  Rd, Rr     : Move - Copia Rr para Rd
; LPM  Rd, Z      : Load Program Memory - Lê byte da Flash apontado por Z
; LPM  Rd, Z+     : Load Program Memory (pós-incremento) - Lê e incrementa Z
;
; --- PILHA (STACK) ---
; PUSH Rr         : Empilha Rr (decrementa SP, escreve na RAM)
; POP  Rd         : Desempilha para Rd (lê da RAM, incrementa SP)
;
; --- ARITMÉTICAS ---
; ADD  Rd, Rr     : Add - Soma Rd = Rd + Rr
; ADC  Rd, Rr     : Add with Carry - Soma com carry: Rd = Rd + Rr + C
; SUBI Rd, K      : Subtract Immediate - Subtrai: Rd = Rd - K
; CLR  Rd         : Clear Register - Zera Rd (equivale a EOR Rd, Rd)
;
; --- LÓGICAS ---
; AND  Rd, Rr     : AND lógico bit a bit
; OR   Rd, Rr     : OR lógico bit a bit
; EOR  Rd, Rr     : XOR lógico bit a bit
;
; --- COMPARAÇÃO ---
; CPI  Rd, K      : Compare with Immediate - Compara Rd com K (afeta flags)
; CP   Rd, Rr     : Compare - Compara Rd com Rr (afeta flags)
;
; --- DESVIOS (BRANCH) ---
; RJMP label      : Relative Jump - Salta para label (incondicional)
; RCALL label     : Relative Call - Chama sub-rotina em label
; RET             : Return - Retorna de sub-rotina
; RETI            : Return from Interrupt - Retorna de interrupção
; BREQ label      : Branch if Equal - Salta se Z=1 (resultado igual)
; BRNE label      : Branch if Not Equal - Salta se Z=0 (resultado diferente)
; BRLO label      : Branch if Lower - Salta se C=1 (unsigned menor)
; BRSH label      : Branch if Same or Higher - Salta se C=0
;
; --- MANIPULAÇÃO DE BITS ---
; SBI  A, b       : Set Bit in I/O - Seta bit b no registrador I/O A
; CBI  A, b       : Clear Bit in I/O - Limpa bit b no registrador I/O A
; SBRS Rr, b      : Skip if Bit in Register Set - Pula próxima instrução se bit b=1
; SBRC Rr, b      : Skip if Bit in Register Clear - Pula próxima instrução se bit b=0
;
; --- CONTROLE ---
; SEI             : Set Enable Interrupts - Habilita interrupções globais (I=1 no SREG)
; CLI             : Clear Interrupts - Desabilita interrupções globais (I=0)
; NOP             : No Operation - Não faz nada (1 ciclo)
;
; EICRA - External Interrupt Control Register A
; EIMSK - External Interrupt Mask Register
; UCSR0A - USART Control and Status Register 0 A
; UCSR0B - USART Control and Status Register 0 B
; UCSR0C - USART Control and Status Register 0 C
; UBRR0H - USART Baud Rate Register High
; UBRR0L - USART Baud Rate Register Low
; UDR0 - USART Data Register 0
;
; DDRB - Data Direction Register B
; PORTB - Port B Output Register
; DDRD - Data Direction Register D
; PORTD - Port D Output Register
;
; ISC01 - Interrupt Sense Control 0 Bit 1
; INT0 - External Interrupt Request 0
; UDRE0 - USART Data Register Empty 0
; RXEN0 - USART Receive Enable 0
; TXEN0 - USART Transmit Enable 0
; RXCIE0 - USART Receive Complete Interrupt Enable 0
; UCSZ01 - USART Character Size 0 Bit 1
; UCSZ00 - USART Character Size 0 Bit 0
; ==============================================================================