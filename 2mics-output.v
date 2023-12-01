// This module builds on the elementary CIC filter (PDM-mic-readout).
// Here, we will read in two MEMS microphones, filter their signals,
// and output their samples over the serial connection.

`timescale 1ns/1ns
`default_nettype none
`include "baudgen.vh"

module top (input wire clk,
	    input wire mic_data_1,
	    input wire mic_data_2,
            output wire serial_tx,
	    output wire mic_clk_1,
	    output wire mic_clk_2,
	    output wire sel_2,
            output wire serial_split);

// Keep the select pin for mic 2 high
assign sel_2 = 1;

wire [31:0] CIC_to_serial_1;
wire [31:0] CIC_to_serial_2;
wire load_data_1;

(* keep="soft" *)
wire load_data_2;

wire clk_3MHz;

assign mic_clk_1 = clk_3MHz;
assign mic_clk_2 = clk_3MHz;

wire serial_conn;
assign serial_tx = serial_conn;
// Split out the serial output for testing
assign serial_split = clk_3MHz;

// Clock divider for PDM 3 MHz
divider #(4) PDM1 ( .clk_in(clk), .clk_out(clk_3MHz));

// Experiment: make a central CIC filter for multiple mics to see if we can
// reduce LUT usage
centralCIC #(64) CIC ( .clk_in(clk_3MHz), .d_in_1(mic_data_1),  .d_in_2(mic_data_2), .d_out_1(CIC_to_serial_1), .d_out_2(CIC_to_serial_2), .load(load_data_1));

// Serial comms
serialtransmission SERIAL1 (.clk(clk), .d_clk(load_data_1), .d_in_1(CIC_to_serial_1), .d_in_2(CIC_to_serial_2), .tx(serial_conn));

endmodule

// Divider module
module divider #(parameter M = 4)
                (input wire clk_in, output wire clk_out);

localparam N = $clog2(M);
reg [N-1:0] divcounter;

initial begin
  divcounter <= 0;
end

always @(posedge clk_in)
  divcounter <= (divcounter == M - 1) ? 0 : divcounter + 1;

assign clk_out = divcounter[N-1];

endmodule

module centralCIC #(parameter width = 64)
		       (input wire        clk_in,
			input wire        d_in_1,
			input wire        d_in_2,
			output reg [31:0] d_out_1,
			output reg [31:0] d_out_2,
		        output reg        load);

parameter decimation_ratio = 256; // From 3 MHz to 117XX Hz

reg [9:0] counter;

reg [width-1:0] d_tmp_1, d_d_tmp_1, d_tmp_2, d_d_tmp_2;

// Integrator stage registers

reg [width-1:0] d_prep_1 = {width{1'b0}};
reg [width-1:0] d_prep_2 = {width{1'b0}};
reg [width-1:0] d1_1 = {width{1'b0}};
reg [width-1:0] d2_1 = {width{1'b0}};
reg [width-1:0] d3_1 = {width{1'b0}};
reg [width-1:0] d4_1 = {width{1'b0}};
//reg [width-1:0] d5_1 = {width{1'b0}};
reg [width-1:0] d1_2 = {width{1'b0}};
reg [width-1:0] d2_2 = {width{1'b0}};
reg [width-1:0] d3_2 = {width{1'b0}};
reg [width-1:0] d4_2 = {width{1'b0}};
//reg [width-1:0] d5_2 = {width{1'b0}};

// Comb stage registers

reg [width-1:0] d6_1, d_d6_1 = {width{1'b0}};
reg [width-1:0] d7_1, d_d7_1 = {width{1'b0}};
reg [width-1:0] d8_1, d_d8_1 = {width{1'b0}};
reg [width-1:0] d9_1, d_d9_1 = {width{1'b0}};
//reg [width-1:0] d10_1 =        {width{1'b0}};
reg [width-1:0] d6_2, d_d6_2 = {width{1'b0}};
reg [width-1:0] d7_2, d_d7_2 = {width{1'b0}};
reg [width-1:0] d8_2, d_d8_2 = {width{1'b0}};
reg [width-1:0] d9_2, d_d9_2 = {width{1'b0}};
//reg [width-1:0] d10_2 =        {width{1'b0}};

//reg [9:0] count = {$clog2(decimation_ratio){1'b0}};
reg [7:0] count = {8{1'b0}};
reg v_comb = 0;  // Valid signal for comb section running at output rate

initial begin
  counter <= 0;
  d1_1 <= 0;
  d2_1 <= 0;
  d3_1 <= 0;
  d4_1 <= 0;
  //d5_1 <= 0;
  d6_1 <= 0;
  d7_1 <= 0;
  d8_1 <= 0;
  d9_1 <= 0;
  //d10_1 <= 0;
  d_tmp_1 <= 0;
  d_d_tmp_1 <= 0;
  d_d6_1 <= 0;
  d_d7_1 <= 0;
  d_d8_1 <= 0;
  d_d9_1 <= 0;
  load <= 1'b1;
  d_out_1 <= {width{1'b1}};
  d1_2 <= 0;
  d2_2 <= 0;
  d3_2 <= 0;
  d4_2 <= 0;
  //d5_2 <= 0;
  d6_2 <= 0;
  d7_2 <= 0;
  d8_2 <= 0;
  d9_2 <= 0;
  //d10_2 <= 0;
  d_tmp_2 <= 0;
  d_d_tmp_2 <= 0;
  d_d6_2 <= 0;
  d_d7_2 <= 0;
  d_d8_2 <= 0;
  d_d9_2 <= 0;
  load <= 1'b1;
  d_out_2 <= {width{1'b1}};
end

always @(posedge clk_in)
begin
  // Integrator section
  d1_1 <= d1_1 + d_in_1;
  d2_1 <= d1_1 + d2_1;
  d3_1 <= d2_1 + d3_1;
  //d4_1 <= d3_1 + d4_1;
  //d5_1 <= d4_1 + d5_1;
  d1_2 <= d1_2 + d_in_2;
  d2_2 <= d1_2 + d2_2;
  d3_2 <= d2_2 + d3_2;
  //d4_2 <= d3_2 + d4_2;
  //d5_2 <= d4_2 + d5_2;
  
  // Decimation
  
  if (count == decimation_ratio - 1)
  begin
    count <= 8'b0;
    //d_tmp_1 <= d5_1;
    //d_tmp_2 <= d5_2;
    d_tmp_1 <= d3_1;
    d_tmp_2 <= d3_2;
    load <= 1'b0; // Briefly set the data trigger to 0, to pass output to the correlator
    v_comb <= 1'b1;
  end else
  begin
    load <= 1'b1;
    count <= count + 1;
    v_comb <= 1'b0;
  end
end
//end

always @(posedge clk_in)  // Comb section running at output rate
begin
  if (v_comb)
  begin
    // Comb section
    d_d_tmp_1 <= d_tmp_1;
    d_d_tmp_2 <= d_tmp_2;
    d6_1 <= d_tmp_1 - d_d_tmp_1;
    d6_2 <= d_tmp_2 - d_d_tmp_2;
    d_d6_1 <= d6_1;
    d_d6_2 <= d6_2;
    d7_1 <= d6_1 - d_d6_1;
    d7_2 <= d6_2 - d_d6_2;
    d_d7_1 <= d7_1;
    d_d7_2 <= d7_2;
    d8_1 <= d7_1 - d_d7_1;
    d8_2 <= d7_2 - d_d7_2;
    //d_d8_1 <= d8_1;
    //d_d8_2 <= d8_2;
    //d9_1 <= d8_1 - d_d8_1;
    //d9_2 <= d8_2 - d_d8_2;
    //d_d9_1 <= d9_1;
    //d_d9_2 <= d9_2;
    //d10_1 <= d9_1 - d_d9_1;
    //d10_2 <= d9_2 - d_d9_2;
    //d_out_1 <= d10_1[30:15];
    //d_out_2 <= d10_2[30:15];
    //d_out_2 <= d8_2[24:9];
    d_out_2 <= d8_2[31:0];
    if (counter == 511)
    begin
      //d_out_1 <= {16{1'b1}};
      d_out_1 <= {32{1'b1}};
      counter <= 10'b0;
    end else begin
      counter <= counter + 1;
      //d_out_1 <= d8_1[24:9];
      d_out_1 <= d8_1[31:0];
    end
  end
end
endmodule

//--- Serial comms module
module serialtransmission(input wire        clk,    //-- System clock (12 MHz on ICEstick)
                          input wire        d_clk,  //-- Load signal, transmission active when this is 1
	                  input wire [31:0] d_in_1, //-- 8-bit data from CIC filter, loaded when d_clk = 0
	                  input wire [31:0] d_in_2, //-- 8-bit data from CIC filter, loaded when d_clk = 0
                          output wire       tx      //-- Data out port to PC
              );

//-- Parameter: baud rate
parameter BAUD =  `B800000; // Should give us some margin for 46875 x 10 bits/s...
//parameter BAUD =  `B400000; // Works...
//parameter BAUD =  `B115200; // Works.

