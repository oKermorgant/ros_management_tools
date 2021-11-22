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
The `ros1ws` and `ros2ws` functions also update the bash prompt to highlight the current distro in use.

## Restrict ROS 2 to a network interface

The function `rmw_restrict` takes a network interface and will only use this interface for ROS 2 (in this terminal).
It is designed for fastRTPS and Cyclone DDS.

```bash
rmw_restrict wlan0  # only uses WiFi
rmw_restrict        # (in another terminal): use last configuration, thus only use WiFi as well
```

## QtCreator configuration

The `qtcreator` folder includes a script to generate ad-hoc configuration files (raw CMake / ROS 1 / ROS 2) for this IDE.
