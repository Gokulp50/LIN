`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.04.2026 12:11:38
// Design Name: 
// Module Name: lin_checksum
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module lin_checksum (
    input  logic       clk,
    input  logic       rstn,
    
    // Control Signals (From Protocol FSM)
    input  logic       start_frame,  // Pulses high at the start of a new LIN frame
    input  logic       enhanced,     // 1 = Enhanced (PID + Data), 0 = Classic
    input  logic [7:0] pid,          // The Protected ID
    
    // Data Stream (From UART RX or TX buffer)
    input  logic       data_valid,   // Pulses high when a new data_byte is ready
    input  logic [7:0] data_byte,    // The incoming data byte to add
    
    // Continuous Output
    output logic [7:0] checksum      // The current inverted modulo-256 result
);

    logic [8:0] sum;      // 9-bit accumulator to catch the carry (bit 8)
    logic [8:0] next_sum; // Combinational look-ahead

    //---------------------------------------------------------
    // Combinational: Inverted Modulo-256 Addition
    //---------------------------------------------------------
    always_comb begin
        // Add the current 8-bit sum to the new incoming data byte
        next_sum = sum[7:0] + data_byte;
        
        // If the addition caused a 9th bit carry, add it back to the bottom!
        if (next_sum[8] == 1'b1) begin
            next_sum = next_sum + 1'b1;
        end
    end

    //---------------------------------------------------------
    // Sequential: The Running Total (Accumulator)
    //---------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sum <= 9'h000;
        end else if (start_frame) begin
            // Initialize the accumulator for a new frame
            if (enhanced) begin
                sum <= {1'b0, pid}; // Enhanced starts with the PID already loaded
            end else begin
                sum <= 9'h000;      // Classic starts at 0
            end
        end else if (data_valid) begin
            // Accumulate the new byte into the running total
            sum <= next_sum;
        end
    end

    // The final LIN checksum is ALWAYS the bitwise inversion (~) of the lower 8 bits
    assign checksum = ~sum[7:0];

endmodule
