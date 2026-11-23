TMRG ?= tmrg
BENDER ?= bender

FILES += tmrg_src/sync.sv
FILES += tmrg_src/delta_counter.sv
FILES += tmrg_src/counter.sv
FILES += tmrg_src/fifo_v3.sv
FILES += obi_uart/rtl/obi_uart_pkg.sv
FILES += obi_uart/rtl/obi_uart_baudgen.sv
FILES += obi_uart/rtl/obi_uart_interrupts.sv
FILES += obi_uart/rtl/obi_uart_modem.sv
FILES += obi_uart/rtl/obi_uart_rx.sv
FILES += obi_uart/rtl/obi_uart_tx.sv
FILES += obi_uart/rtl/obi_uart_register.sv
FILES += obi_uart/rtl/obi_uart.sv

tmrg:
	mkdir -p tmrg_files
	git apply obi_types_comment.patch
	$(TMRG) $(FILES) --top-module=delta_counter --tmr-dir=tmrg_files
	git apply -R obi_types_comment.patch
	git apply tmrg_obi_types_fix.patch
	git apply tmrg_counter_overflow.patch
	sed -i -E 's/^module (\w+TMR\b)/(* keep_redundancy *)\nmodule \1/' tmrg_files/*TMR.sv

