`timescale 1ns / 1ps
`include "nfc_param.vh"
/* 
2025.11.14 SCMI ZGX 
保留基本的 3000 读操作。 
主要简化： 
移除的功能： 列读（E005） 多平面读（3200） 缓存读（31, 3F, E006） 
相关输入：i_col_num, i_col_addr_len 
简化状态机： 仅保留 IDLE、READ、WAIT 三个状态 
移除 FIRST_TWO、COLUMN、CRCE_ONE、CRCE_TWO、MPR、CACHE_LAST 只使用 3000 命令： 
所有读操作使用 16'h3000 支持连续多页读取，每次递增一页地址 
*/
module schedule_read(
    input                     clk,
    input                     rst,
    output                    o_cmd_ready,
    input                     i_cmd_valid,
    input  [15 : 0]           i_rcmd_id,
    input  [47 : 0]           i_raddr,    // LBA
    input  [23 : 0]           i_rlen,     // total read length in bytes
    
    input                     i_page_buf_ready,
    input                     i_page_cmd_ready,

    output reg                o_page_cmd_valid,
    output reg [15 : 0]       o_page_cmd,
    output reg                o_page_cmd_last,
    output reg [15 : 0]       o_page_cmd_id,
    output reg [47 : 0]       o_page_addr,
    output reg [31 : 0]       o_page_cmd_param
);

// Simple read FSM
localparam
    IDLE = 2'b01,
    READ = 2'b10,
    WAIT = 2'b11;

reg  [1:0]  state;
reg  [47:0] read_addr;
reg  [23:0] remain_len;

wire [15:0] page_size;
assign page_size = `PAGE_UTIL_BYTE;      // usable bytes per page
assign o_cmd_ready = (state == IDLE) & i_page_cmd_ready;

// =============================================================================
// FSM
// =============================================================================

always @(posedge clk or posedge rst)
if (rst) begin
    state             <= IDLE;
    read_addr         <= 48'd0;
    remain_len        <= 24'd0;

    o_page_cmd_valid  <= 1'b0;
    o_page_cmd        <= 16'h0;
    o_page_cmd_last   <= 1'b0;
    o_page_cmd_id     <= 16'h0;
    o_page_addr       <= 48'd0;
    o_page_cmd_param  <= 32'd0;

end else begin

    case (state)

        IDLE: begin
            o_page_cmd_valid <= 1'b0;

            if (i_cmd_valid) begin
                read_addr  <= i_raddr;
                remain_len <= i_rlen;
                state      <= READ;
            end
        end

        READ: begin
            if (i_page_cmd_ready && i_page_buf_ready) begin
                
                // ---------- 1. Param ----------
                if (remain_len <= page_size) begin
                    // last partial page or exact last page
                    o_page_cmd_last  <= 1'b1;
                    o_page_cmd_param <= {remain_len[15:0], 12'h800, 3'h6, 1'b1};
                end else begin
                    // full page
                    o_page_cmd_last  <= 1'b0;
                    o_page_cmd_param <= {page_size, 12'h800, 3'h6, 1'b1};
                end

                // ---------- 2. Command ----------
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'h3000;
                o_page_cmd_id    <= i_rcmd_id;
                o_page_addr      <= read_addr;

                // ---------- 3. Update remain_len after issuing ----------
                if (remain_len <= page_size)
                    remain_len <= 24'd0;
                else
                    remain_len <= remain_len - page_size;

                // ---------- 4. Next page address ----------
                read_addr <= read_addr + 48'h10000;   // next page row

                // go to WAIT
                state <= WAIT;
            end
        end

        WAIT: begin
            o_page_cmd_valid <= 1'b0;

            if (!i_page_cmd_ready) begin
                if (remain_len == 0)
                    state <= IDLE;
                else
                    state <= READ;
            end
        end

    endcase

end

endmodule
