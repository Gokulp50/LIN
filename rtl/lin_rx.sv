`timescale 1ns / 1ps

module lin_rx (
    input  logic       clk,
    input  logic       rstn,
    input  logic       rx_tick,
    input  logic       lin_rx,
    
    output logic       break_flag,
    output logic [7:0] rx_byte,
    output logic       rx_done,
    output logic       framing_error
);

    typedef enum logic [2:0] {
        IDLE, 
        WAIT_START, 
        SAMPLE_DATA, 
        WAIT_STOP,
        CHECK_BREAK,
        CHECK_BREAK_DELIM,
        BREAK_TIMEOUT
    } state_t;
    
    state_t state;
    logic [7:0] tick_count;
    logic [7:0] bit_count;
    logic [4:0] delim_count;
    logic [7:0] shift_reg;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state         <= IDLE;
            tick_count    <= 0;
            bit_count     <= 0;
            delim_count   <= 0;
            shift_reg     <= 0;
            break_flag    <= 0;
            rx_byte       <= 0;
            rx_done       <= 0;
            framing_error <= 0;
        end else begin
            break_flag    <= 0;
            rx_done       <= 0;
            framing_error <= 0;
            
            case (state)
                IDLE: begin
                    if (lin_rx == 1'b0) begin
                        state <= WAIT_START;
                        tick_count <= 0;
                    end
                end
                
                WAIT_START: begin
                    if (rx_tick) begin
                        tick_count <= tick_count + 1;
                        if (tick_count == 7) begin 
                            if (lin_rx == 1'b0) begin
                                tick_count <= 0;
                                bit_count  <= 0;
                                state      <= SAMPLE_DATA;
                            end else begin
                                state <= IDLE;
                            end
                        end
                    end
                end
                
                SAMPLE_DATA: begin
                    if (rx_tick) begin
                        tick_count <= tick_count + 1;
                        if (tick_count == 15) begin 
                            tick_count <= 0;
                            shift_reg  <= {lin_rx, shift_reg[7:1]}; 
                            bit_count  <= bit_count + 1;
                            
                            if (bit_count == 7) begin
                                state <= WAIT_STOP;
                            end
                        end
                    end
                end
                
                WAIT_STOP: begin
                    if (rx_tick) begin
                        tick_count <= tick_count + 1;
                        if (tick_count == 15) begin
                            tick_count <= 0;
                            if (lin_rx == 1'b1) begin
                                rx_byte <= shift_reg;
                                rx_done <= 1'b1;
                                state   <= IDLE;
                            end else begin
                                if (shift_reg == 8'h00) begin
                                    state     <= CHECK_BREAK;
                                    bit_count <= 10; 
                                end else begin
                                    framing_error <= 1'b1;
                                    state         <= BREAK_TIMEOUT;
                                end
                            end
                        end
                    end
                end

                CHECK_BREAK: begin
                    if (rx_tick) begin
                        tick_count <= tick_count + 1;
                        if (tick_count == 15) begin 
                            tick_count <= 0;
                            bit_count  <= bit_count + 1;
                            if (bit_count == 31) state <= BREAK_TIMEOUT;
                        end
                    end
                    
                    if (lin_rx == 1'b1) begin
                        if (bit_count >= 13) begin
                            state       <= CHECK_BREAK_DELIM;
                            delim_count <= 0;
                            tick_count  <= 0;
                        end else begin
                            state <= IDLE; 
                        end
                    end
                end
                
                CHECK_BREAK_DELIM: begin
                    if (rx_tick) begin
                        tick_count <= tick_count + 1;
                        if (tick_count == 15) begin
                            tick_count  <= 0;
                            delim_count <= delim_count + 1;
                        end
                    end
                    
                    if (lin_rx == 1'b0) begin
                        if (delim_count >= 1) begin
                            break_flag <= 1'b1;
                            state      <= WAIT_START; 
                            tick_count <= 0;
                        end else begin
                            framing_error <= 1'b1;
                            state         <= IDLE;
                        end
                    end
                    
                    if (delim_count >= 2) begin
                        break_flag <= 1'b1;
                        state      <= IDLE;
                    end
                end

                BREAK_TIMEOUT: begin
                    if (lin_rx == 1'b1) state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule