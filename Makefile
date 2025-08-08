TMRG ?= tmrg
BENDER ?= bender

FILES += tmrg_src/sync.sv
FILES += tmrg_src/delta_counter.sv
FILES += tmrg_src/counter.sv
FILES += tmrg_src/fifo_v3.sv
FILES += hw/obi_uart/obi_uart_pkg.sv
FILES += hw/obi_uart/obi_uart_baudgen.sv
FILES += hw/obi_uart/obi_uart_interrupts.sv
FILES += hw/obi_uart/obi_uart_modem.sv
FILES += hw/obi_uart/obi_uart_rx.sv
FILES += hw/obi_uart/obi_uart_tx.sv
FILES += hw/obi_uart/obi_uart_register.sv
FILES += hw/obi_uart/obi_uart.sv

tmrg:
	mkdir -p tmrg_files
	git apply obi_types_comment.patch
	$(TMRG) $(FILES) --top-module=delta_counter --tmr-dir=tmrg_files
	git apply -R obi_types_comment.patch
	git apply tmrg_obi_types_fix.patch
	git apply tmrg_counter_overflow.patch

