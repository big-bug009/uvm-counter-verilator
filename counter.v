module counter (
  input clk,
  input rst_n,
  input en,
  output reg [7:0] count
);

  always @(posedge clk) begin
    if (rst_n == 0)
      count <= 0;
    else if (en == 1)
      count <= count + 1;
  end

endmodule
