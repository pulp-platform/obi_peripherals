# obi_uart 16550/Linux Coverage Matrix

This is a working checklist for directed tests against the 16550A-compatible
surface.  Linux 8250 behavior is the tie breaker where the 16550A/B/C data sheets
leave room for interpretation.

## References

- TI TL16C550C data sheet, especially sections 8.5.1.2 (FIFO interrupt mode),
  8.5.1.3 (interrupt identification), 8.6.7 (LSR), and 8.6.8 (MSR):
  <https://www.ti.com/lit/ds/symlink/tl16c550c.pdf>
- Linux 8250 interrupt, RX, TX, and modem handling:
  <https://codebrowser.dev/linux/linux/drivers/tty/serial/8250/8250_port.c.html>
- Linux 8250 register definitions:
  <https://codebrowser.dev/linux/linux/include/uapi/linux/serial_reg.h.html>
- Linux 8250 saved flags for LSR/MSR bits that clear on read:
  <https://codebrowser.dev/linux/linux/include/linux/serial_8250.h.html>

## Compatibility Baseline

| Rule | Source basis |
| --- | --- |
| Reading LSR clears OE, PE, FE, and BI. A newly completed error is retained when it coincides with the read. | TL16C550C section 8.6.7 specifies read-clear behavior. Linux preserves `UART_LSR_BRK_ERROR_BITS` because it expects those bits to clear on read. New-event priority is an implementation rule inferred to avoid losing an event at the read boundary. |
| RDA is level-backed by DR without FIFOs and by the programmed trigger level with FIFOs. Reading RBR/FIFO clears the serviced condition. | TL16C550C sections 8.5.1.2 and 8.5.1.3; Linux `serial8250_rx_chars()` reads RBR while LSR DR remains set. |
| An enabled, already-retained RLS, RDA, THRE, or modem-status cause raises an interrupt without requiring a new edge. | TL16C550C IER and interrupt-identification descriptions define enabled interrupt conditions. Linux enables/disables IER independently of reading the corresponding status registers. |
| THRI clears on THR write or an IIR read that reports THRI. It does not immediately reassert while THRE remains continuously high after the IIR acknowledgement. | TL16C550C section 8.5.1.2 and the interrupt reset table. Linux services THRI through IIR and writes one or more bytes through `serial8250_tx_chars()`. |
| THRE means the TX FIFO/holding register is empty; TEMT additionally requires the transmitter shift register to be empty. | TL16C550C section 8.6.7. Linux distinguishes `UART_LSR_THRE` from `UART_LSR_TEMT` and defines both-empty as their conjunction. |
| DLAB remaps only offsets 0 and 1; IIR/FCR, LCR, MCR, LSR, MSR, and SCR remain at offsets 2 through 7. | TL16C550C register-selection table. Linux uses the fixed `serial_reg.h` offsets while changing DLAB only around divisor-latch access. |
| FIFO mode exposes 16 received bytes total, with RDA trigger levels at 1, 4, 8, and 14 total unread bytes. Character timeout occurs after four complete programmed character times. | TL16C550C receiver FIFO and timeout descriptions. Linux identifies a 16550A as a 16-byte FIFO and programs the standard trigger encodings. |
| IIR[7:6] is `00` with FIFO mode disabled and `11` when 16550A FIFO mode is enabled. | TL16C550C IIR FIFO-status definition; Linux probes FIFO capability after writing FCR FIFO enable. |
| LCR.STB selects one stop bit when clear, two stop bits for 6/7/8-bit words when set, and 1.5 stop bits for 5-bit words when set. | TL16C550C LCR stop-bit definition. Linux termios programming maps `CSTOPB` to this bit. |
| Register offsets are relative to the UART base and do not repeat at higher addresses. | Linux `serial_reg.h` defines offsets 0 through 7; 8250 register access applies `regshift` to the offset rather than masking a larger address into the register window. |

## Common Linux Modes

