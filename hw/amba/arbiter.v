module arbiter #(
  N_MASTER = 1
) (
  input   [N_MASTER - 1 : 0] request,
  output  [N_MASTER - 1 : 0] grant  
);

  genvar i;
  assign grant[0] = request[0];
  generate
    for (i = 1; i < N_MASTER; i = i + 1) begin : grant_gen
      assign grant[i] = ~(|request[i - 1 : 0]) & request[i];
    end
  endgenerate
  
endmodule