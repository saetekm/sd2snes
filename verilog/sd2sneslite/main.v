`timescale 1 ns / 1 ns
//////////////////////////////////////////////////////////////////////////////////
// Company: Rehkopf
// Engineer: Rehkopf
// 
// Create Date:    01:13:46 05/09/2009 
// Design Name: 
// Module Name:    main 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: Master Control FSM
//
// Dependencies: address
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module main(
  /* input clock */
  input CLKIN,

  /* SNES signals */
  input [23:0] SNES_ADDR,
  input SNES_READ,
  input SNES_WRITE,
  input SNES_CS,
  inout [7:0] SNES_DATA,
  input SNES_CPU_CLK,
  input SNES_REFRESH,
  output SNES_IRQ,
  output SNES_DATABUS_OE,
  output SNES_DATABUS_DIR,
  input SNES_SYSCLK,

  /* SRAM signals */
  /* Bus 1: PSRAM, 128Mbit, 16bit, 70ns */
  inout [15:0] ROM_DATA,
  output [22:0] ROM_ADDR,
  output ROM_CE,
  output ROM_OE,
  output ROM_WE,
  output ROM_BHE,
  output ROM_BLE,

  /* Bus 2: SRAM, 4Mbit, 8bit, 45ns */
  inout [7:0] RAM_DATA,
  output [18:0] RAM_ADDR,
  output RAM_CE,
  output RAM_OE,
  output RAM_WE,

  /* MCU signals */
  input SPI_MOSI,
  inout SPI_MISO,
  input SPI_SS,
  inout SPI_SCK,
  input MCU_OVR,
  output MCU_RDY,
  
  output DAC_MCLK,
  output DAC_LRCK,
  output DAC_SDOUT,

  /* SD signals */
  input [3:0] SD_DAT,
  inout SD_CMD,
  inout SD_CLK,

  /* debug */
  output p113_out
);

assign DAC_MCLK = 1'b0;
assign DAC_LRCK = 1'b0;
assign DAC_SDOUT = 1'b0;

assign SD_CMD = 1'bZ;
assign SD_CLK = 1'bZ;

wire [7:0] spi_cmd_data;
wire [7:0] spi_param_data;
wire [7:0] spi_input_data;
wire [31:0] spi_byte_cnt;
wire [2:0] spi_bit_cnt;
wire [23:0] MCU_ADDR;
wire [7:0] mcu_data_in;
wire [7:0] mcu_data_out;
wire [3:0] MAPPER;
wire [23:0] SAVERAM_MASK;
wire [23:0] ROM_MASK;

wire [23:0] MAPPED_SNES_ADDR;
wire ROM_ADDR0;

spi snes_spi(
  .clk(CLK2),
  .MOSI(SPI_MOSI),
  .MISO(SPI_MISO),
  .SSEL(SPI_SS),
  .SCK(SPI_SCK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .endmessage(spi_endmessage),
  .startmessage(spi_startmessage),
  .input_data(spi_input_data),
  .byte_cnt(spi_byte_cnt),
  .bit_cnt(spi_bit_cnt)
);

reg [7:0] MCU_DINr;
wire [7:0] MCU_DOUT;

mcu_cmd snes_mcu_cmd(
  .clk(CLK2),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .mcu_sram_size(SRAM_SIZE),
  .mcu_write(MCU_WRITE),
  .mcu_data_in(MCU_DINr),
  .mcu_data_out(MCU_DOUT),
  .spi_byte_cnt(spi_byte_cnt),
  .spi_bit_cnt(spi_bit_cnt),
  .spi_data_out(spi_input_data),
  .addr_out(MCU_ADDR),
  .endmessage(spi_endmessage),
  .startmessage(spi_startmessage),
  .saveram_mask_out(SAVERAM_MASK),
  .rom_mask_out(ROM_MASK),
  .mcu_rrq(MCU_RRQ),
  .mcu_wrq(MCU_WRQ),
  .mcu_rq_rdy(MCU_RDY)
);

// dcm1: dfs 4x
my_dcm snes_dcm(
  .CLKIN(CLKIN),
  .CLKFX(CLK2),
  .LOCKED(DCM_LOCKED),
  .RST(DCM_RST),
  .STATUS(DCM_STATUS)
);

assign DCM_RST=0;

reg [5:0] SNES_READr;
reg [5:0] SNES_WRITEr;
reg [12:0] SNES_CPU_CLKr;
reg [5:0] SNES_RWr;
reg [23:0] SNES_ADDRr;

wire SNES_RW = (SNES_READ & SNES_WRITE);

wire SNES_RW_start = (SNES_RWr == 6'b111110); // falling edge marks beginning of cycle
wire SNES_RD_start = (SNES_READr == 6'b111110);
wire SNES_WR_start = (SNES_WRITEr == 6'b111110);
wire SNES_cycle_start = (SNES_CPU_CLKr[5:0] == 6'b000001);
wire SNES_cycle_end = (SNES_CPU_CLKr[5:0] == 6'b111110);

always @(posedge CLK2) begin
  SNES_READr <= {SNES_READr[4:0], SNES_READ};
  SNES_WRITEr <= {SNES_WRITEr[4:0], SNES_WRITE};
  SNES_CPU_CLKr <= {SNES_CPU_CLKr[11:0], SNES_CPU_CLK};
  SNES_RWr <= {SNES_RWr[4:0], SNES_RW};
end

wire ROM_SEL;

address snes_addr(
  .CLK(CLK2),
  .SNES_ADDR(SNES_ADDR), // requested address from SNES
  .SNES_CS(SNES_CS),     // "CART" pin from SNES (active low)
  .ROM_ADDR(MAPPED_SNES_ADDR),   // Address to request from SRAM (active low)
  .ROM_SEL(ROM_SEL),     // which SRAM unit to access
  .IS_SAVERAM(IS_SAVERAM),
  .IS_ROM(IS_ROM),
  .MCU_ADDR(MCU_ADDR),
  .SAVERAM_MASK(SAVERAM_MASK),
  .ROM_MASK(ROM_MASK)
);

wire SNES_READ_CYCLEw;
wire SNES_WRITE_CYCLEw;
wire MCU_READ_CYCLEw;
wire MCU_WRITE_CYCLEw;

parameter MODE_SNES = 1'b0;
parameter MODE_MCU = 1'b1;

parameter ST_IDLE         = 18'b000000000000000001;
parameter ST_SNES_RD_ADDR = 18'b000000000000000010;
parameter ST_SNES_RD_WAIT = 18'b000000000000000100;
parameter ST_SNES_RD_END  = 18'b000000000000001000;
parameter ST_SNES_WR_ADDR = 18'b000000000000010000;
parameter ST_SNES_WR_WAIT1= 18'b000000000000100000;
parameter ST_SNES_WR_DATA = 18'b000000000001000000;
parameter ST_SNES_WR_WAIT2= 18'b000000000010000000;
parameter ST_SNES_WR_END  = 18'b000000000100000000;
parameter ST_MCU_RD_ADDR  = 18'b000000001000000000;
parameter ST_MCU_RD_WAIT  = 18'b000000010000000000;
parameter ST_MCU_RD_WAIT2 = 18'b000000100000000000;
parameter ST_MCU_RD_END   = 18'b000001000000000000;
parameter ST_MCU_WR_ADDR  = 18'b000010000000000000;
parameter ST_MCU_WR_WAIT  = 18'b000100000000000000;
parameter ST_MCU_WR_WAIT2 = 18'b001000000000000000;
parameter ST_MCU_WR_END   = 18'b010000000000000000;

parameter ROM_RD_WAIT = 4'h4;
parameter ROM_RD_WAIT_MCU = 4'h5;
parameter ROM_WR_WAIT1 = 4'h2;
parameter ROM_WR_WAIT2 = 4'h3;
parameter ROM_WR_WAIT_MCU = 4'h6;

reg [17:0] STATE;
initial STATE = ST_IDLE;

reg [1:0] CYCLE_RESET;
reg ROM_WE_MASK;
reg ROM_OE_MASK;

reg [7:0] SNES_DINr;
reg [7:0] ROM_DOUTr;

assign SNES_DATA = (!SNES_READ) ? SNES_DINr : 8'bZ;

reg [3:0] ST_MEM_DELAYr;
reg MCU_RD_PENDr;
reg MCU_WR_PENDr;
reg [23:0] ROM_ADDRr;
reg NEED_SNES_ADDRr;
always @(posedge CLK2) begin
  if(SNES_cycle_end) NEED_SNES_ADDRr <= 1'b1;
  else if(STATE & (ST_SNES_RD_END | ST_SNES_WR_END)) NEED_SNES_ADDRr <= 1'b0;
end

wire ASSERT_SNES_ADDR = SNES_CPU_CLK & NEED_SNES_ADDRr;

assign ROM_ADDR  = (ASSERT_SNES_ADDR) ? MAPPED_SNES_ADDR[23:1] : ROM_ADDRr[23:1];
assign ROM_ADDR0 = (ASSERT_SNES_ADDR) ? MAPPED_SNES_ADDR[0] : ROM_ADDRr[0];

reg ROM_WEr;
initial ROM_WEr = 1'b1;

reg RQ_MCU_RDYr;
initial RQ_MCU_RDYr = 1'b1;
assign MCU_RDY = RQ_MCU_RDYr;

always @(posedge CLK2) begin
  if(MCU_RRQ) begin
    MCU_RD_PENDr <= 1'b1;
	 RQ_MCU_RDYr <= 1'b0;
  end else if(MCU_WRQ) begin
    MCU_WR_PENDr <= 1'b1;
	 RQ_MCU_RDYr <= 1'b0;
  end else if(STATE & (ST_MCU_RD_END | ST_MCU_WR_END)) begin
    MCU_RD_PENDr <= 1'b0;
	 MCU_WR_PENDr <= 1'b0;
	 RQ_MCU_RDYr <= 1'b1;
  end
end

reg snes_wr_cycle;

always @(posedge CLK2) begin
  if(SNES_cycle_start) begin
    STATE <= ST_SNES_RD_ADDR;
  end else if(SNES_WR_start) begin
    STATE <= ST_SNES_WR_ADDR;
  end else begin
    case(STATE)
	   ST_IDLE: begin
		  ROM_ADDRr <= MAPPED_SNES_ADDR;
		  if(MCU_RD_PENDr) STATE <= ST_MCU_RD_ADDR;
		  else if(MCU_WR_PENDr) STATE <= ST_MCU_WR_ADDR;
        else STATE <= ST_IDLE;
		end
		ST_SNES_RD_ADDR: begin
		  STATE <= ST_SNES_RD_WAIT;
		  ST_MEM_DELAYr <= ROM_RD_WAIT;
		end
		ST_SNES_RD_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_RD_END;
		  else STATE <= ST_SNES_RD_WAIT;
		  if(ROM_ADDR0) SNES_DINr <= ROM_DATA[7:0];
		  else SNES_DINr <= ROM_DATA[15:8];
		end
		ST_SNES_RD_END: begin
		  STATE <= ST_IDLE;
		  if(ROM_ADDR0) SNES_DINr <= ROM_DATA[7:0];
		  else SNES_DINr <= ROM_DATA[15:8];
		end
      ST_SNES_WR_ADDR: begin
        ROM_WEr <= (!IS_SAVERAM);
        snes_wr_cycle <= 1'b1;
		  STATE <= ST_SNES_WR_WAIT1;
		  ST_MEM_DELAYr <= ROM_WR_WAIT1;
		end
		ST_SNES_WR_WAIT1: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_WR_DATA;
		  else STATE <= ST_SNES_WR_WAIT1;
		end
		ST_SNES_WR_DATA: begin
        ROM_DOUTr <= SNES_DATA;
		  ST_MEM_DELAYr <= ROM_WR_WAIT2;
		  STATE <= ST_SNES_WR_WAIT2;
		end
      ST_SNES_WR_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_WR_END;
		  else STATE <= ST_SNES_WR_WAIT2;
		end
		ST_SNES_WR_END: begin
		  STATE <= ST_IDLE;
		  ROM_WEr <= 1'b1;
		  snes_wr_cycle <= 1'b0;
		end
		ST_MCU_RD_ADDR: begin
		  ROM_ADDRr <= MCU_ADDR;
		  STATE <= ST_MCU_RD_WAIT;
		  ST_MEM_DELAYr <= ROM_RD_WAIT_MCU;
		end
		ST_MCU_RD_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_RD_WAIT2;
			 ST_MEM_DELAYr <= 4'h2;
		  end
		  else STATE <= ST_MCU_RD_WAIT;
		  if(ROM_ADDR0) MCU_DINr <= ROM_DATA[7:0];
		  else MCU_DINr <= ROM_DATA[15:8];
      end
		ST_MCU_RD_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_RD_END;
		  end else STATE <= ST_MCU_RD_WAIT2;
		end
		ST_MCU_RD_END: begin
		  STATE <= ST_IDLE;
		end
		ST_MCU_WR_ADDR: begin
		  ROM_ADDRr <= MCU_ADDR;
		  STATE <= ST_MCU_WR_WAIT;
		  ST_MEM_DELAYr <= ROM_WR_WAIT_MCU;
		  ROM_DOUTr <= MCU_DOUT;
		  ROM_WEr <= 1'b0;
		end
		ST_MCU_WR_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
          ROM_WEr <= 1'b1;
		    STATE <= ST_MCU_WR_WAIT2;
			 ST_MEM_DELAYr <= 4'h2;
		  end
		  else STATE <= ST_MCU_WR_WAIT;
      end
		ST_MCU_WR_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_WR_END;
        end else STATE <= ST_MCU_WR_WAIT2;
		end
		ST_MCU_WR_END: begin
		  STATE <= ST_IDLE;
		end

	 endcase
  end
end

assign ROM_DATA[7:0] = ROM_ADDR0
                       ?(!ROM_WE ? ROM_DOUTr : 8'bZ)
                       :8'bZ;

assign ROM_DATA[15:8] = ROM_ADDR0 ? 8'bZ
                        :(!ROM_WE ? ROM_DOUTr : 8'bZ);
                         
assign ROM_WE = ROM_WEr | (ASSERT_SNES_ADDR & ~snes_wr_cycle);
assign ROM_OE = 1'b0;

assign ROM_CE = 1'b0;

assign ROM_BHE = !ROM_WE ? ROM_ADDR0 : 1'b0;
assign ROM_BLE = !ROM_WE ? !ROM_ADDR0 : 1'b0;

assign SNES_DATABUS_OE = ((IS_ROM & SNES_CS)
                          |(!IS_ROM & !IS_SAVERAM)
                          |(SNES_READ & SNES_WRITE)
                         );

assign SNES_DATABUS_DIR = !SNES_READ ? 1'b1 : 1'b0;

assign SNES_IRQ = 1'b0;

assign p113_out = 1'b0;

endmodule
