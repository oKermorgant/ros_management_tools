# ide_config
A Python script to generate QtCreator and VS Code configuration file for CMake, ROS 1 and ROS 2 projects


## Usage

Just run the script from the folder where the `CMakeLists.txt` file is. It will identify whether it is a raw CMake, ROS 1 or ROS 2 package and pick the suitable build directory.

If the configuration file already exists, it will ask for confirmation.

## Options

- `-c <path>` : to indicate the path to `CMakeLists.txt` if it is not the current folder (default `.`)
- `-b <path>` : build folder (relative to CMake file) to use, for raw CMake projects (default `./build`)
- `--clean` : deletes the build folder before creating it again (default False)

## Generated files

- for Qt Creator: `CMakeLists.txt.user`
- for VS Code: `.vscode/settings.json`
