LIBRARY ieee;
CONTEXT ieee.ieee_std_context;

ENTITY crop IS
  GENERIC (
    CFG_WORDS_WDH : INTEGER := 16;
    ENCODING_WDH  : INTEGER := 24
  );
  PORT (
    clk : IN STD_LOGIC; --! Clock input
    rst : IN STD_LOGIC; --! Active high synchronous reset

    -- Config
    cfg_x_offset : IN STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0); --! Horizontal start position of subset region in pixel
    cfg_y_offset : IN STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0); --! Vertical start position of subset region in pixel
    cfg_cols     : IN STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0); --! Width of subset region in pixel
    cfg_rows     : IN STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0); --! Height of subset region in pixel

    -- Sink
    snk_tvalid : IN STD_LOGIC;                                   --! Sink AXI Stream tvalid
    snk_tready : OUT STD_LOGIC;                                  --! Sink AXI Stream tready
    snk_tdata  : IN STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0); --! Sink AXI Stream data for 1 pixel 23:16 red, 15:8 blue, 7:0 green
    snk_tlast  : IN STD_LOGIC;                                   --! Sink AXI Stream tlast - used as End of line marker
    snk_tuser  : IN STD_LOGIC;                                   --! Sink AXI Stream tuser - used as Start of frame marker

    -- Source
    src_tvalid : OUT STD_LOGIC;                                   --! Source AXI Stream tvalid
    src_tready : IN STD_LOGIC;                                    --! Source AXI Stream tready
    src_tdata  : OUT STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0); --! Source AXI Stream data for 1 pixel: 23:16 red, 15:8 blue, 7:0 green
    src_tlast  : OUT STD_LOGIC;                                   --! Source AXI Stream tlast - used as End of line marker
    src_tuser  : OUT STD_LOGIC);                                  --! Source AXI Stream tuser - used as Start of frame marker
END ENTITY;

ARCHITECTURE rtl OF crop IS
  SIGNAL captured_pixel_reg   : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL captured_columns_cnt : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0)        := (OTHERS => '0');
  SIGNAL captured_rows_cnt    : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0)        := (OTHERS => '0');
BEGIN

  --! Process used for driving Tready Signals. Whenever rst signal is asserted module is not ready for recieving the data.
  --! During normal operation module will be ready whenever the source will be ready for recieving the data.
  drive_tready_signals : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        snk_tready <= '0';
      ELSE
        snk_tready <= src_tready;
      END IF;
    END IF;
  END PROCESS;

  --! Process used for registering incoming pixel value. Whenever rst signal is asserted it will stay at "0",
  --! During normal operation it register snk_tdata value into captured_pixel_reg every rising edge but only when
  --! snk_tvalid and snk_tready is high.
  capture_pixel_from_sink_proc : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        captured_pixel_reg <= (OTHERS => '0');
      ELSE
        IF (snk_tvalid = '1' AND snk_tready = '1') THEN
          captured_pixel_reg <= snk_tdata;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --! Process used for counting up incoming columns from video stream. Whenever rst signal is asserted,
  --! it will clear the counter at first upcoming rising edge. In normal operation cnt will be set to 0 only when
  --! snk_tvalid, snk_tready and snk_tuser will be High (indicating start of the frame) or snk_tvalid, snk_tready and
  --! snk_tlast will be High (indicating end of the line). Every clock cycle it will then check if the master
  --! module is transmitting the data by checking snk_tvalid = '1' and snk_tready '1' and will increment by 1.
  --! In any other case it will hold its previous value.
  count_capured_columns_from_sink_proc : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        captured_columns_cnt <= (OTHERS => '0');
      ELSE
        IF (snk_tvalid = '1' AND snk_tready = '1' AND (snk_tuser = '1' OR snk_tlast = '1')) THEN
          captured_columns_cnt <= (OTHERS => '0');
        ELSIF (snk_tvalid = '1' AND snk_tready = '1') THEN
          captured_columns_cnt <= captured_columns_cnt + 1;
        ELSE
          captured_columns_cnt <= captured_columns_cnt;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --! Process used for counting up number of rows coming from transmitting device. Whenever rst signal is asserted,
  --! it will clear the counter at first upcoming rising edge. In normal operation cnt will be set to 0 only when
  --! snk_tvalid, snk_tready and snk_tuser will be High (indicating start of the frame). Every clock cycle it will
  --! then check if snk_tvalid, snk_tready and snk_tlast is High (indication from Master that currently transferred pixel
  --! is the last one from the line) and increment if so. In any other case it will hold its previous value.
  count_completed_rows_from_sink_proc : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        captured_rows_cnt <= (OTHERS => '0');
      ELSE
        IF (snk_tvalid = '1' AND snk_tready = '1' AND snk_tuser = '1') THEN
          captured_rows_cnt <= (OTHERS => '0');
        ELSIF (snk_tvalid = '1' AND snk_tready = '1' AND snk_tlast = '1') THEN
          captured_rows_cnt <= captured_rows_cnt + 1;
        ELSE
          captured_rows_cnt <= captured_rows_cnt;
        END IF;
      END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE;