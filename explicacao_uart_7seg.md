# Receptor Serial com Display 7 Segmentos — Explicação Completa

Este documento explica passo a passo como funciona o código assembly do projeto **UART → Display 7 Segmentos** no ATmega328P.

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Vetores de Interrupção](#vetores-de-interrupção)
3. [Tabela de 7 Segmentos](#tabela-de-7-segmentos)
4. [Inicialização (INICIO)](#inicialização-inicio)
5. [Configuração da UART](#configuração-da-uart)
6. [Loop Principal](#loop-principal)
7. [ISR de Recepção UART](#isr-de-recepção-uart)
8. [Conversão ASCII → Índice](#conversão-ascii--índice)
9. [Busca na Tabela (LPM)](#busca-na-tabela-lpm)
10. [ISR do Botão (INT0)](#isr-do-botão-int0)
11. [Exemplo Passo a Passo: Enviando '1' pela UART](#exemplo-passo-a-passo-enviando-1-pela-uart)

---

## Visão Geral

O programa faz o seguinte:

1. **Inicializa** o microcontrolador: stack, GPIO, interrupções e UART.
2. **Fica em loop infinito** aguardando interrupções.
3. Quando **chega um byte pela UART** (caractere hex '0'–'F'):
   - Converte ASCII → índice numérico (0–15)
   - Busca o padrão de bits na tabela da Flash
   - Escreve no PORTB → acende os segmentos do display
4. Quando o **botão em PD2 é pressionado** (INT0):
   - Envia uma string (nome do aluno) pela UART

---

## Vetores de Interrupção

No AVR, os primeiros endereços da Flash são reservados para **vetores de interrupção**. Quando uma interrupção ocorre, o processador salta automaticamente para o endereço correspondente.

```asm
.org 0x0000                             ; Endereço 0x0000 = vetor de reset
    RJMP INICIO                         ; Salta para inicialização no reset

.org INT0addr                           ; Endereço do vetor INT0 (interrupção externa 0)
    RJMP ISR_BOTAO                      ; Salta para tratador do botão

.org URXCaddr                           ; Endereço do vetor USART RX Complete
    RJMP ISR_UART_RX                    ; Salta para tratador de recepção UART
```

| Vetor       | Quando dispara?                     | Para onde salta?  |
|-------------|-------------------------------------|-------------------|
| `0x0000`    | Reset / power-on                    | `INICIO`          |
| `INT0addr`  | Borda de descida em PD2 (botão)     | `ISR_BOTAO`       |
| `URXCaddr`  | Byte completo recebido pela UART    | `ISR_UART_RX`     |

---

## Tabela de 7 Segmentos

O display de 7 segmentos tem 7 LEDs (a–g). Cada dígito hex (0–F) precisa de uma combinação diferente de segmentos ligados.

```
    aaaa
   f    b
   f    b
    gggg
   e    c
   e    c
    dddd
```

Como o display é **ânodo comum** (lógica invertida), `0` no bit = LED aceso, `1` = LED apagado.

```asm
TABELA:
    .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78  ; 0-7
    .DB 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E  ; 8-F
    .DB 0x3F, 0x00                                       ; traço (idx 16), padding
```

| Índice | Hex    | Binário    | Dígito exibido |
|--------|--------|------------|----------------|
| 0      | 0x40   | 01000000   | **0**          |
| 1      | 0x79   | 01111001   | **1**          |
| 2      | 0x24   | 00100100   | **2**          |
| ...    | ...    | ...        | ...            |
| 16     | 0x3F   | 00111111   | **-** (traço)  |

---

## Inicialização (INICIO)

Quando o microcontrolador liga (ou sofre reset), ele executa a partir do endereço 0x0000, que salta para `INICIO`.

### 1. Configura o Stack Pointer

```asm
LDI R16, LOW(RAMEND)                ; R16 = byte baixo do topo da RAM (0xFF)
OUT SPL, R16                        ; SPL = 0xFF
LDI R16, HIGH(RAMEND)               ; R16 = byte alto do topo da RAM (0x08)
OUT SPH, R16                        ; SPH = 0x08 → SP = 0x08FF (topo da RAM)
```

O Stack Pointer aponta para o **topo da RAM** (0x08FF no ATmega328P). A pilha cresce "para baixo" (endereços menores).

### 2. Configura GPIO

```asm
LDI R16, 0x7F                       ; R16 = 0b01111111 (bits 0-6 = 1)
OUT DDRB, R16                       ; DDRB = 0x7F → PB0-PB6 como saída (display)
OUT PORTB, R16                      ; PORTB = 0x7F → display apagado (lógica invertida)
SBI DDRD, 1                         ; PD1 como saída (TX UART)
SBI PORTD, 2                        ; habilita pull-up em PD2 (botão)
```

| Pino    | Função                        |
|---------|-------------------------------|
| PB0–PB6 | Saída → segmentos a–g         |
| PD0     | Entrada RX da UART            |
| PD1     | Saída TX da UART              |
| PD2     | Entrada do botão (com pull-up)|

### 3. Configura INT0 (interrupção do botão)

```asm
LDI R16, (1<<ISC01)                 ; INT0 na borda de descida
STS EICRA, R16
LDI R16, (1<<INT0)                  ; habilita INT0
OUT EIMSK, R16
```

- **EICRA**: define que INT0 dispara na **borda de descida** (quando o botão é pressionado e PD2 vai de 1→0).
- **EIMSK**: habilita a máscara da interrupção INT0.

---

## Configuração da UART

### Baud Rate

```asm
.equ VALOR_UBRR = 207               ; Baud Rate 4800 bps @ 16MHz

LDI R16, HIGH(VALOR_UBRR)           ; R16 = 0x00
STS UBRR0H, R16
LDI R16, LOW(VALOR_UBRR)            ; R16 = 0xCF (207)
STS UBRR0L, R16
```

Fórmula: `UBRR = (F_CPU / 16 × BAUD) - 1 = (16MHz / 16×4800) - 1 ≈ 207`

### Habilita RX, TX e interrupção de recepção

```asm
LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
STS UCSR0B, R16
```

| Bit      | Nome    | Função                                      |
|----------|---------|---------------------------------------------|
| RXEN0    | bit 4   | Habilita receptor (pode receber dados)      |
| TXEN0    | bit 3   | Habilita transmissor (pode enviar dados)    |
| RXCIE0   | bit 7   | Habilita interrupção quando chega 1 byte    |

Resultado: `(1<<7)|(1<<4)|(1<<3)` = `0b10011000` = `0x98`

### Formato do frame: 8N1

```asm
LDI R16, (1<<UCSZ01)|(1<<UCSZ00)    ; 8 bits de dados
STS UCSR0C, R16
```

- **UCSZ01:UCSZ00 = 11** → 8 bits de dados
- Paridade não setada → sem paridade (N)
- Stop bit não setado → 1 stop bit

Resultado: **8N1** (8 bits, No parity, 1 stop bit)

### Habilita interrupções globais

```asm
SEI                                 ; I=1 no SREG
```

Sem isso, nenhuma interrupção funciona.

---

## Loop Principal

```asm
LOOP:
    RJMP LOOP                       ; Loop infinito - aguarda interrupções
```

O programa fica aqui "parado", esperando. Quando uma interrupção ocorre, o processador suspende o loop, executa a ISR correspondente, e depois volta pro loop.

---

## ISR de Recepção UART

Quando um byte completo chega pela UART, a interrupção `URXCaddr` dispara e o processador salta para `ISR_UART_RX`.

### 1. Salva contexto

```asm
PUSH R16                            ; Salva R16 na pilha
PUSH R17                            ; Salva R17 na pilha
IN R17, SREG                        ; R17 = SREG (salva flags)
PUSH R17                            ; Salva SREG na pilha
PUSH ZL                             ; Salva ZL na pilha
PUSH ZH                             ; Salva ZH na pilha
```

Isso é necessário porque a ISR vai modificar esses registradores. Sem salvar, o código principal poderia "perder" valores.

### 2. Lê o byte recebido

```asm
LDS R16, UDR0                       ; R16 = byte recebido da UART
```

Ler `UDR0` também limpa a flag de "RX Complete".

### 3. Ignora CR e LF

```asm
CPI R16, 13                         ; Compara com CR (carriage return)
BREQ FIM_RX                         ; Se igual, ignora
CPI R16, 10                         ; Compara com LF (line feed)
BREQ FIM_RX                         ; Se igual, ignora
```

Isso evita que Enter/nova linha bagunce o display.

### 4. Converte e busca na tabela

```asm
RCALL CONVERTE_HEX                  ; ASCII → índice (0-16)

LDI ZH, HIGH(TABELA*2)
LDI ZL, LOW(TABELA*2)
ADD ZL, R16                         ; Z = TABELA + índice
CLR R17
ADC ZH, R17                         ; propaga carry se ZL estourou
LPM R16, Z                          ; R16 = tabela[índice]
```

### 5. Atualiza o display

```asm
OUT PORTB, R16                      ; PORTB = padrão de segmentos
```

### 6. Restaura contexto e retorna

```asm
FIM_RX:
    POP ZH
    POP ZL
    POP R17
    OUT SREG, R17                   ; restaura flags
    POP R17
    POP R16
    RETI                            ; retorna da interrupção
```

`RETI` (e não `RET`) porque é uma interrupção — ele restaura o bit I do SREG.

---

## Conversão ASCII → Índice

A sub-rotina `CONVERTE_HEX` transforma o caractere ASCII em um índice de 0 a 16.

```asm
CONVERTE_HEX:
    CPI R16, '0'                    ; < '0' ?
    BRLO INVALIDO
    CPI R16, '9'+1                  ; <= '9' ?
    BRLO EH_DIGITO                  ; sim → é dígito
    CPI R16, 'A'
    BRLO INVALIDO
    CPI R16, 'F'+1
    BRLO EH_MAIUSCULA               ; é 'A'-'F'
    CPI R16, 'a'
    BRLO INVALIDO
    CPI R16, 'f'+1
    BRLO EH_MINUSCULA               ; é 'a'-'f'
    RJMP INVALIDO

EH_DIGITO:
    SUBI R16, '0'                   ; '0'-'9' → 0-9
    RET

EH_MAIUSCULA:
    SUBI R16, 'A'-10                ; 'A'-'F' → 10-15
    RET

EH_MINUSCULA:
    SUBI R16, 'a'-10                ; 'a'-'f' → 10-15
    RET

INVALIDO:
    LDI R16, 16                     ; índice 16 = traço
    RET
```

| Entrada | Cálculo              | Saída |
|---------|----------------------|-------|
| `'0'`   | 48 - 48 = 0          | 0     |
| `'1'`   | 49 - 48 = 1          | 1     |
| `'9'`   | 57 - 48 = 9          | 9     |
| `'A'`   | 65 - 55 = 10         | 10    |
| `'F'`   | 70 - 55 = 15         | 15    |
| `'a'`   | 97 - 87 = 10         | 10    |
| `'?'`   | inválido             | 16    |

---

## Busca na Tabela (LPM)

### Por que `TABELA*2`?

No AVR, a Flash é organizada em **palavras de 16 bits** (2 bytes). O assembler gera endereços em palavras, mas a instrução `LPM` espera endereço em **bytes**.

Por isso multiplicamos por 2: `TABELA*2` converte endereço de palavra → endereço de byte.

```asm
LDI ZH, HIGH(TABELA*2)              ; byte alto do endereço
LDI ZL, LOW(TABELA*2)               ; byte baixo do endereço
ADD ZL, R16                         ; soma o índice
CLR R17
ADC ZH, R17                         ; propaga carry
LPM R16, Z                          ; lê o byte da Flash
```

Se `TABELA` está no endereço de palavra `0x0030`, então `TABELA*2 = 0x0060` (endereço de byte).

---

## ISR do Botão (INT0)

Quando o botão é pressionado, a interrupção INT0 dispara e envia a string `MSG_NOME` pela UART.

```asm
ISR_BOTAO:
    ; salva contexto...
    LDI ZH, HIGH(MSG_NOME*2)
    LDI ZL, LOW(MSG_NOME*2)

ENVIA_LOOP:
    LPM R16, Z+                     ; lê caractere e incrementa Z
    CPI R16, 0                      ; é terminador?
    BREQ FIM_BTN                    ; sim → sai
    RCALL ENVIA_BYTE                ; envia pela UART
    RJMP ENVIA_LOOP                 ; próximo caractere

FIM_BTN:
    ; restaura contexto...
    RETI
```

A sub-rotina `ENVIA_BYTE` aguarda o buffer TX estar vazio e então escreve em `UDR0`:

```asm
ENVIA_BYTE:
    PUSH R17
ESPERA_TX:
    LDS R17, UCSR0A
    SBRS R17, UDRE0                 ; pula se UDRE0=1 (buffer vazio)
    RJMP ESPERA_TX                  ; senão, espera
    STS UDR0, R16                   ; envia o byte
    POP R17
    RET
```

---

## Exemplo Passo a Passo: Enviando '1' pela UART

Vamos simular o que acontece quando você envia o caractere **`'1'`** pelo terminal serial.

### Passo 1: Byte chega na UART

- O computador envia o byte `0x31` (código ASCII de `'1'`).
- A UART do ATmega328P recebe o byte completo.
- A flag `RXC0` é setada → interrupção `URXCaddr` dispara.

### Passo 2: Processador entra na ISR

```
PC (Program Counter) salta para ISR_UART_RX
```

### Passo 3: Salva contexto

```
PUSH R16, R17, SREG, ZL, ZH → vão para a pilha
```

### Passo 4: Lê o byte recebido

```asm
LDS R16, UDR0           ; R16 = 0x31 (ASCII de '1')
```

### Passo 5: Verifica se é CR ou LF

```asm
CPI R16, 13             ; 0x31 ≠ 13 → não é CR
CPI R16, 10             ; 0x31 ≠ 10 → não é LF
```

Continua normalmente.

### Passo 6: Converte ASCII → índice

```asm
RCALL CONVERTE_HEX
```

Dentro de `CONVERTE_HEX`:

```asm
CPI R16, '0'            ; 0x31 >= 0x30? Sim
CPI R16, '9'+1          ; 0x31 < 0x3A? Sim → é dígito!
BRLO EH_DIGITO          ; salta para EH_DIGITO

EH_DIGITO:
SUBI R16, '0'           ; R16 = 0x31 - 0x30 = 0x01 = 1
RET
```

**Resultado: R16 = 1**

### Passo 7: Carrega endereço da tabela

Supondo que `TABELA` está no endereço de palavra `0x0030`:

```asm
TABELA*2 = 0x0060

LDI ZH, HIGH(0x0060)    ; ZH = 0x00
LDI ZL, LOW(0x0060)     ; ZL = 0x60
```

### Passo 8: Soma o índice

```asm
ADD ZL, R16             ; ZL = 0x60 + 1 = 0x61
CLR R17                 ; R17 = 0
ADC ZH, R17             ; ZH = 0x00 + 0 = 0x00 (sem carry)
```

**Z = 0x0061** (aponta para `TABELA[1]`)

### Passo 9: Lê o padrão da Flash

```asm
LPM R16, Z              ; R16 = byte no endereço 0x0061 da Flash
```

Olhando a tabela:

```
TABELA[0] = 0x40   (endereço 0x0060)
TABELA[1] = 0x79   (endereço 0x0061) ← AQUI!
```

**R16 = 0x79 = 0b01111001**

### Passo 10: Escreve no display

```asm
OUT PORTB, R16          ; PORTB = 0x79
```

| Bit | Pino | Segmento | Valor | LED      |
|-----|------|----------|-------|----------|
| 0   | PB0  | a        | 1     | Apagado  |
| 1   | PB1  | b        | 0     | **Aceso**|
| 2   | PB2  | c        | 0     | **Aceso**|
| 3   | PB3  | d        | 1     | Apagado  |
| 4   | PB4  | e        | 1     | Apagado  |
| 5   | PB5  | f        | 1     | Apagado  |
| 6   | PB6  | g        | 0     | Apagado  |

Segmentos **b** e **c** acesos = número **1** no display!

```
        (a apagado)
      |            |
      f            b  ← aceso
      |            |
        (g apagado)
      |            |
      e            c  ← aceso
      |            |
        (d apagado)
```

### Passo 11: Restaura contexto e retorna

```asm
POP ZH, ZL, SREG→R17, R17, R16
RETI                    ; volta pro LOOP principal
```

### Resumo do fluxo

```
'1' (0x31) chega pela UART
        ↓
ISR_UART_RX dispara
        ↓
R16 = 0x31 (lê UDR0)
        ↓
CONVERTE_HEX: 0x31 - 0x30 = 1
        ↓
Z = TABELA*2 + 1 = endereço do byte 0x79
        ↓
LPM: R16 = 0x79
        ↓
OUT PORTB, 0x79 → display mostra "1"
        ↓
RETI → volta ao loop principal
```

---

## Diagrama de Tempo

```
Tempo →

UART RX:    ════════[0x31]═══════════════════════════
                     │
Interrupção:         ▼ (URXCaddr)
                     │
ISR_UART_RX: ────────┬──────────────────────────┐
                     │  salva contexto          │
                     │  lê UDR0                 │
                     │  converte ASCII→índice   │
                     │  busca na tabela         │
                     │  OUT PORTB               │
                     │  restaura contexto       │
                     │  RETI                    │
                     └──────────────────────────┘
                                                │
Display:     ═══════════════════════════════════[1]═══
                                                ▲
                                          mostra "1"
```

---

Pronto! Agora você sabe exatamente o que acontece quando um caractere chega pela UART e aparece no display.

