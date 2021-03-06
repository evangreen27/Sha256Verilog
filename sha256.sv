module sha256(
input logic 				clk, reset_n, start, 
input logic 	[31:0] 	message_addr, size, output_addr,
output logic 				done, mem_clk, mem_we,
output logic 	[15:0] 	mem_addr,
output logic 	[31:0] 	mem_write_data,
input logic 	[31:0]	mem_read_data);
					
enum logic [3:0] {IDLE=4'b000, PREP=4'b0001, PREP2=4'b0010, INITIAL=4'b0011, LOOP=4'b0100, DELAY=4'b0101, INITW=4'b0110, PRECOMP=4'b0111, READ=4'b1000, PUSH=4'b1001, WRITER=4'b1010} state;

assign mem_clk = clk;

logic   [ 31:0] h0;
logic   [ 31:0] h1;
logic   [ 31:0] h2;
logic   [ 31:0] h3;
logic   [ 31:0] h4;
logic   [ 31:0] h5;
logic   [ 31:0] h6;
logic   [ 31:0] h7;
logic   [ 31:0] t;

logic   [ 31:0] a, b, c, d, e, f, g, h;

logic   [ 31:0] w[0:15];

int pad_length, outloop;
int m, count;


// SHA256 K constants
parameter int sha256_k[0:63] = '{
   32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5, 32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
   32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3, 32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
   32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc, 32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
   32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7, 32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
   32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13, 32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
   32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3, 32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
   32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5, 32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
   32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208, 32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2
};

// ___________________Main___________________

