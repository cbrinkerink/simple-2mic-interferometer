// This file contains a module with a 5-stage CIC filter (from https://github.com/ericgineer/CIC/blob/master/CIC.v),
// and a serial transmission module to send the filtered data to PC.
//
// If we set the output width of this CIC filter to 8 bits, we can send the
// output data as characters over the serial link without needing to fiddle
// with multi-byte data points (yet).

// List of inputs:

// clk              (for CIC filter)  3 MHz clock
// d_in             (for CIC filter)  1-bit line from PDM microphone
// load             (for serial)
// clk_in           (for divider)     12 MHz system clock
// clk              (for serial)      Baud rate clock, 500 kHz should be okay
//                                    (10 bits x 46875 samples/sec plus some margin)

// List of outputs:

// d_out            (from CIC filter) 8-bit data
// d_clk            (from CIC filter) 46875 Hz clock. Needed?
// load             (from CIC filter) Only low for a brief time interval, when
//                                    the 8-bit data is to be transferred into
//                                    the serial shift register.
// clk_out          (from divider)    500 kHz for serial
// tx               (from serial)     1-bit serial data

`timescale 1ns/1ns
`default_nettype none
`include "baudgen.vh"

module top (input wire clk,
	    input wire mic_data,
            output wire serial_tx,
	    output wire mic_clk,
            output wire serial_split);

wire [7:0] CIC_to_serial;
wire load_data;

wire clk_3MHz;
assign mic_clk = clk_3MHz;

wire serial_conn;
assign serial_tx = serial_conn;
// Split out the serial output for testing
assign serial_split = serial_conn;

// Clock divider for PDM 3 MHz
divider #(4) PDM1 ( .clk_in(clk), .clk_out(clk_3MHz));

// CIC filter accepting 1-bit PDM input and generating 8-bit filtered
// & decimated output
CICfilter #(64) CIC1 ( .clk_in(clk_3MHz), .d_in(mic_data), .d_out(CIC_to_serial), .load(load_data));

// Serial comms
serialtransmission SERIAL1 (.clk(clk), .d_clk(load_data), .d_in(CIC_to_serial), .tx(serial_conn));

endmodule

// I still need to take a critical look at the required width parameter here.
// I am not sure I actually need 12 bits, we might make do with fewer.
// I have set it to 8 bits for now.
module CICfilter #(parameter width = 12)
		       (input wire       clk_in,
			input wire       d_in,
			output reg [7:0] d_out,
		        output reg       load);

parameter decimation_ratio = 64; // From 3 MHz to 46875 Hz

reg [width-1:0] d_tmp, d_d_tmp;

// Integrator stage registers

reg [width-1:0] d_prep = {width{1'b0}};
reg [width-1:0] d1 = {width{1'b0}};
reg [width-1:0] d2 = {width{1'b0}};
reg [width-1:0] d3 = {width{1'b0}};
reg [width-1:0] d4 = {width{1'b0}};
reg [width-1:0] d5 = {width{1'b0}};

// Comb stage registers

reg [width-1:0] d6, d_d6 = {width{1'b0}};
reg [width-1:0] d7, d_d7 = {width{1'b0}};
reg [width-1:0] d8, d_d8 = {width{1'b0}};
reg [width-1:0] d9, d_d9 = {width{1'b0}};
reg [width-1:0] d10 =      {width{1'b0}};

reg [15:0] count = 16'b0;
reg v_comb = 0;  // Valid signal for comb section running at output rate

initial begin
  d1 <= 0;
  d2 <= 0;
  d3 <= 0;
  d4 <= 0;
  d5 <= 0;
end

always @(posedge clk_in)
begin
  // Integrator section
  d1 <= d1 + d_in;
  //if (d_in == 0) d_prep = 12'b111111100000;
  //else d_prep = 12'b000000100000;
  //d1 <= d1 + d_prep;
  d2 <= d1 + d2;
  d3 <= d2 + d3;
  d4 <= d3 + d4;
  d5 <= d4 + d5;
  
  // Decimation
  
  if (count == decimation_ratio - 1)
  begin
    count <= 16'b0;
    d_tmp <= d5;
    load <= 1'b0; // Briefly set the data trigger to 0,
                       // for loading an output
                       // into the shift register
     	               // of the serial comms
    	               // module
    v_comb <= 1'b1;
  end else if (count < 8)
  begin
    load <= 1'b0; // Keep the data trigger low a little longer,
                  // as the baud clock runs more slowly than
                  // the 3 MHz PDM input clock used here.
    count <= count + 16'd1;
    v_comb <= 1'b0;
  end else
  begin
    load <= 1'b1;
    count <= count + 16'd1;
    v_comb <= 1'b0;
  end
end
//end

always @(posedge clk_in)  // Comb section running at output rate
begin
  begin
    if (v_comb)
    begin
      // Comb section
      d_d_tmp <= d_tmp;
      d6 <= d_tmp - d_d_tmp;
      d_d6 <= d6;
      d7 <= d6 - d_d6;
      d_d7 <= d7;
      d8 <= d7 - d_d7;
      d_d8 <= d8;
      d9 <= d8 - d_d8;
      d_d9 <= d9;
      d10 <= d9 - d_d9;
      //d_out <= d10 >>> (width - 8); // This 'gain' likely needs to be changed...
      //d_out <= d10[30:23]; // This 'gain' likely needs to be changed...
      d_out <= d10[26:19]; // This 'gain' likely needs to be changed...
    end
  end
end								
endmodule


// Divider module
module divider(input wire clk_in, output wire clk_out);

parameter M = 104;

localparam N = $clog2(M);
reg [N-1:0] divcounter = 0;

always @(posedge clk_in)
  divcounter <= (divcounter == M - 1) ? 0 : divcounter + 1;

assign clk_out = divcounter[N-1];

endmodule

//--- Serial comms module
module serialtransmission(input wire         clk, //-- System clock (12 MHz on ICEstick)
                          input wire       d_clk, //-- Load signal, transmission active when this is 1
	                  input wire [7:0]  d_in, //-- 8-bit data from CIC filter, loaded when d_clk = 0
                          output wire         tx  //-- Data out port to PC
              );

//-- Parameter: baud rate
parameter BAUD =  `B800000; // Should give us some margin for 46875 x 10 bits/s...
//parameter BAUD =  `B400000; // Works...
//parameter BAUD =  `B115200; // Works.

