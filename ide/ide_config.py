#!/usr/bin/env python3

import sys
import os
from shutil import rmtree
from time import localtime, sleep
from subprocess import check_output, Popen, CalledProcessError
import argparse


def dict_replace(s, d):
    for key in d:
        s = s.replace(key, d[key])
    return s


def extract(s,left='(',right=')'):
    return s.partition(left)[2].partition(right)[0].strip()


def gen_qtcreator(cmake_dir, build_dir, build_type):
    home = os.path.expanduser('~') + '/'
    envID_file = home + '.config/QtProject/QtCreator.ini'
    confID_file = home + '.config/QtProject/qtcreator/profiles.xml'
    cmake_user = f'{cmake_dir}/CMakeLists.txt.user'

    class Version:
        def __init__(self, s):
            self.s = self.split(s)

        def split(self,s):
            s = [int(v) for v in s.split('.')]
            if len(s) != 3:
                s += [0]*(3-len(s))
            return s

        def rep(self):
            return '.'.join(str(v) for v in self.s)

        def __eq__(self,s):
            s = self.split(s)
            return s[0] == self.s[0] and s[1] == self.s[1]

        def __ge__(self, s):
            s = self.split(s)
            for i in range(3):
                if self.s[i] > s[i]:
                    return True
                elif self.s[i] < s[i]:
                    return False
            return True

    # get ID's on this computer and Qt Creator version
    def readConfig():
        with open(envID_file) as f:
            envID = f.read().split('Settings\\EnvironmentId=@ByteArray(')[1].split(')')[0]
        with open(confID_file) as f:
            data = f.read()
            confID = data.split('<value type="QString" key="PE.Profile.Id">')[1].split('<')[0]
            qtcVersion = Version(data.split('<!-- Written by QtCreator ')[1].split(', ')[0])
        return envID, confID, qtcVersion

    qt_proc = None

    while True:

        if qt_proc is None and (not os.path.exists(envID_file) or not os.path.exists(confID_file)):
            print('Will run QtCreator once to generate local configuration')
            sleep(3)
            qt_proc = Popen(['qtcreator','&'], shell=False)
        try:
            envID, confID, qtcVersion = readConfig()
            break
        except:
            sleep(1)

    if qt_proc is not None:
        try:
            qt_proc.kill()
            qt_proc.communicate()
        except:
            pass

    # load configuration template
    gen_config_path = os.path.dirname(os.path.abspath(__file__))

    template_name = 'CMakeLists.txt.user.template.pre4.8'
    if qtcVersion == '4.8':
        template_name = 'CMakeLists.txt.user.template.4.8'
    elif qtcVersion == '4.9':
        template_name = 'CMakeLists.txt.user.template.4.9'
    elif qtcVersion >= '4.10':
        template_name = 'CMakeLists.txt.user.template'

    with open(gen_config_path + '/' + template_name) as f:
        config = f.read()

    # header = version / time / envID
    ct = localtime()
    ct_str = []
    for key in ('year', 'mon', 'mday','hour','min','sec'):
        ct_str.append(str(getattr(ct, 'tm_'+key)).zfill(2))
    time_str = '{}-{}-{}T{}:{}:{}'.format(*ct_str)

    replace_dict = {}
    replace_dict['<gen_version/>'] = qtcVersion.rep()
    replace_dict['<gen_time/>'] = '{}-{}-{}T{}:{}:{}'.format(*ct_str)
    replace_dict['<gen_envID/>'] = envID
    replace_dict['<gen_cmake_dir/>'] = cmake_dir

    replace_dict['<gen_build_dir/>'] = build_dir
    replace_dict['<gen_install_dir/>'] = install_dir
    replace_dict['<gen_conf/>'] = confID
    replace_dict['<gen_cmake_build_type/>'] = build_type

    config = dict_replace(config, replace_dict)

    config = '\n'.join(line for line in config.splitlines() if line.strip() != '' and '!--' not in line)

    print('Configuring Qt Creator @ CMakeLists.txt.user')
    with open(cmake_user, 'w') as f:
        f.write(config)


def gen_vscode(cmake_dir, build_dir, build_type = None):
    code_dir = cmake_dir + '/.vscode'
    if not os.path.exists(code_dir):
        os.mkdir(code_dir)
    print('Configuring VS Code @ .vscode/settings.json (C/C++ - CMake Tools - clangd extensions)')

    with open(os.path.dirname(os.path.abspath(__file__)) + '/settings.json.template') as f:
        settings = f.read()

    with open(code_dir + '/settings.json', 'w') as f:
        f.write(settings.replace('<gen_build_dir>', build_dir))
    with open(code_dir + '/compile_flags.txt', 'w') as f:
        f.write('-xc++\n-std=c++17')


parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.description = 'A script to generate IDE (Qt Creator / VS Code) configuration file for CMake projects.'
parser.add_argument('-c', metavar='cmakelist_dir', help='Folder of CMakeLists.txt file',default='.')
parser.add_argument('-b', metavar='build_dir', help='Relative build folder',default='./build')
parser.add_argument('--clean', action='store_true', default=False)
args = parser.parse_args()

cmake_dir = os.path.abspath(args.c)
cmake_file = cmake_dir + '/CMakeLists.txt'
build_dir = os.path.abspath(cmake_dir + '/' + args.b)

if not os.path.exists(cmake_file):
    print('Could not find CMakeLists.txt, exiting')
    print('Given location: ' + cmake_file)
    sys.exit(0)

with open(cmake_file) as f:
    cmake = f.read().splitlines()
    
package = ''
build_type = None


class RosBuild:
    version = None
    tool = ''

    @staticmethod
    def find_ws_root(pkg_dir):

        # find a 'src' directory in this tree
        # if several, pick the one that also has a 'build' folder

        if '/src' not in pkg_dir:
            print('The package path does not comply with ROS standard (no src folder)')
            return None

        tree = pkg_dir.split('/src')

        ros_dir = tree[0]

        if len(tree) > 2:
            # check it is the correct one
            for path in tree[1:]:
                if os.path.exists(f'{ros_dir}/build'):
                    break
                ros_dir += f'/src{path}'
            else:
                # no build directory, workspace is ambiguous
                print('The package path is ambiguous (several src folders), cannot guess the workspace')
                print('Compile (catkin or colcon) from the workspace then run this script again.')
                return None

        # try to identify build tool
        if os.path.exists(f'{ros_dir}/build/COLCON_IGNORE'):
            RosBuild.tool = 'colcon'
        elif os.path.exists(f'{ros_dir}/.catkin_tools'):
            RosBuild.tool = 'catkin'

        if RosBuild.tool:
            print(f'Configuring for ROS {RosBuild.version} workspace compiled through {RosBuild.tool}')
        else:
            RosBuild.tool = ['catkin','colcon'][RosBuild.version-1]
            print(f'Could not identify build tool, picking {RosBuild.tool} for ROS {RosBuild.version}')
        return ros_dir

    @staticmethod
    def get_dirs(package):
        build_dir = ros_dir + '/build/' + package
        bin_dir = ros_dir + '/devel/.private/' + package + '/lib'
        install_dir = ros_dir + '/install/' + package
        if RosBuild.tool == 'colcon':
            bin_dir = build_dir
        return build_dir, bin_dir, install_dir


#print('Loading ' + os.path.abspath(cmake_file) + '\n')

for line in cmake:
    
    # remove comments anyway
    line = line.split('#')[0]
    while ' (' in line:
        line = line.replace(' (', '(')
    
    if 'project(' in line:
        package = extract(line)
    elif 'CMAKE_BUILD_TYPE' in line and 'set' in line:
        if line.index('set') < line.index('CMAKE_BUILD_TYPE'):
            try:
                build_type = extract(line).split()[1].strip('"').strip("'")
            except IndexError:
                build_type = None
    elif not RosBuild.version:
        if 'catkin_package' in line:
            RosBuild.version = 1
        elif 'ament_package' in line or 'ament_auto_package' in line:
            RosBuild.version = 2

# check build directory - update if ROS unless manually set
bin_dir = build_dir
install_dir = '/usr/local'

if RosBuild.version and '-b' not in sys.argv:

    ros_dir = RosBuild.find_ws_root(os.path.abspath(cmake_dir))
    if ros_dir is None:
        sys.exit(0)

    build_dir, bin_dir, install_dir = RosBuild.get_dirs(package)

    if not os.path.exists(build_dir):
        print(f'You will have to run "{RosBuild.tool} build" before loading the project in your IDE')

elif not os.path.exists(build_dir):
    os.mkdir(build_dir)
elif args.clean:
    rmtree(build_dir)
    os.mkdir(build_dir)

print('  build directory: ' + os.path.abspath(build_dir))
if bin_dir != build_dir:
    print('  bin directory:   ' + os.path.abspath(bin_dir))


if build_type is None:

    # try to identify in build directory
    cmake_cache = f'{build_dir}/CMakeCache.txt'
    if os.path.exists(cmake_cache):
        with open(cmake_cache) as f:
            cache = f.read().splitlines()
        for line in cache:
            if line.startswith('CMAKE_BUILD_TYPE'):
                build_type = line.split('=')[-1]
                if build_type:
                    print(f'  build type "{build_type}" from CMakeCache.txt')
                break

    if build_type is None:
        build_type = 'Debug'
else:
    print(f'  build type "{build_type}" from CMakeLists.txt')
print()


for ide, generator in (('qtcreator', gen_qtcreator),
                       ('code', gen_vscode)):
    try:
        available = check_output(['which',ide])
        generator(cmake_dir, build_dir, build_type)
    except CalledProcessError:
        continue