always_ff @(posedge clk, negedge reset_n)
begin
	if (!reset_n) begin
		done <= 0;
		state <= IDLE;
	end
	else begin
	
		case (state)
		IDLE: // Start
			if (start) begin
				pad_length = (padding(size));						
				state <= PREP;
			end
		
		PREP: // Preprocessing state
			begin
				mem_we <= 1;
				mem_addr <= message_addr + (size/4);
				case (size % 4) // pad bit 1
					0: mem_write_data <= 32'h80000000;
					1: mem_write_data <= (mem_write_data & 32'h FF000000) | 32'h 00800000;
					2: mem_write_data <= (mem_write_data & 32'h FFFF0000) | 32'h 00008000;
					3: mem_write_data <= (mem_write_data & 32'h FFFFFF00) | 32'h 00000080;
				endcase
				outloop = (pad_length+8)/64;
				m <= (size/4)+1;
				state <= PREP2;
			end
			
		PREP2: // 2nd Preprocessing state
		begin
			if (m < pad_length/4) begin
				mem_addr <= m;
				mem_write_data <= 32'h00000000;
				m <= m + 1;
				state <= PREP2;
			end
			else begin
				mem_we <= 1;
				mem_addr <= pad_length/4;
				mem_write_data <= size >> 29;
				state <= INITIAL;
			end
		end
	
			
		INITIAL: // Finishing Padding and Setting Hash Values
			begin
				mem_addr <= mem_addr + 1;
				mem_write_data <= (size*8);
				
				h0 <= 32'h6a09e667;
				h1 <= 32'hbb67ae85;
				h2 <= 32'h3c6ef372;
				h3 <= 32'ha54ff53a;
				h4 <= 32'h510e527f;
				h5 <= 32'h9b05688c;
				h6 <= 32'h1f83d9ab;
				h7 <= 32'h5be0cd19;
				m <= 0; // resets counter for next state
				state <= LOOP;
			end
			
		LOOP: // SHA256 Hash Loop
			if (m < outloop) begin
				a <= h0;
				b <= h1;
				c <= h2;
				d <= h3;
				e <= h4;
				f <= h5;
				g <= h6;
				h <= h7;
				mem_we <= 0;
				mem_addr <= message_addr + m*16;
				t <= 0;
				state <= DELAY;
			end
			else begin
				count <= 0;
				state <= WRITER;
			end
			
		DELAY:
			begin
				state <= INITW;
			end
		
		INITW: // Reads first w[t] and finds next mem_addr
			begin
				w[t] <= mem_read_data;
				mem_we <= 0;
				mem_addr <= message_addr + t + (m*16) + 1;
				state <= PRECOMP;
			end			
		
		
		PRECOMP: // Preloads mem_addr for 2nd READ cycle
			begin
				mem_addr <= message_addr + t + (m*16) + 2;
				state <= READ;
			end
			
		READ: // Reads in w[t] values from memory
			begin
				if(t < 16) begin
					{a, b, c, d, e, f, g, h} <= sha256_op(a, b, c, d, e, f, g, h, w[t], t);
					w[t+1] <= mem_read_data;
					mem_addr <= message_addr + t + (m*16) + 3;
					t <= t + 1;
					state <= READ;
				end
				else begin // Computes w[16] and optimizes area
					w[15] <= calc_w(w[t-2], w[t-7], w[t-15], w[t-16]);
					w[14] <= w[15];
					w[13] <= w[14];
					w[12] <= w[13];
					w[11] <= w[12];
					w[10] <= w[11];
					w[9] <= w[10];
					w[8] <= w[9];
					w[7] <= w[8];
					w[6] <= w[7];
					w[5] <= w[6];
					w[4] <= w[5];
					w[3] <= w[4];
					w[2] <= w[3];
					w[1] <= w[2];
					w[0] <= w[1];
					$display("w %x,%x,%x,%x\n", w[t-2], w[t-7], w[t-15], w[t-16]);
					state <= PUSH;
				end
			end
			
		PUSH: // Computes w[17] to w[63] and optimizes area
			begin
				if (t < 64) begin
					$display("w %x,%x,%x,%x\n", w[15], w[10], w[2], w[1]);
					{a, b, c, d, e, f, g, h} <= sha256_op(a, b, c, d, e, f, g, h, w[15], t);
					w[15] <= calc_w(w[14], w[9], w[1], w[0]);
					w[14] <= w[15];
					w[13] <= w[14];
					w[12] <= w[13];
					w[11] <= w[12];
					w[10] <= w[11];
					w[9] <= w[10];
					w[8] <= w[9];
					w[7] <= w[8];
					w[6] <= w[7];
					w[5] <= w[6];
					w[4] <= w[5];
					w[3] <= w[4];
					w[2] <= w[3];
					w[1] <= w[2];
					w[0] <= w[1];
					t <= t + 1;
					state <= PUSH;
				end
				else begin
					h0 <= h0 + a;
					h1 <= h1 + b;
					h2 <= h2 + c;
					h3 <= h3 + d;
					h4 <= h4 + e;
					h5 <= h5 + f;
					h6 <= h6 + g;
					h7 <= h7 + h;
					m <= m + 1;
					state <= LOOP;
				end
			end
				
		WRITER: // Writes values to output
			begin
				mem_we <= 1;
				mem_addr <= output_addr + count;
				count <= count + 1;
				case (count)
				0: 
					begin 
						mem_write_data <= h0;
					end	
				1: 
					begin 
						mem_write_data <= h1; 
					end
				2: 
					begin 
						mem_write_data <= h2; 
					end
				3: 
					begin 
						mem_write_data <= h3; 
					end
				4: 
					begin 
						mem_write_data <= h4; 
					end
				5: 
					begin 
						mem_write_data <= h5; 
					end
				6: 
					begin 
						mem_write_data <= h6; 
					end
				7: 
					begin 
						mem_write_data <= h7; 
					end
				default: 
					begin 
						state <= IDLE;
						done <= 1; 
					end
				endcase
			end
		endcase
	end
end

// ___________________Functions___________________
	
// SHA256 hash round
function logic [255:0] sha256_op(input logic [31:0] a, b, c, d, e, f, g, h, w,
                                 input logic [7:0] t);
    logic [31:0] S1, S0, ch, maj, t1, t2; // internal signals
begin
    S1 = rightrotate(e, 6) ^ rightrotate(e, 11) ^ rightrotate(e, 25);
    ch = (e & f) ^ ((~e) & g);
    t1 = h + S1 + ch + sha256_k[t] + w;
    S0 = rightrotate(a, 2) ^ rightrotate(a, 13) ^ rightrotate(a, 22);
    maj = (a & b) ^ (a & c) ^ (b & c);
    t2 = S0 + maj;

    sha256_op = {t1 + t2, a, b, c, d + t1, e, f, g};
end
endfunction


// right rotation
function logic [31:0] rightrotate(input logic [31:0] x,
                                  input logic [7:0] r);
begin
    rightrotate = (x >> r) | (x << (32-r));
end
endfunction

// padding bits
function int padding(input logic [31:0] size);
	// calculate total number of bytes after padding (before appending total length)
	if ((size + 1) % 64 <= 56 && (size + 1) % 64 > 0) begin
		padding = (size/64)*64 + 56;
	end
   else begin
		padding = (size/64+1)*64 + 56;
	end
endfunction

// calculate W[t]
function logic [31:0] calc_w(input logic [31:0] w2, w7, w15, w16);
	logic [31:0] s1, s0;
	begin
		s0 = rightrotate(w15, 7) ^ rightrotate(w15, 18) ^ (w15 >> 3);
		s1 = rightrotate(w2, 17) ^ rightrotate(w2, 19) ^ (w2 >> 10);
      calc_w = w16 + s0 + w7 + s1;
	end
endfunction
endmodule