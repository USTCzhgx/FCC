module pluse_sync(
    input rst,
    input clk,
    input signal_in,
    output signal_out
);

reg sig_1, sig_2;

always @(posedge clk) begin
    if(~rst) begin
        sig_1 <= 1'b0;
        sig_2 <= 1'b0;
    end else begin
        sig_1 <= signal_in;
        sig_2 <= sig_1;
    end
end

assign signal_out = sig_2;

endmodule