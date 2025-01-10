from pathlib import Path
from os.path import abspath, join, dirname
from vunit import VUnit
import random

generics = {
    'G_IMG_WIDTH'          : 10,
    'G_IMG_HEIGHT'         : 10,
    'G_CROP_COLS'          : 5,
    'G_CROP_ROWS'          : 5,
    'G_CROP_X_OFFSET'      : 2,
    'G_CROP_Y_OFFSET'      : 2,
    'G_MULTIPLE_FRAMES'    : 30
}

# ROOT
ROOT = Path(__file__).resolve().parent
# Sources path for DUT
DUT_PATH = ROOT / "../src"
# Sources path for TB
TEST_PATH = ROOT

# create VUnit instance
VU = VUnit.from_argv(compile_builtins=False)
VU.add_vhdl_builtins()

# create common library
lib = VU.add_library("crop_lib")
# add design source files to lib
lib.add_source_files([DUT_PATH / "*.vhd"])
# add testbench source files to crop
lib.add_source_files([TEST_PATH / "*.vhd"])
testbench = lib.test_bench("crop_tb")

for key, value in generics.items():
    testbench.set_generic(key,value)


def generate_test_vectors(file_path, width=generics['G_IMG_WIDTH'], height=generics['G_IMG_HEIGHT']):
    """
    Generates test vectors in the form of a HEX file, representing an image with random RGB colors.

    :param file_path: Path to the file where the test vectors will be saved.
    :param width: Width of the image in pixels.
    :param height: Height of the image in pixels.
    :return: None
    """

    # Generate image with predefinied width and height
    image_data = bytearray()
    for _ in range(width * height):
        color = (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255))
        image_data.extend(color)

    with open(file_path, "w") as file:
        for _ in range(width * height):
            r = random.randint(0, 255)
            g = random.randint(0, 255)
            b = random.randint(0, 255)
            hex_color = f"{r:02X}{g:02X}{b:02X}"
            file.write(f"{hex_color}\n")

def generate_golden_image_vectors(file_path, output_file, test_nr, width=generics['G_IMG_WIDTH'], height=generics['G_IMG_HEIGHT'],
                                  x_offset=generics['G_CROP_X_OFFSET'], y_offset=generics['G_CROP_Y_OFFSET'],
                                  cols=generics['G_CROP_COLS'], rows=generics['G_CROP_ROWS']):
    """
    Loads a HEX file with colors, crops it according to the specified parameters, and saves the result to a file.

    :param file_path: Path to the file containing colors in HEX format.
    :param width: Width of the original image in pixels.
    :param height: Height of the original image in pixels.
    :param x_offset: Starting pixel in the X-axis.
    :param y_offset: Starting pixel in the Y-axis.
    :param cols: Number of columns to crop.
    :param rows: Number of rows to crop.
    :param output_file: Path to the output file where the cropped image will be saved.
    :return: None
    """
    # Load the file into memory as a list of colors
    with open(file_path, "r") as file:
        colors = [line.strip() for line in file]

    # Validate parameters
    if x_offset < 0 or y_offset < 0 or x_offset + cols > width or y_offset + rows > height:
        raise ValueError("Invalid cropping parameters")

    # Cropped image
    cropped_image = []

    for row in range(y_offset, y_offset + rows):
        start_index = row * width + x_offset
        end_index = start_index + cols
        cropped_image.append(colors[start_index:end_index])

    # Save the cropped image to a file
    with open(output_file, "w") as output:
        for row in cropped_image:
            for value in row:
                output.write(value + "\n")

def set_generics(obj, suffix=0):
    """
    generates test vectors and sets generic for a given object.
    :param obj: testcase in main testbench unit.
    :param suffix: number of test.
    :return: None.
    """

    input_filename = join(dirname(abspath(__file__)), 'vunit_out/test_vector_{}.hex'.format(suffix))
    output_filename = join(dirname(abspath(__file__)), 'vunit_out/golden_vector_{}.hex'.format(suffix))
    generate_test_vectors(input_filename)
    generate_golden_image_vectors(input_filename, output_filename, suffix)
    obj.set_generic("G_IN_FILE_PATH", input_filename.replace('\\', '/'))
    obj.set_generic("G_GOLDEN_FILE_PATH", output_filename.replace('\\', '/'))

for nr, test in enumerate(testbench.get_tests()):
    set_generics(test, nr)

VU.main()