| Mode | Expected behavior | Current coverage |
| --- | --- | --- |
| Reset/default character mode | FIFO disabled, IER/MCR/LCR clear, LSR THRE+TEMT set, divisor reset visible through DLAB. | Partial: `tb_obi_uart_regs` checks LSR reset, IIR no-interrupt value, DLAB DLL/DLM access. |
| 8N1 receive | 8-bit character, no parity, one stop bit. | Covered: `tb_obi_uart_rx_smoke`; `tb_obi_uart_rx_line_status`. |
| 8N1 transmit | THR write clears THRE/TEMT, byte serialized with start/data/stop bits. | Covered at TX-module level: `tb_obi_uart_tx_waveform` also checks back-to-back holding-register/FIFO writes. Partial at top level: `tb_obi_uart_regs` checks LSR after THR write. |
| Divisor programming | Linux sets DLAB, writes DLL/DLM, restores LCR. Divisor range is 1..65535 for classic 16550-compatible programming. | Partial: `tb_obi_uart_regs` checks DLAB aliasing and DLL/DLM readback. Missing baud edge rate checks and divisor 0 behavior decision. |
| FIFO-enabled 16550A mode | Linux treats PORT_16550A as 16-byte FIFO with RX trigger bytes 1, 4, 8, 14 and IIR FIFO bits set to 16550A. | Partial: `tb_obi_uart_regs` checks dynamic IIR FIFO identification; `tb_obi_uart_rx_fifo` checks trigger level 4 and exact 8N1 timeout; `tb_obi_uart_rx_fifo_deep` checks all visible RX trigger levels, 16-byte ordered drain, RX FIFO reset, and byte-17 overrun. Missing top-level FIFO IRQ/IIR flows and TX full-boundary coverage. |
| Interrupt-driven RX/TX | IER enables RDI/RLSI/THRI/MSI; IIR reports pending interrupt, active low status bit, prioritized IDs. | Partial: `tb_obi_uart_interrupts` checks late enable, read-clear/new-event priority, THRI acknowledgement/rearm, FIFO RDA level behavior, and IRQ polarity; `tb_obi_uart_top_rx` checks top-level RDA IRQ/IIR clear through OBI. Missing top-level RLS/THRI/MSI flows. |
| Polling receive | Linux reads LSR, then RHR only if DR is set. | Covered for basic RX: `tb_obi_uart_top_rx` checks top-level LSR/RHR polling with real serial RX; `tb_obi_uart_rx_line_status` checks RHR clear at RX module. |
| Modem control/status | MCR controls DTR/RTS/OUT1/OUT2, loopback reflects MCR outputs into MSR, MSR delta bits are sticky until read. | Partial: `tb_obi_uart_modem` checks active-low outputs, deltas, and loopback at module level. Missing top-level MSR sticky clear via OBI read. |
| Break handling | Linux handles BI specially and may receive BI without DR on some devices; BI suppresses FE/PE in driver accounting. | Missing. Need RX break detect, set-break TX behavior, and BI/DR interaction. |
| Termios parity/word length/stop modes | Linux programs LCR for 5/6/7/8 bits, parity enable, even/stick parity, and stop-bit selection. | Partial: `tb_obi_uart_tx_waveform` checks 8-bit/two-stop and 5-bit/1.5-stop state timing. Missing RX stop-mode coverage, 5/6/7-bit data sweeps, and odd/even/stick parity. |

## Edge Cases To Test

