
# Entity: crop 
- **File**: crop.vhd

## Diagram
![Diagram](crop.svg "Diagram")
## Generics

| Generic name  | Type    | Value | Description                                                     |
| ------------- | ------- | ----- | --------------------------------------------------------------- |
| CFG_WORDS_WDH | INTEGER | 16    | bitwidth of config words (defines max value of offset/row/cols) |
| ENCODING_WDH  | INTEGER | 24    | bitwidth of colour encoding of captured pixels                  |

## Ports

| Port name    | Direction | Type                                         | Description                                                         |
| ------------ | --------- | -------------------------------------------- | ------------------------------------------------------------------- |
| clk          | in        | STD_LOGIC                                    | Clock input                                                         |
| rst          | in        | STD_LOGIC                                    | Active high synchronous reset                                       |
| cfg_x_offset | in        | STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) | Horizontal start position of subset region in pixel                 |
| cfg_y_offset | in        | STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) | Vertical start position of subset region in pixel                   |
| cfg_cols     | in        | STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) | Width of subset region in pixel                                     |
| cfg_rows     | in        | STD_LOGIC_VECTOR(CFG_WORDS_WDH - 1 DOWNTO 0) | Height of subset region in pixel                                    |
| snk_tvalid   | in        | STD_LOGIC                                    | Sink AXI Stream tvalid                                              |
| snk_tready   | out       | STD_LOGIC                                    | Sink AXI Stream tready                                              |
| snk_tdata    | in        | STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0)  | Sink AXI Stream data for 1 pixel 23:16 red, 15:8 blue, 7:0 green    |
| snk_tlast    | in        | STD_LOGIC                                    | Sink AXI Stream tlast - used as End of line marker                  |
| snk_tuser    | in        | STD_LOGIC                                    | Sink AXI Stream tuser - used as Start of frame marker               |
| src_tvalid   | out       | STD_LOGIC                                    | Source AXI Stream tvalid                                            |
| src_tready   | in        | STD_LOGIC                                    | Source AXI Stream tready                                            |
| src_tdata    | out       | STD_LOGIC_VECTOR(ENCODING_WDH - 1 DOWNTO 0)  | Source AXI Stream data for 1 pixel: 23:16 red, 15:8 blue, 7:0 green |
| src_tlast    | out       | STD_LOGIC                                    | Source AXI Stream tlast - used as End of line marker                |
| src_tuser    | out       | STD_LOGIC                                    | Source AXI Stream tuser - used as Start of frame marker             |

## Signals

| Name                 | Type                                 | Description                                                                                       |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| captured_columns_cnt | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | counter used for keeping an eye of captured columns in definied row                               |
| captured_rows_cnt    | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | counter used for keeping an eye of captured rows of video stream                                  |
| cfg_x_offset_reg     | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | cropped stream x_offset (registered)                                                              |
| cfg_y_offset_reg     | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | cropped stream y_offset (registered)                                                              |
| cfg_cols_reg         | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | number of columns to crop (registered): x_offset + cfg_cols will define width of the video stream |
| cfg_rows_reg         | UNSIGNED(CFG_WORDS_WDH - 1 DOWNTO 0) | number of rows to crop (registered): y_offset + cfg_rows will define height of the video stream   |

## Processes
- drive_tready_signals: ( clk )
  - **Description**
  Process used for driving Tready Signals. Whenever rst signal is asserted module is not ready for recieving the data. During normal operation module will be ready whenever the source will be ready for recieving the data.
- capture_pixel_from_sink_proc: ( clk )
  - **Description**
  Process used for driving data output. Whenever rst signal is asserted src_tdata will stay at "0", During normal operation incoming value could be passed to output stream when snk_tvalid and snk_tready are high. Source will wait for Tvalid signal to be asserted to capture the data.
- count_capured_columns_from_sink_proc: ( clk )
  - **Description**
  Process used for counting up incoming columns from video stream. Whenever rst signal is asserted, it will clear the counter at first upcoming rising edge. In normal operation cnt will be set to 0 only when snk_tvalid, snk_tready and snk_tuser will be High (indicating start of the frame) or snk_tvalid, snk_tready and snk_tlast will be High (indicating end of the line). Every clock cycle it will then check if the master module is transmitting the data by checking snk_tvalid = '1' and snk_tready '1' and will increment by 1. In any other case it will hold its previous value.
- count_completed_rows_from_sink_proc: ( clk )
  - **Description**
  Process used for counting up number of rows coming from transmitting device. Whenever rst signal is asserted, it will clear the counter at first upcoming rising edge. In normal operation cnt will be set to 0 only when snk_tvalid, snk_tready and snk_tuser will be High (indicating start of the frame). Every clock cycle it will then check if snk_tvalid, snk_tready and snk_tlast is High (indication from Master that currently transferred pixel is the last one from the line) and increment if so. In any other case it will hold its previous value.
- capture_configuration_at_start_of_frame: ( clk )
  - **Description**
  Configuration should be changable during runtime. This process allows to overwrite configuration only when there is start of new frame detected. In any other case the configuration will be locked untill new frame.
- drive_data_tlast_tuser_signal_for_source: ( clk )
  - **Description**
  Process used for driving source side signals. Whenever rst is asserted src_tvalid, src_tuser and src_tlast will be set to '0'. During normal operation src_tvalid will be high when captured columns will be inside range defined as: (cfg_x_offset, cfg_x_offset + cfg_columns) and captured rows will be inside range: (cfg_y_offset, cfg_y_offset + cfg_rows). If the value is outside these ranges src_tvalid will be kept low (as well as src_tuser and src_tlast). src_tuser (start of the frame) signal will be high whenever captured_columns = cfg_x_offset and captured_rows = cfg_y_offset in any other case will be set to '0'. src_tlast (end of the line) signal will be high when captured_columns - 1 = cfg_x_offset + cfg_columns. in any other case will be set to '0'
