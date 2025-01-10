LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
LIBRARY std;
USE std.textio.ALL;

LIBRARY vunit_lib;
CONTEXT vunit_lib.vunit_context;

LIBRARY crop_lib;

ENTITY crop_tb IS
  GENERIC (
    runner_cfg         : STRING  := runner_cfg_default;
    G_IMG_WIDTH        : INTEGER := 10;
    G_IMG_HEIGHT       : INTEGER := 10;
    G_CROP_COLS        : INTEGER := 5;
    G_CROP_ROWS        : INTEGER := 5;
    G_CROP_X_OFFSET    : INTEGER := 0;
    G_CROP_Y_OFFSET    : INTEGER := 0;
    G_IN_FILE_PATH     : STRING  := "./test_vector.hex";
    G_GOLDEN_FILE_PATH : STRING  := "./golden_vector.hex";
    G_MULTIPLE_FRAMES  : INTEGER := 1
  );
END;

ARCHITECTURE bench OF crop_tb IS
  -- Clock period
  CONSTANT clk_period : TIME := 5 ns;
  -- Constants
  CONSTANT CFG_WORDS_WDH : INTEGER                                     := 16;
  CONSTANT ENCODING_WDH  : INTEGER                                     := 24;
  CONSTANT EMPTY_DATA    : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  -- Ports
  SIGNAL clk          : STD_LOGIC                                    := '0';
  SIGNAL rst          : STD_LOGIC                                    := '0';
  SIGNAL cfg_x_offset : STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL cfg_y_offset : STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL cfg_cols     : STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL cfg_rows     : STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL snk_tvalid   : STD_LOGIC                                    := '0';
  SIGNAL snk_tready   : STD_LOGIC                                    := '0';
  SIGNAL snk_tdata    : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0)  := (OTHERS => '0');
  SIGNAL snk_tlast    : STD_LOGIC                                    := '0';
  SIGNAL snk_tuser    : STD_LOGIC                                    := '0';
  SIGNAL src_tvalid   : STD_LOGIC                                    := '0';
  SIGNAL src_tready   : STD_LOGIC                                    := '0';
  SIGNAL src_tdata    : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0)  := (OTHERS => '0');
  SIGNAL src_tlast    : STD_LOGIC                                    := '0';
  SIGNAL src_tuser    : STD_LOGIC                                    := '0';

  SIGNAL v_pixel_cnt_sig : unsigned(32 - 1 DOWNTO 0);

  FILE file_ptr        : text;
  FILE golden_file_ptr : text;