| Area | Edge case | Current coverage |
| --- | --- | --- |
| Register aliasing | DLAB changes only offsets 0/1; offsets 2..7 remain accessible. | Covered for reads: `tb_obi_uart_regs` checks DLL/DLM plus DLAB-on IIR, LCR, MCR, LSR, MSR, and SCR visibility. Shared-register write coverage remains partial. |
| Byte enables | Only byte lane 0 should affect 8-bit registers; other lanes should not silently corrupt state. | Missing. |
| Unsupported addresses | Reads/writes outside 0..7 register window should return OBI error. | Covered for representative low/high aliases: `tb_obi_uart_regs` checks 0x40 and 0x80 reads plus a rejected 0x84 write with no IER corruption. Exhaustive address testing is missing. |
| Scratch register | Datasheet has SCR; current implementation intentionally returns 0 and ignores writes. Linux may probe/use SCR on some paths. | Partial: `tb_obi_uart_regs` checks read as 0. Missing write-then-read stays 0. This is a compatibility risk/decision. |
| FIFO clear bits | FCR clear RX/TX should flush FIFOs and self-clear reset bits. | Partial: `tb_obi_uart_rx_fifo_deep` checks the RX FIFO reset-bit self-clear request and that all unread bytes, including the prefetched RHR byte, are flushed. Missing TX FIFO reset and top-level FCR readback. |
| RX FIFO trigger thresholds | FCR[7:6] maps to 1/4/8/14 total unread bytes, including the prefetched RHR byte. Linux defaults many 16550A ports to trigger 8. | Covered at RX-module level: `tb_obi_uart_rx_fifo_deep` checks 1/4/8/14 visible thresholds and trigger-1 persistence. Missing top-level IIR/IRQ interaction. |
| RX timeout interrupt | In FIFO mode, stale RX data below trigger should raise character timeout after four programmed character times. Linux handles `UART_IIR_RX_TIMEOUT`. | Partial: `tb_obi_uart_rx_fifo` checks exact 40-baud timeout for 8N1. Missing other LCR modes and top-level IIR timeout ID. |
| RX overrun | New data when RHR/FIFO cannot accept should set OE and apply the mode-specific replacement/discard rule. | Partial: `tb_obi_uart_rx_line_status` checks non-FIFO overwrite/overrun; `tb_obi_uart_rx_fifo_deep` checks byte-17 discard/overrun and ordered drain of the 16 retained bytes. Missing top-level LSR observation. |
| RX error bits | PE/FE/BI/OE should latch in LSR, be associated with received character in FIFO mode, and clear on LSR read as specified. | Partial: `tb_obi_uart_rx_line_status` checks OE production, all four read-clear outputs, and simultaneous new-error priority. Missing received PE/FE/BI frames and FIFO character association. |
| LSR clear timing | Reading LSR clears error bits, reading RHR clears DR when no more RX data remains. | Covered at RX-module level, including simultaneous new error. Missing a top-level OBI LSR clear test. |
| IIR clear timing | THRI clears on THR write or a reporting IIR read; RDI clears when RX drops below trigger; RLS clears on LSR read; MSI clears on MSR read. | Covered at interrupt-module level, including retained causes enabled late and simultaneous new events. Missing full top-level timing. |
| THRE/TEMT distinction | THRE means THR/FIFO can accept data; TEMT means both holding and shift register empty. RS485 paths in Linux care about TEMT. | Covered at TX-module level in non-FIFO and FIFO modes, including FIFO pop of the last byte. `tb_obi_uart_regs` checks top-level reset and THR write. Missing top-level serial TX progression. |
| TX FIFO | 16-byte TX FIFO, loading behavior, full/empty flags, FIFO clear. | Partial: `tb_obi_uart_tx_waveform` checks one-byte queue status, FIFO reset acknowledgement, and two ordered bytes across a push/write overlap. Missing depth/full-boundary and top-level FIFO clear tests. |
| False start/noise | Start-bit false detection should reject short low pulses. | Missing. |
| Back-to-back RX | Continuous frames with no idle gap should be received correctly. | Partial: non-FIFO two-frame overrun test. Missing valid back-to-back frames with RHR reads/FIFO enabled. |
| Loopback top-level | MCR loopback should route TX to RX and modem outputs to modem inputs where applicable. | Partial: modem status loopback only. Missing serial TX-to-RX loopback at top level. |
| IRQ polarity | Both `irq_o` and `irq_no` should mirror pending status consistently. | Covered at interrupt submodule. Missing top-level IRQ assertion. |
| FCR/IIR FIFO ID | IIR bits 7:6 are clear with FIFO disabled and report 16550A FIFO mode when enabled. | Covered for disabled reset and FCR-enable transitions in `tb_obi_uart_regs`; interrupt tests exercise both modes. |
| Low baud trigger change | Linux may lower RX trigger to 1 for baud below 2400. | Missing. This is mostly FCR-trigger behavior once thresholds are tested. |
| Auto flow control | TL16C550C supports auto RTS/CTS, and Linux uses MCR AFE for capable ports. Current IP appears to leave flow control to software. | Unclear/likely out of scope. Need explicit compatibility statement or implementation/tests. |
| DMA/TXRDY/RXRDY | Some 16550C-like parts expose DMA-related behavior. | Likely out of scope. Current IP does not expose those pins. |

