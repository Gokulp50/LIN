`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.03.2026 21:52:29
// Design Name: lin_21_protocol
// Module Name: lin_baud_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:01
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lin_baud_gen #( 
parameter SYS_CLK_FREQ = 50_000_000 ) // Assuming the hardware clk rate is 50Mhz
(
    input  logic clk,          // high speed sys clk    
    input  logic rstn,         // active low rst
    input  logic [15:0] bdiv,  // programmable baud divider from Master
    output logic rx_tick,      //16x oversampled tick from the reciver
    output logic tx_tick       // 1x tick for the transmitter
);

// Internal counters
logic [15:0] rx_acc;
logic [3:0]  tx_acc;

// rx tick generator
always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rx_acc  <= 16'd0;
        rx_tick <= 1'b0; 
    end else begin
        if (rx_acc >= (bdiv - 1)) begin
            rx_acc  <= 16'd0;
            rx_tick <= 1'b1; // Generate the pulse!
        end else begin
            rx_acc  <= rx_acc + 1'b1;
            rx_tick <= 1'b0;
        end
    end
end

// tx tick genration (1x baud rate)
// The transmitter only needs to shift 1 bit out per bit-time,
// so we just count 16 RX ticks to make 1 TX tick.
always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx_acc  <= 4'd0;
            tx_tick <= 1'b0;
        end else if (rx_tick) begin
            if (tx_acc == 4'd15) begin
                tx_acc  <= 4'd0;
                tx_tick <= 1'b1; // Generate pulse for TX
            end else begin
                tx_acc  <= tx_acc + 1'b1;
                tx_tick <= 1'b0;
            end
        end else begin
            tx_tick <= 1'b0;
        end
    end
endmodule