BEGIN

  clk <= NOT clk AFTER clk_period/2;

  crop_inst : ENTITY work.crop
    GENERIC MAP(
      CFG_WORDS_WDH => CFG_WORDS_WDH,
      ENCODING_WDH  => ENCODING_WDH
    )
    PORT MAP(
      clk          => clk,
      rst          => rst,
      cfg_x_offset => cfg_x_offset,
      cfg_y_offset => cfg_y_offset,
      cfg_cols     => cfg_cols,
      cfg_rows     => cfg_rows,
      snk_tvalid   => snk_tvalid,
      snk_tready   => snk_tready,
      snk_tdata    => snk_tdata,
      snk_tlast    => snk_tlast,
      snk_tuser    => snk_tuser,
      src_tvalid   => src_tvalid,
      src_tready   => src_tready,
      src_tdata    => src_tdata,
      src_tlast    => src_tlast,
      src_tuser    => src_tuser
    );

  main_test_runner : PROCESS
    VARIABLE v_iline     : Line;
    VARIABLE v_pixel     : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0) := (OTHERS => '0');
    VARIABLE v_pixel_cnt : unsigned(32 - 1 DOWNTO 0)                   := (OTHERS => '0');

    VARIABLE v_golden_line  : Line;
    VARIABLE v_golden_value : STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0) := (OTHERS => '0');
  BEGIN
    test_runner_setup(runner, runner_cfg);

    WHILE test_suite LOOP
      IF run("TEST::INIT_STATE") THEN
        WAIT UNTIL rising_edge(clk);
        rst <= '1';
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        check_equal(src_tdata, EMPTY_DATA);
        check_equal(src_tvalid, '0');
        check_equal(src_tuser, '0');
        check_equal(src_tlast, '0');
        check_equal(src_tready, '0');

      ELSIF run("TEST::PROPAGATE_TREADY") THEN
        WAIT UNTIL rising_edge(clk);
        src_tready <= '1';
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        check_equal(src_tready, snk_tready);
        src_tready <= '0';
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        check_equal(src_tready, snk_tready);

      ELSIF run("TEST::CROP_WITH_OFFSET") THEN
        WAIT UNTIL rising_edge(clk);
        rst <= '1';
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        rst          <= '0';
        src_tready   <= '1';
        cfg_x_offset <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_X_OFFSET, cfg_x_offset'length));
        cfg_y_offset <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_Y_OFFSET, cfg_y_offset'length));
        cfg_cols     <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_COLS, cfg_cols'length));
        cfg_rows     <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_ROWS, cfg_rows'length));
        file_open(file_ptr, G_IN_FILE_PATH, read_mode);
        file_open(golden_file_ptr, G_GOLDEN_FILE_PATH, read_mode);

        WHILE NOT endfile(file_ptr) LOOP
          IF (snk_tready = '1') THEN
            readline(file_ptr, v_iline);
            hread(v_iline, v_pixel);
            snk_tdata <= v_pixel;
            v_pixel_cnt := v_pixel_cnt + 1;
            IF (v_pixel_cnt = 1) THEN
              snk_tuser <= '1';
              snk_tvalid <= '1';
            ELSE
              snk_tuser <= '0';
            END IF;
            IF (v_pixel_cnt MOD G_IMG_WIDTH = 0 AND v_pixel_cnt /= 0) THEN
              snk_tlast <= '1';
            ELSE
              snk_tlast <= '0';
            END IF;
            WAIT UNTIL rising_edge(clk);
            IF (src_tvalid = '1' AND src_tready = '1') THEN
              readline(golden_file_ptr, v_golden_line);
              hread(v_golden_line, v_golden_value);
              check_equal(src_tdata, v_golden_value);
            END IF;
          ELSE
            WAIT UNTIL rising_edge(clk);
          END IF;
          v_pixel_cnt_sig <= v_pixel_cnt;
        END LOOP;

      ELSIF run("TEST::CROP_MULTIPLE_FRAMES") THEN
        WAIT UNTIL rising_edge(clk);
        rst <= '1';
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        rst          <= '0';
        src_tready   <= '1';
        cfg_x_offset <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_X_OFFSET, cfg_x_offset'length));
        cfg_y_offset <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_Y_OFFSET, cfg_y_offset'length));
        cfg_cols     <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_COLS, cfg_cols'length));
        cfg_rows     <= STD_LOGIC_VECTOR(TO_UNSIGNED(G_CROP_ROWS, cfg_rows'length));
        FOR i IN 0 TO G_MULTIPLE_FRAMES - 1 LOOP
          file_open(file_ptr, G_IN_FILE_PATH, read_mode);
          file_open(golden_file_ptr, G_GOLDEN_FILE_PATH, read_mode);
          v_pixel_cnt := (OTHERS => '0');
          WHILE NOT endfile(file_ptr) LOOP
            IF (snk_tready = '1') THEN
              readline(file_ptr, v_iline);
              hread(v_iline, v_pixel);
              snk_tdata <= v_pixel;
              v_pixel_cnt := v_pixel_cnt + 1;
              IF (v_pixel_cnt = 1) THEN
                snk_tuser <= '1';
                snk_tvalid   <= '1';
              ELSE
                snk_tuser <= '0';
              END IF;
              IF (v_pixel_cnt MOD G_IMG_WIDTH = 0 AND v_pixel_cnt /= 0) THEN
                snk_tlast <= '1';
              ELSE
                snk_tlast <= '0';
              END IF;
              WAIT UNTIL rising_edge(clk);
              IF (src_tvalid = '1' AND src_tready = '1') THEN
                readline(golden_file_ptr, v_golden_line);
                hread(v_golden_line, v_golden_value);
                check_equal(src_tdata, v_golden_value);
              END IF;
            ELSE
              WAIT UNTIL rising_edge(clk);
            END IF;
            v_pixel_cnt_sig <= v_pixel_cnt;
          END LOOP;
          file_close(file_ptr);
          file_close(golden_file_ptr);
        END LOOP;

        WAIT UNTIL rising_edge(clk);
      END IF;

    END LOOP;

    test_runner_cleanup(runner);
    WAIT;
  END PROCESS;

  test_runner_watchdog(runner, 2 ms);
END;