## Current Test Inventory

| Test | Scope |
| --- | --- |
| `tb_obi_uart_elab` | Full top-level elaboration/synthesis wrapper with idle OBI bus. |
| `tb_obi_uart_regs` | Top-level OBI smoke for reset LSR, THR write, dynamic IIR FIFO identification, DLAB DLL/DLM and shared offsets 2..7, IER, scratch read, high-address read/write rejection, and no alias corruption. |
| `tb_obi_uart_rx_smoke` | RX module 8N1 receive of one byte. |
| `tb_obi_uart_rx_line_status` | RX module non-FIFO data-ready, overrun on second unread byte, LSR error read-clear with simultaneous new error, and RHR read clear. |
| `tb_obi_uart_rx_fifo` | RX module FIFO mode trigger level 4 and exact 40-baud 8N1 character timeout. |
| `tb_obi_uart_rx_fifo_deep` | RX module visible trigger levels 1/4/8/14, trigger-1 persistence, 16-byte ordered drain, RX FIFO reset behavior, and overrun/discard on byte 17. |
| `tb_obi_uart_interrupts` | Interrupt late enable, retained status, read-clear/new-event priority, THRI acknowledgement/rearm, FIFO RDA level behavior, and IRQ polarity. |
| `tb_obi_uart_modem` | Modem module active-low outputs, input deltas, loopback status. |
| `tb_obi_uart_top_rx` | Top-level OBI polling RX, RDA IRQ/IIR, RHR read clear, divisor/LCR setup. |
| `tb_obi_uart_tx_waveform` | TX module 8N1 waveform, non-FIFO and FIFO THRE/TEMT timing, ordered back-to-back overlap cases, 8-bit/two-stop timing, and 5-bit/1.5-stop timing. |

## Suggested Next Tests

1. Top-level RX error matrix: parity error, framing error, break, overrun, LSR read clear, and interrupt priority through OBI/IRQ.
2. Top-level interrupt timing: late-enable and simultaneous read/new-event cases for RLS, RDA, and MSI.
3. Top-level FIFO interrupt test: enable FIFO, fill to trigger levels, verify IIR RDA/timeout IDs and IRQ clear behavior.
4. TX FIFO boundaries: fill all 16 entries, verify full behavior, drain order, and TX FIFO reset through OBI.
5. LCR mode sweep: 5/6/7/8-bit words and odd/even/stick parity for RX and TX; add RX stop-mode coverage.
6. Register robustness: byte enables, unmapped writes, scratch write behavior, DLAB alias edges.

## Open Compatibility Questions

- Is the scratch register intentionally unimplemented even though classic 16550 software may use it for probes?
- Is auto RTS/CTS support expected for this IP, or explicitly out of scope despite TL16C550C support?
- What should divisor 0 do? Datasheets generally describe divisor programming as 1..65535, but software can write 0 during probing on some variants.
- Should TX/RX FIFO clear bits be self-clearing in the FCR readback exactly like a discrete 16550, or is current internal self-clear sufficient?
