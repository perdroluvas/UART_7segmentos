; ==============================================================================
; PROJETO: Receptor Serial com Display 7 Segmentos
; Display conectado em PB0-PB6 (segmentos a-g)
; Lógica invertida: 0=ACENDE, 1=APAGA
; ==============================================================================

	.include "m328Pdef.inc"

	;    Baud Rate 4800
	.equ VALOR_UBRR = 207

	.dseg
	.org SRAM_START

	.cseg
	.org 0x0000
	RJMP CONFIG_INICIAL
	.org INT0addr
	RJMP TRATA_BOTAO
	.org URXCaddr
	RJMP TRATA_RECEPCAO

	; --- TABELA CORRIGIDA (LÓGICA INVERTIDA) ---
	; O display opera em lógica negativa: 0=ACENDE, 1=APAGA
	; IMPORTANTE: Dois bytes por linha para evitar padding de alinhamento!

; Lookup table: índice 0-15 = dígitos 0-F, índice 16 = traço
TABELA_HEX:
	.DB 0x40, 0x79  ; 0, 1
	.DB 0x24, 0x30  ; 2, 3
	.DB 0x19, 0x12  ; 4, 5
	.DB 0x02, 0x78  ; 6, 7
	.DB 0x00, 0x10  ; 8, 9
	.DB 0x08, 0x03  ; A, b
	.DB 0x46, 0x21  ; C, d
	.DB 0x06, 0x0E  ; E, F
	.DB 0x3F, 0x00  ; traço, padding

; String enviada ao pressionar botão (CR+LF no final)
MSG_NOME:
	.DB "Aluno: Pedro Lucas Batista dos Santos Araujo", 13, 10, 0, 0

; ==================== INICIALIZAÇÃO ====================
CONFIG_INICIAL:
	; Configura Stack Pointer para o topo da RAM
	LDI R16, LOW(RAMEND)
	OUT SPL, R16
	LDI R16, HIGH(RAMEND)
	OUT SPH, R16

	; Configura direção dos pinos
	LDI R16, 0x7F
	OUT DDRB, R16          ; PB0-PB6 como saída (segmentos a-g)
	SBI DDRD, 1            ; PD1 como saída (TX da UART)
	CBI DDRD, 2            ; PD2 como entrada (botão)
	SBI PORTD, 2           ; Ativa pull-up no botão

	; Configura INT0: dispara na borda de descida
	LDI R16, (1 << ISC01)
	STS EICRA, R16
	LDI R16, (1 << INT0)
	OUT EIMSK, R16         ; Habilita INT0

	; Configura UART: 4800 bps, 8N1
	LDI R16, high(VALOR_UBRR)
	STS UBRR0H, R16
	LDI R16, low(VALOR_UBRR)
	STS UBRR0L, R16
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)  ; RX, TX e interrupção RX
	STS UCSR0B, R16
	LDI R16, (1<<UCSZ01)|(1<<UCSZ00)            ; 8 bits de dados
	STS UCSR0C, R16

	SEI                    ; Habilita interrupções globais

; Loop principal - apenas aguarda interrupções
MAIN_LOOP:
	RJMP MAIN_LOOP

; ==================== ISR: RECEPÇÃO UART ====================
TRATA_RECEPCAO:
	; Salva contexto (registradores usados + SREG)
	PUSH R16
	PUSH R17
	PUSH R30
	PUSH R31
	IN   R16, SREG
	PUSH R16

	LDS R17, UDR0          ; Lê byte recebido

	; Ignora CR (13) e LF (10) - evita "apagar" display no Enter
	CPI  R17, 13
	BREQ SAI_RX
	CPI  R17, 10
	BREQ SAI_RX

	; === Classificação do caractere recebido ===
	CPI  R17, '0'
	BRLO EH_INVALIDO       ; < '0' → inválido
	CPI  R17, '9' + 1
	BRLO EH_NUMERO         ; '0'-'9' → número
	CPI  R17, 'A'
	BRLO EH_INVALIDO       ; entre '9' e 'A' → inválido
	CPI  R17, 'F' + 1
	BRLO EH_LETRA_MAIUSCULA ; 'A'-'F' → hex maiúsculo
	CPI  R17, 'a'
	BRLO EH_INVALIDO       ; entre 'F' e 'a' → inválido
	CPI  R17, 'f' + 1
	BRLO EH_LETRA_MINUSCULA ; 'a'-'f' → hex minúsculo
	RJMP EH_INVALIDO

EH_NUMERO:
	SUBI R17, '0'          ; Converte ASCII '0'-'9' → 0-9
	RJMP ATUALIZA

EH_LETRA_MAIUSCULA:
	SUBI R17, 'A' - 10     ; Converte ASCII 'A'-'F' → 10-15
	RJMP ATUALIZA

EH_LETRA_MINUSCULA:
	SUBI R17, 'a' - 10     ; Converte ASCII 'a'-'f' → 10-15
	RJMP ATUALIZA

EH_INVALIDO:
	LDI R17, 16            ; Índice 16 = traço (caractere inválido)

ATUALIZA:
	; Carrega endereço da tabela (x2 pois Flash é em palavras)
	LDI ZH, HIGH(TABELA_HEX * 2)
	LDI ZL, LOW(TABELA_HEX * 2)
	ADD ZL, R17            ; Z += índice do dígito
	LDI R16, 0
	ADC ZH, R16            ; Propaga carry se houver
	LPM R16, Z             ; Lê padrão de segmentos da tabela

	OUT PORTB, R16         ; Envia bits 0-6 para segmentos a-g

SAI_RX:
	; Restaura contexto e retorna da interrupção
	POP R16
	OUT SREG, R16
	POP R31
	POP R30
	POP R17
	POP R16
	RETI

; ==================== ISR: BOTÃO (INT0) ====================
TRATA_BOTAO:
	; Salva contexto
	PUSH R16
	PUSH R17
	PUSH R30
	PUSH R31
	IN   R16, SREG
	PUSH R16

	; Carrega endereço da string
	LDI  ZH, HIGH(MSG_NOME * 2)
	LDI  ZL, LOW(MSG_NOME * 2)

ENVIA_MSG:
	LPM   R17, Z+          ; Lê próximo char e incrementa ponteiro
	CPI   R17, 0           ; Chegou no terminador?
	BREQ  FIM_BTN          ; Sim → sai
	RCALL TX_BYTE          ; Não → envia o byte
	RJMP  ENVIA_MSG        ; Repete

FIM_BTN:
	; Restaura contexto e retorna
	POP R16
	OUT SREG, R16
	POP R31
	POP R30
	POP R17
	POP R16
	RETI

; ==================== SUB-ROTINA: ENVIA BYTE UART ====================
TX_BYTE:
	LDS  R16, UCSR0A       ; Lê status da UART
	SBRS R16, UDRE0        ; Buffer TX vazio?
	RJMP TX_BYTE           ; Não → aguarda
	STS  UDR0, R17         ; Sim → envia byte
	RET
