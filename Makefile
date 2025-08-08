TMRG ?= tmrg
BENDER ?= bender

INCLUDES += --inc-dir=.bender/git/checkouts/common_cells-3510fb294b1f35a1/include

FILES += ../tmrg_src/sync.sv
FILES += ../tmrg_src/delta_counter.sv
FILES += ../tmrg_src/counter.sv
FILES += ../tmrg_src/fifo_v3.sv
FILES += ../hw/obi_uart/obi_uart_pkg.sv
FILES += ../hw/obi_uart/obi_uart_baudgen.sv
FILES += ../hw/obi_uart/obi_uart_interrupts.sv
FILES += ../hw/obi_uart/obi_uart_modem.sv
FILES += ../hw/obi_uart/obi_uart_rx.sv
FILES += ../hw/obi_uart/obi_uart_tx.sv
FILES += ../hw/obi_uart/obi_uart_register.sv
FILES += ../hw/obi_uart/obi_uart.sv

tmrg:
	mkdir -p tmrg_files
	git apply obi_types_comment.patch
	cd tmrg_files && $(TMRG) $(INCLUDES) $(FILES) --top-module=delta_counter
	git apply -R obi_types_comment.patch

