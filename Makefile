#----------------------------------------
#-- Establecer nombre del componente
#----------------------------------------
NAME = 2mics-output
DEPS = 

#-------------------------------------------------------
#-- Objetivo por defecto: hacer simulacion y sintesis
#-------------------------------------------------------
all: sim sint
	
#----------------------------------------------
#-- make sim
#----------------------------------------------
#-- Objetivo para hacer la simulacion del
#-- banco de pruebas
#----------------------------------------------
sim: $(NAME)_tb.vcd
	
#-----------------------------------------------
#-  make sint
#-----------------------------------------------
#-  Objetivo para realizar la sintetis completa
#- y dejar el diseno listo para su grabacion en
#- la FPGA
#-----------------------------------------------
sint: $(NAME).bin
	
#-------------------------------
#-- Compilation and simulation
#-------------------------------
$(NAME)_tb.vcd: $(NAME).v $(DEPS) $(NAME)_tb.v
	
	#-- Compile
	iverilog -o $(NAME)_tb.out $^	
	#-- Simulate
	./$(NAME)_tb.out
	
	#-- Visualise the simulation output with GTKwave
	# Not working correctly for OSX (wring executable), deactivated
	#gtkwave $@ $(NAME)_tb.gtkw &

#------------------------------
#-- Full synthesis
#------------------------------
$(NAME).bin: $(NAME).pcf $(NAME).v $(DEPS)
	
	#-- Synthesis
	# For ECP5, the synth_ecp5 option will be needed.
	yosys -p "synth_ice40 -blif $(NAME).blif -top top" $(NAME).v $(DEPS)
	#yosys -l $(NAME)-yosys.log -p "synth_ecp5 -top top -json $(NAME).json" $(NAME).v $(DEPS)
	#yosys -p "synth_ecp5 -blif $(NAME).blif" $(NAME).v $(DEPS)
	
	#-- Place & route
	arachne-pnr -o $(NAME).txt -d 1k -p $(NAME).pcf $(NAME).blif
	#nextpnr-ecp5 -l $(NAME)-nextpnr.log --um5g-85k --json $(NAME).json --lpf $(NAME).lpf --textcfg $(NAME).txt
	
	#-- Generate final bitfile, download to FPGA
	icepack $(NAME).txt $(NAME).bin
	#ecppack --input $(NAME).txt --bit $(NAME).bin
	#ecpprog $(NAME).bin

#-- Clear all
clean:
	rm -f *.bin *.txt *.blif *.out *.vcd *~

.PHONY: all clean