reg [8:0] counter = 0;
reg [9:0] data = 10'b1000000000;
reg load;

//-- Data clock
wire clk_baud;

//-- When d_clk is 0, load the 8 bits into the frame for transmission
//-- When d_clk is 1, increase our counter to keep track of which bit to send
always @(posedge clk_baud)
begin
  load <= d_clk;
  if (load == 0)
  begin
    data <= {1'b1,d_in,1'b0};  // Pad our byte with a start bit (0) and a stop bit (1)
    counter <= 0;     // Reset our counter so we can keep track of bits to send
  end else
    counter <= counter + 1; // Go to the next bit
end

//-- Send a data frame if d_clk = 1 and counter is low enough (we only send 10 bits per
//   packet)
//-- When we are in loading mode (d_clk = 0), send out a '1' so that the line
//   remains idle. 
//   The first bit to be sent out is a 0. This is the start bit!
//   The stop bit is the last bit to be sent, and is a 1.
//   I have added an additional condition, as we don't want to repeat the
//   sending of the 8-bit sample.
assign tx = (load && counter < 10) ? data[counter] : 1;

//-- Divider for data clock, use this module inside the current module
// Note that the 'M' parameter inside the 'divider' module is overwritten
// here by the value of the BAUD variable.
divider #(BAUD) BAUD0 ( .clk_in(clk), .clk_out(clk_baud));

endmodule
