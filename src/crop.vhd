LIBRARY ieee;
CONTEXT ieee.ieee_std_context;

LIBRARY crop_lib;

ENTITY crop IS
  GENERIC (
    CFG_WORDS_WDH : INTEGER := 16; --! bitwidth of config words (defines max value of offset/row/cols)
    ENCODING_WDH  : INTEGER := 24  --! bitwidth of colour encoding of captured pixels
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
    src_tuser  : OUT STD_LOGIC                                    --! Source AXI Stream tuser - used as Start of frame marker
  );
END ENTITY;

ARCHITECTURE rtl OF crop IS
  --! counter used for keeping an eye of captured columns in definied row
  SIGNAL captured_columns_cnt : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');

  --! counter used for keeping an eye of captured rows of video stream
  SIGNAL captured_rows_cnt : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');

  --! cropped stream x_offset (registered)
  SIGNAL cfg_x_offset_reg : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  --! cropped stream y_offset (registered)
  SIGNAL cfg_y_offset_reg : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  --! number of columns to crop (registered): x_offset + cfg_cols will define width of the video stream
  SIGNAL cfg_cols_reg : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  --! number of rows to crop (registered): y_offset + cfg_rows will define height of the video stream
  SIGNAL cfg_rows_reg : UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');

  --! used to align data with counter
  SIGNAL snk_tlast_reg : STD_LOGIC := '0';

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

  --! Process used for driving data output. Whenever rst signal is asserted src_tdata will stay at "0",
  --! During normal operation incoming value could be passed to output stream when snk_tvalid and snk_tready are high.
  --! Source will wait for Tvalid signal to be asserted to capture the data.
  capture_pixel_from_sink_proc : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        src_tdata     <= (OTHERS => '0');
        snk_tlast_reg <= '0';
      ELSE
        IF (snk_tvalid = '1' AND snk_tready = '1') THEN
          src_tdata     <= snk_tdata;
          snk_tlast_reg <= snk_tlast;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --! Process used for counting up incoming columns from video stream. Whenever rst signal is asserted,
  --! it will clear the counter at first upcoming rising edge. In normal operation cnt will be modify only when
  --! snk_tvalid, snk_tready will be High (indicating ongoin transaction).
  --! counter will be cleared whenever new frame or end of the line arrives, in other cases it will be incremented by 1.
  count_capured_columns_from_sink_proc : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        captured_columns_cnt <= (OTHERS => '0');
      ELSE
        IF (snk_tvalid = '1' AND snk_tready = '1') THEN
          IF ((snk_tuser = '1' OR snk_tlast_reg = '1')) THEN
            captured_columns_cnt <= (OTHERS => '0');
          ELSE
            captured_columns_cnt <= captured_columns_cnt + 1;
          END IF;
        ELSE
          captured_columns_cnt <= (OTHERS => '0');
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
        ELSIF (snk_tvalid = '1' AND snk_tready = '1' AND snk_tlast_reg = '1') THEN
          captured_rows_cnt <= captured_rows_cnt + 1;
        ELSE
          captured_rows_cnt <= captured_rows_cnt;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --! Configuration should be changable during runtime. This process allows to overwrite configuration only
  --! when there is start of new frame detected. In any other case the configuration will be locked untill new frame.
  capture_configuration_at_start_of_frame : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        cfg_x_offset_reg <= (OTHERS => '0');
        cfg_y_offset_reg <= (OTHERS => '0');
        cfg_cols_reg     <= (OTHERS => '0');
        cfg_rows_reg     <= (OTHERS => '0');
      ELSE
        IF (snk_tvalid = '1' AND snk_tuser = '1') THEN
          cfg_x_offset_reg <= unsigned(cfg_x_offset);
          cfg_y_offset_reg <= unsigned(cfg_y_offset);
          cfg_cols_reg     <= unsigned(cfg_cols) - 1;
          cfg_rows_reg     <= unsigned(cfg_rows);
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --! Process used for driving source side signals. Whenever rst is asserted src_tvalid, src_tuser and src_tlast will be set to '0'.
  --! During normal operation src_tvalid will be high when captured columns will be inside range defined as:
  --! (cfg_x_offset, cfg_x_offset + cfg_columns) and captured rows will be inside range: (cfg_y_offset, cfg_y_offset + cfg_rows).
  --! If the value is outside these ranges src_tvalid will be kept low (as well as src_tuser and src_tlast).
  --! src_tuser (start of the frame) signal will be high whenever captured_columns = cfg_x_offset and captured_rows = cfg_y_offset
  --! in any other case will be set to '0'.
  --! src_tlast (end of the line) signal will be high when captured_columns + 1 = cfg_x_offset + cfg_columns.
  --! in any other case will be set to '0'
  drive_data_tlast_tuser_signal_for_source : PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF (rst = '1') THEN
        src_tvalid <= '0';
        src_tuser  <= '0';
        src_tlast  <= '0';
      ELSE
        IF (snk_tvalid = '1') THEN
          IF ((captured_columns_cnt >= cfg_x_offset_reg - 1 AND captured_columns_cnt < cfg_x_offset_reg + cfg_cols_reg)
            AND (captured_rows_cnt >= cfg_y_offset_reg AND captured_rows_cnt < cfg_y_offset_reg + cfg_rows_reg)) THEN

            src_tvalid <= '1';

            IF (captured_columns_cnt = cfg_x_offset_reg - 1) AND (captured_rows_cnt = cfg_y_offset_reg) THEN
              src_tuser <= '1';
            ELSE
              src_tuser <= '0';
            END IF;

            IF (captured_columns_cnt + 1 = cfg_x_offset_reg + cfg_cols_reg) THEN
              src_tlast <= '1';
            ELSE
              src_tlast <= '0';
            END IF;
          ELSE
            src_tvalid <= '0';
            src_tuser  <= '0';
            src_tlast  <= '0';
          END IF;
        ELSE
          src_tvalid <= '0';
          src_tuser  <= '0';
          src_tlast  <= '0';
        END IF;
      END IF;
    END IF;
  END PROCESS;
END ARCHITECTURE;