reg [9:0] counter = 0;
reg [39:0] data = 40'b1000000000100000000010000000001000000000;
//reg [9:0] data = 10'b1000000000;
reg load;
reg start;
reg transmitting;

//-- Data clock
wire clk_baud;

//-- When d_clk is 0, load the 8 bits into the frame for transmission
//-- When d_clk is 1, increase our counter to keep track of which bit to send
// This block should run at a higher rate than the baud clock gives! This is
// because the 'load' signal is only active for a very short time interval,
// specifically for only one cycle of the 3 MHz clock for every audio sample interval.
// We should however leave the baud clock running the counter for the
// transmission data.

always @(posedge clk)
begin
  load <= d_clk;
  if (transmitting == 1) start <= 0;
  if (load == 0)
  begin
    data <= {1'b1, d_in_1[23:16], 1'b0, 1'b1, d_in_1[15:8], 1'b0, 1'b1, d_in_2[23:16], 1'b0, 1'b1, d_in_2[15:8], 1'b0};  // Pad our bytes with a start bit (0) and a stop bit (1)
    if (transmitting == 0) start <= 1;
  end
end

always @(posedge clk_baud)
begin
  if (start == 1)
  begin
    counter <= 0;     // Reset our counter so we can keep track of bits to send
    transmitting <= 1;
  end
  if (transmitting)
  begin
    if (counter < 40) counter <= counter + 1; // Go to the next bit
    else
    begin
      transmitting <= 0;
      counter <= 0;
    end
  end
end

//-- Send a data frame if d_clk = 1 and counter is low enough (we only send 10 bits per
//   packet)
//-- When we are in loading mode (d_clk = 0), send out a '1' so that the line
//   remains idle. 
//   The first bit to be sent out is a 0. This is the start bit!
//   The stop bit is the last bit to be sent, and is a 1.
//   I have added an additional condition, as we don't want to repeat the
//   sending of the 8-bit sample.
assign tx = (transmitting && counter < 40) ? data[counter] : 1;

//-- Divider for data clock, use this module inside the current module
// Note that the 'M' parameter inside the 'divider' module is overwritten
// here by the value of the BAUD variable.
divider #(BAUD) BAUD0 ( .clk_in(clk), .clk_out(clk_baud));

endmodule
