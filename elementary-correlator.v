// This module builds on the elementary CIC filter (PDM-mic-readout).
// Here, we will read in two MEMS microphones, filter their signals,
// and put them through a simple lag correlator.

// Steps for upgrade:
// - Add mic clock output and mic data input
// - duplicate the CIC filter for the second mic
// - Add lag correlator
// - Connect lag correlator to serial output in some way
// Thoughts on the cadence of correlator operations:
// The correlator gets 2 new audio samples at a rate of 46875 Hz.
// Within one audio sample time, the correlator needs to perform 2 shifts,
// one for each lag buffer, and after each shift the correlation products need
// to be added to the relevant registers.
// We need to decide the time frame over which the correlation products get
// integrated, and the cadence with which they then get transmitted to the
// serial connection.
// The data output of the CIC filters gets updated once every audio sample
// period, at the time resolution of the PDM clock frequency.


`timescale 1ns/1ns
`default_nettype none
`include "baudgen.vh"

module top (input wire clk,
	    input wire mic_data_1,
	    input wire mic_data_2,
            output wire serial_tx,
	    output wire mic_clk_1,
	    output wire mic_clk_2,
            output wire serial_split);

wire [17:0] CIC_to_correlator_1;
wire [17:0] CIC_to_correlator_2;
wire correlated_data;
wire load_data_1;

(* keep="soft" *)
wire load_data_2;

wire clk_3MHz;

assign mic_clk_1 = clk_3MHz;
assign mic_clk_2 = clk_3MHz;

//wire serial_conn;
assign serial_tx = correlated_data;
// Split out the serial output for testing
assign serial_split = correlated_data;

// Clock divider for PDM 3 MHz
divider #(4) PDM1 ( .clk_in(clk), .clk_out(clk_3MHz));

// CIC filter2 accepting 1-bit PDM input and generating 8-bit filtered
// & decimated output
CICfilter #(64) CIC1 ( .clk_in(clk_3MHz), .d_in(mic_data_1), .d_out(CIC_to_correlator_1), .load(load_data_1));
CICfilter #(64) CIC2 ( .clk_in(clk_3MHz), .d_in(mic_data_2), .d_out(CIC_to_correlator_2), .load(load_data_2));

// Lag correlator, accepts the output from 2 CICfilters
lagcorrelator LAG1 ( .clk_in(clk), .d_in_1(CIC_to_correlator_1), .d_in_2(CIC_to_correlator_2), .sample_ready(load_data_1), .data_out(correlated_data));

// Serial comms
serialtransmission SERIAL1 (.clk(clk), .d_clk(load_data), .d_in(correlated_data), .tx(serial_conn));

endmodule

// I still need to take a critical look at the required width parameter here.
// I am not sure I actually need 12 bits, we might make do with fewer.
// I have set it to 8 bits for now.
module CICfilter #(parameter width = 64)
		       (input wire        clk_in,
			input wire        d_in,
			output reg [17:0] d_out,
		        output reg        load);

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
  d6 <= 0;
  d7 <= 0;
  d8 <= 0;
  d9 <= 0;
  d10 <= 0;
  d_tmp <= 0;
  d_d_tmp <= 0;
  d_d6 <= 0;
  d_d7 <= 0;
  d_d8 <= 0;
  d_d9 <= 0;
  load <= 1'b1;
  d_out <= 18'b0;
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
    load <= 1'b0; // Briefly set the data trigger to 0, to pass output to the correlator
    v_comb <= 1'b1;
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

      // !!!!! NOTE: The line below originally tried to stuff 64 bits into 8 bits !!!!!!
      // I have fixed the width of the output register to 64 bits now, which
      // hopefully helps.
      // !!!!! Second NOTE: the multipliers on the ECP5 are 18x18 bits, so to
      // be efficient I will likely need to limit the bit ranges to send
      // there. The accepted bit widths for the correlator will therefore also
      // need to be changed to 18 bits.
      //d_out <= d10[30:13];
      d_out <= d10[17:0];
    end
  end
end								
endmodule

// Lag correlator
module lagcorrelator( input  wire        clk_in,
	              input  wire [17:0] d_in_1,
		      input  wire [17:0] d_in_2,
		      input  wire  sample_ready,
		      output wire      data_out);

// Define internal lag registers, accumulators and wires here

reg [17:0] hold_1 = 18'b0;
reg [17:0] hold_2 = 18'b0;

reg [17:0] d1_1 = 18'b0;
reg [17:0] d1_2 = 18'b0;
reg [17:0] d1_3 = 18'b0;
reg [17:0] d1_4 = 18'b0;
reg [17:0] d1_5 = 18'b0;
reg [17:0] d2_1 = 18'b0;
reg [17:0] d2_2 = 18'b0;
reg [17:0] d2_3 = 18'b0;
reg [17:0] d2_4 = 18'b0;
reg [17:0] d2_5 = 18'b0;
// product registers
reg [35:0] prod0 = 36'b0;
reg [35:0] prod1 = 36'b0;
reg [35:0] prod2 = 36'b0;
reg [35:0] prod3 = 36'b0;
reg [35:0] prod4 = 36'b0;
reg [35:0] prod5 = 36'b0;
reg [35:0] prod6 = 36'b0;
reg [35:0] prod7 = 36'b0;
reg [35:0] prod8 = 36'b0;
reg [35:0] prod9 = 36'b0;
//reg [63:0] lags[9:0]; // 10 lag registers, 64 bits wide each
reg [63:0] lags0 = 64'b0;
reg [63:0] lags1 = 64'b0;
reg [63:0] lags2 = 64'b0;
reg [63:0] lags3 = 64'b0;
reg [63:0] lags4 = 64'b0;
reg [63:0] lags5 = 64'b0;
reg [63:0] lags6 = 64'b0;
reg [63:0] lags7 = 64'b0;
reg [63:0] lags8 = 64'b0;
reg [63:0] lags9 = 64'b0;
reg [639:0] lagbuffer = 640'b0;
reg load;
reg loaded;

reg [7:0] counter = 8'b0; // counter starting at each new audio sample, ticking up with every (12 MHz) clock cycle
reg [11:0] sample_counter = 12'b0; // This counter counts up with every new audio sample processed, and resets after trans-
                                   // mission of the most recent correlation results.
reg transfer_active = 1'b0;         // Indicates whether serial data transfer is active or not
reg [9:0] transfer_counter = 10'b0; // counts bits sent during transfer

initial begin
  lags9 = 64'b0;
  lags8 = 64'b0;
  lags7 = 64'b0;
  lags6 = 64'b0;
  lags5 = 64'b0;
  lags4 = 64'b0;
  lags3 = 64'b0;
  lags2 = 64'b0;
  lags1 = 64'b0;
  lags0 = 64'b0;
  prod9 = 36'b0;
  prod8 = 36'b0;
  prod7 = 36'b0;
  prod6 = 36'b0;
  prod5 = 36'b0;
  prod4 = 36'b0;
  prod3 = 36'b0;
  prod2 = 36'b0;
  prod1 = 36'b0;
  prod0 = 36'b0;
  loaded = 1'b0;
  hold_1 = 18'b0;
  hold_2 = 18'b0;
end

always @(posedge clk_in)
// Do things depending on whether new audio data is coming in and the internal
// counter state
begin
  counter <= counter + 1;
  if (sample_ready == 0 && loaded == 0)
  begin
    counter <= 0; // Reset our counter when a new audio sample becomes available
    sample_counter <= sample_counter + 1; // increment our sample counter to reset our integration period
    // !!! There is still something wrong with the timing here:
    // the hold registers do not get good sample data when sample_ready is set to 0.
    // Perhaps this has to do with the initial output from the CIC filters,
    // they have a delay when starting from their initial state too. To be
    // investigated.
    hold_1 <= d_in_1;
    hold_2 <= d_in_2;
    // Reset our lagbuffer here too
    lagbuffer <= 640'b0;
    loaded = 1;
  end else if (counter == 1)
  begin
    // Now, we have loaded our audio samples and we move on to internal
    // processing of these samples.
    // Shift input 1 to accommodate the new sample
    d1_5 <= d1_4;
    d1_4 <= d1_3;
    d1_3 <= d1_2;
    d1_2 <= d1_1;
    d1_1 <= hold_1;
  end else if (counter == 2)
  // One clock cycle later, we can calculate all the new odd products.
  begin
    prod9 <= d1_1 * d2_5;
    prod7 <= d1_2 * d2_4;
    prod5 <= d1_3 * d2_3;
    prod3 <= d1_4 * d2_2;
    prod1 <= d1_5 * d2_1;
  end else if (counter == 3)
  begin
    // Shift input 2 to accommodate the new sample
    d2_5 <= d2_4;
    d2_4 <= d2_3;
    d2_3 <= d2_2;
    d2_2 <= d2_1;
    d2_1 <= hold_2;
  end else if (counter == 4)
  begin
    // Calculate correlation products for all even lags
    prod8 <= d1_1 * d2_5;
    prod6 <= d1_2 * d2_4;
    prod4 <= d1_3 * d2_3;
    prod2 <= d1_4 * d2_2;
    prod0 <= d1_5 * d2_1;
  end else if (counter == 5)
  begin
    // Now integrate all lags using the prepared products
    lags9 <= lags9 + prod9;
    lags8 <= lags8 + prod8;
    lags7 <= lags7 + prod7;
    lags6 <= lags6 + prod6;
    lags5 <= lags5 + prod5;
    lags4 <= lags4 + prod4;
    lags3 <= lags3 + prod3;
    lags2 <= lags2 + prod2;
    lags1 <= lags1 + prod1;
    lags0 <= lags0 + prod0;
  end else if (counter == 100)
  begin
    // To indicate we are done with processing the latest audio samples and
    // ready to begin again
    loaded = 0;
  end
  // Add steps for transmission of data here
  // Avoid doing stuff at the same time as the earlier two time steps!
  if (counter == 6 && sample_counter == 3125) // gives 15 integrations per second
  begin
    // Copy our accumulated values to our buffer for safe keeping
    lagbuffer[639:576] <= lags9;
    lagbuffer[575:512] <= lags8;
    lagbuffer[511:448] <= lags7;
    lagbuffer[447:384] <= lags6;
    lagbuffer[383:320] <= lags5;
    lagbuffer[319:256] <= lags4;
    lagbuffer[255:192] <= lags3;
    lagbuffer[191:128] <= lags2;
    lagbuffer[127:64] <= lags1;
    lagbuffer[63:0] <= lags0;
  end else if (counter == 7 && sample_counter == 3125)
  begin
    // Empty the individual lag buffers themselves
    lags9 <= 0;
    lags8 <= 0;
    lags7 <= 0;
    lags6 <= 0;
    lags5 <= 0;
    lags4 <= 0;
    lags3 <= 0;
    lags2 <= 0;
    lags1 <= 0;
    lags0 <= 0;
    // Now, we can start outputting all the bytes from this big buffer in
    // sequence on the following clock cycles!
  end
  if (counter == 7 && sample_counter == 3125)
  begin
    transfer_active <= 1'b1;
    transfer_counter <= 1'b0;
  end
  if (transfer_active == 1)
  begin
    transfer_counter <= transfer_counter + 1;
  end
  if (transfer_counter == 640)
  begin
    transfer_active <= 0;
    transfer_counter <= 0;
    sample_counter <= 0;
  end
end

assign data_out = (transfer_active == 1 && transfer_counter < 640) ? lagbuffer[transfer_counter] : 1;

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
