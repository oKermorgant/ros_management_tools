Some scripts to easily use ROS 1 and ROS 2

## ROS 1 / ROS 2 management

The script `ros_management.bash` has a set of tools to handle ROS 1 / ROS 2 workspaces. It can be sourced in a `.bashrc` after defining the two variables `ros1_workspaces` and `ros2_workspaces`, that point to the overlay-ordered workspaces:

```bash
ros1_workspaces="/opt/ros/noetic ~/a_first_ros1_workspace ~/main_ros1_overlay"
ros2_workspaces="/opt/ros/foxy ~/some_ros2_workspace ~/main_ros2_overlay"
source /path/to/ros_management.bash
ros1ws  # activate ROS 1 / disable ROS 2
ros2ws  # activate ROS 2 / disable ROS 1
```

## Options

- if sourced with `-p`, the script will also update the bash prompt in order to know whether we are in a ROS 1 or ROS 2 terminal
- if sourced with `-k`, the settings will be stored and automatically loaded in any new terminal.
    - settings are stored in `~/.ros_management_auto_init`
    - if sourced with `-ros1` or `-ros2`, will directly activate the given version, unless other settings have been stored

If you use `-k` in your `~/.bashrc` it is better to use `-ros1` or `-ros2` instead of `ros1ws` / `ros2ws`, as the latter will override any previous setting.

### Restrict ROS 2 to a network interface

The function `ros_restrict` takes a network interface (or `WIFI` / `ETH`) and will only use this interface for ROS 2 (in this terminal).
It is designed for fastRTPS and Cyclone DDS.

```bash
ros_restrict WIFI  # only uses WiFi
# or ros_restrict wlan0 if it is the name of the wifi interface
```
If `ros_management.bash` was sourced with `-k` then this restriction is loaded in any new terminal

### Reset previous settings

To ignore the stored settings (ros version / network interface restriction) there are two options:
- run `ros_reset` that removes any previous settings and sets `ROS_LOCALHOST_ONLY` for ROS 2
- source the script without `-k`, the settings will still be here but will not be loaded in this terminal

### Example

```bash
ros1_workspaces="/opt/ros/noetic ~/a_first_ros1_workspace ~/main_ros1_overlay"
ros2_workspaces="/opt/ros/foxy ~/some_ros2_workspace ~/main_ros2_overlay"
# activate ROS 1 workspaces unless otherwise set before, also modify the prompt
source /path/to/ros_management.bash -p -k -ros1

#activate ROS 2 workspaces and save it for future terminals
ros2ws
# restrict to ethernet, save it for future terminals
ros_restrict eth0
```

### More examples

A few functions, that are designed for use at Centrale Nantes, also exist:
- `ros_baxter`: configure ROS 1 to connect on Baxter's ROSMASTER through ethernet
- `ros_turtle`: configure ROS 2 to use the same ROS_DOMAIN_ID as our Turtlebots and restrict to Wifi

Any similar function can be defined and used with the custom prompt and stored settings. The function should start with `ros_` and are assumed to be exclusive (only the latest called `ros_` function is stored for future terminals).s


## QtCreator configuration

The `qtcreator` folder includes a script to generate ad-hoc configuration files (raw CMake / ROS 1 / ROS 2) for Qt Creator.

