Some scripts to easily use ROS 1 and ROS 2

## ROS 1 / ROS 2 management

The script `ros_management.bash` is a set of tools to handle ROS 1 / ROS 2 workspaces. It can be sourced in a `.bashrc` after defining the two variables `ros1_workspaces` and `ros2_workspaces`, that list to the overlay-ordered workspaces:

```bash
ros1_workspaces="/opt/ros/noetic ~/a_first_ros1_workspace ~/main_ros1_overlay"
ros2_workspaces="/opt/ros/foxy ~/some_ros2_workspace ~/main_ros2_overlay"
source /path/to/ros_management.bash
```

The main functions  are `ros1ws` and `ros2ws`, to activate either ROS 1 or ROS 2 workspaces in a terminal.

## Arguments

#### Prefer ROS 1 or ROS 2 with `-ros1` or `-ros2`: 

If sourced with `-ros1` or `-ros2`, will directly activate the given version and consider it the prefered one.

#### Modify the prompt with `-p`

If sourced with `-p`, the script will update the bash prompt in order to know:
    - whether the non-prefered ROS version is active (if any)
    - whether ROS 2 is restricted to a specific network interface
    
```bash
source /path/to/ros_management.bash -ros1 -p # default to ROS 1, thus [ROS1] is not displayed in the prompt
ros2ws # ros2 is now active and [ROS2] is displayed
```

#### Restrict ROS 2 to localhost with `-lo`

In this case the script will set `ROS_LOCALHOST_ONLY` for ROS 2

#### Store settings with `-k`

If the settings are stored then any new terminal will have the same settings as the previous one, assuming that `ros_management.bash` is sourced in your `.bashrc` file.

The idea is that when working on a given robot, or a given ROS version, the special setting is only done once even if new terminals are open afterwards (it may happen when using ROS).

Manual calls to `rosXws` or `ros_restrict` will override `-ros1/2` and `-lo` arguments in new terminals.

Settings are stored in `~/.ros_management_auto_init`, delete this file to restore the default behavior

```bash
source /path/to/ros_management.bash -ros2 -k # default to ROS 2 + store settings
ros1ws # ros1 is now active and will be active in new terminals
```
```bash
source /path/to/ros_management.bash -ros2 -k -p # also activate prompt
ros1ws # ros1 is now active and will be active in new terminals, [ROS1] is displayed as well
```

## Network interface functions

### Restrict ROS 2 to a network interface

The function `ros_restrict` takes a network interface (or `lo` / `WIFI` / `ETH`) and will only use this interface for ROS 2 (in this terminal).
It is designed for FastRTPS and Cyclone DDS. In practice, a few XML is needed to properly handle these cases:
- https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/whitelist.html
- https://answers.ros.org/question/365051/using-ros2-offline-ros_localhost_only1
- https://answers.ros.org/question/405753/limit-ros-traffic-to-specific-network-interface

```bash
ros_restrict WIFI  # only uses WiFi, let the script find the interface name
# or ros_restrict wlan0 if it is the name of the wifi interface
```
If `ros_management.bash` was sourced with `-k` then this restriction is forwarded to any new terminal.

### Reset network settings

Running `ros_reset` removes any previous network setting:
- unset `ROS_IP` and `ROS_MASTER_URI` for ROS 1
- sets `ROS_LOCALHOST_ONLY` with prefered interface being `lo` for ROS 2

### Example

```bash
#activate ROS 2 workspaces and save it for future terminals
ros2ws
# restrict to ethernet, save it for future terminals
ros_restrict eth0
```

### More examples

A few functions, that are designed for use at Centrale Nantes, also exist:
- `ros_baxter`: configure ROS 1 to connect on Baxter's ROSMASTER through ethernet, restrict ROS 2 to localhost
- `ros_turtle`: configure ROS 2 to use the same ROS_DOMAIN_ID as our Turtlebots and restrict to Wifi

Any similar function can be defined and used with the custom prompt and stored settings. The function should start with `ros_` and are assumed to be exclusive (only the latest called `ros_` function is stored for future terminals).

## `colcon` shortcuts (ROS 2)

In ROS 1, `catkin build` could be run from anywhere inside the workspace while in ROS 2, `colcon build` has to be called from the root (where directories `src`, `build` and `install` lie). In practice, calling `colcon build` from e.g. your package directory will actually use this folder as the workspace.

The command `colbuild` offers the same usage as `catkin`: it calls `colcon build --symlink-install` and can be run from anywhere inside the workspace. It provides two options:
- `-p`: similar to `--packages-select`
- `-pu`: similar to `--packages-up-to`

## QtCreator configuration

The `qtcreator` folder includes a script to generate ad-hoc configuration files (raw CMake / ROS 1 / ROS 2) for Qt Creator.
