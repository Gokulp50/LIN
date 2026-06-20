`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.04.2026 14:45:33
// Design Name: 
// Module Name: lin_controller
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

module lin_controller #(
    parameter CLOCK_FREQ = 100_000_000, // 100 MHz System Clock
    parameter BAUD_RATE  = 20_000       // 20 kbps LIN Baud Rate
)(
    input  logic       clk,
    input  logic       rstn,

    // Physical LIN Bus Interface
    input  logic       lin_rx_in,      // Serial input from physical transceiver
    output logic       lin_tx_out,     // Serial output to physical transceiver

    // CPU / Application Layer Interface (Transmitter)
    input  logic       start_transmit, // Pulse to start a frame
    input  logic       master_mode,    // 1 = Master, 0 = Slave
    input  logic       send_break,     // Send Break Field
    input  logic [7:0] tx_pid,         // Frame ID to send
    input  logic       enhanced_cs,    // 1 = Enhanced, 0 = Classic Checksum
    input  logic [2:0] tx_data_count,  // Number of bytes (0-7, where 0=1 byte)
    input  logic [7:0] tx_data,        // Data byte pushed from CPU
    input  logic       tx_data_valid,  // CPU says data is ready
    output logic       tx_data_ready,  // Controller asks CPU for next byte
    output logic       tx_busy,        // Controller is currently sending
    output logic       tx_done,        // Transmission complete

    // CPU / Application Layer Interface (Receiver)
    output logic       rx_break_det,   // Controller detected a Break field
    output logic [7:0] rx_data,        // Byte received from bus
    output logic       rx_data_valid,  // Pulse when rx_data is valid
    output logic       rx_error        // Framing error detected
);

    //========================================================================
    // 1. Baud Rate Generator (Using YOUR module!)
    //========================================================================
    localparam logic [15:0] BDIV_VALUE = CLOCK_FREQ / (BAUD_RATE * 16);

    logic tx_tick, rx_tick;

    lin_baud_gen #(
        .SYS_CLK_FREQ(CLOCK_FREQ)
    ) baud_generator (
        .clk(clk),
        .rstn(rstn),
        .bdiv(BDIV_VALUE), // Pass the calculated 312 divider into your module
        .rx_tick(rx_tick),
        .tx_tick(tx_tick)
    );

    //========================================================================
    // 2. Transmitter FSM Instantiation
    //========================================================================
    lin_tx transmitter (
        .clk            (clk),
        .rstn           (rstn),
        .tx_tick        (tx_tick),
        
        .start_transmit (start_transmit),
        .master_mode    (master_mode),
        .send_break     (send_break),
        .pid            (tx_pid),
        .enhanced_cs    (enhanced_cs),
        .data_count     (tx_data_count),
        
        .tx_data        (tx_data),
        .tx_data_valid  (tx_data_valid),
        .tx_data_ready  (tx_data_ready),
        
        .tx_busy        (tx_busy),
        .tx_done        (tx_done),
        .lin_tx         (lin_tx_out)
    );

    //========================================================================
    // 3. Receiver FSM Instantiation
    //========================================================================
    lin_rx receiver (
        .clk            (clk),
        .rstn           (rstn),
        .rx_tick        (rx_tick),
        .lin_rx         (lin_rx_in),
        
        .break_flag     (rx_break_det),
        .rx_byte        (rx_data),
        .rx_done        (rx_data_valid),
        .framing_error  (rx_error)
    );

endmodule
