localparam string FA_TB_VERSION = "FA_UVM_R15";	//verzija okruzenja

//default vrednosti, u slucaju da nisu definisane 
`ifndef FA_ROWS
  `define FA_ROWS 8
`endif
`ifndef FA_HEADS
  `define FA_HEADS 2
`endif
`ifndef FA_B
  `define FA_B 4
`endif
`ifndef FA_BC
  `define FA_BC 4
`endif
//parametri koje koristimo u testiranju
localparam int HEADS_TB = `FA_HEADS;
localparam int ROWS_TB = `FA_ROWS;
localparam int B_TB = `FA_B;
localparam int BC_TB = `FA_BC;
localparam int DIM_TB = 64;
//brojanje rezultata
localparam int COLS_TB = HEADS_TB * DIM_TB;
localparam int OUTPUT_WORDS = ROWS_TB * COLS_TB;
localparam int Q_BLOCKS = (ROWS_TB+B_TB-1)/B_TB;
localparam int INPUT_WORDS = HEADS_TB*(ROWS_TB*DIM_TB + Q_BLOCKS*2*ROWS_TB*DIM_TB);	//prati nas redosled slanja podataka
function automatic int minimum(int a, int b); 	//za blok manje velicine
	return a < b ? a : b; 
endfunction
function automatic void output_position(int index, output int h, r, d);	//pretvara niz izlaznih reci u koordinate zato sto RTL salje niz reci, ali scoreboard mora znati koja rec gde pripada
  int qb, offset, nr;
  qb = index/(HEADS_TB*B_TB*DIM_TB);
  offset = index%(HEADS_TB*B_TB*DIM_TB);	//kojem q bloku izlaz pripada
  nr = minimum(B_TB, ROWS_TB-qb*B_TB);	//racuna redove tog bloka, ukljucujuci i nepotpun blok
  h = offset/(nr*DIM_TB);						//odredjujemo stavaran broj
  r = qb*B_TB + (offset%(nr*DIM_TB))/DIM_TB;	//blokova, ukljucujuci i nepotpune
  d = index%DIM_TB;								
endfunction

localparam int signed INPUT_MIN = 24'sh800000;
localparam int signed INPUT_MAX = 24'sh7FFFFF;
localparam int signed INPUT_LSB = 1;
localparam int signed FIXED_ONE = 1 << 18;
localparam int signed FIXED_QUARTER = 1 << 16;
localparam real INPUT_SCALE = 262144.0;
localparam real OUTPUT_SCALE = 17179869184.0;
typedef enum {MATRIX_Q, MATRIX_K, MATRIX_V} fa_matrix_kind;
