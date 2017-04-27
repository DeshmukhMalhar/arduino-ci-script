arduino-ci-script
==========

Bash script for continuous integration of [Arduino](http://www.arduino.cc/) projects. I'm using this centrally managed script for multiple repositories to make updates easy. I'm using this with [Travis CI](http://travis-ci.org/) but it could be easily adapted to other purposes.

[![Build Status](https://travis-ci.org/per1234/arduino-ci-script.svg?branch=master)](https://travis-ci.org/per1234/arduino-ci-script)

#### Installation
- You can download a .zip of all the files from https://github.com/per1234/arduino-ci-script/archive/master.zip
- Include the script in your project by adding the following line:
```bash
source arduino-ci-script.sh
```
- Or if you want to leave the files hosted in this repository:
```bash
source <(curl -SLs https://raw.githubusercontent.com/per1234/arduino-ci-script/master/arduino-ci-script.sh)
```


#### Usage
See https://github.com/per1234/arduino-ci-script/blob/master/.travis.yml for an example of the script in use.
##### Special version names:
  - `all`: Refers to all versions of the Arduino IDE (including the hourly build). In the context of `install_ide` this means all IDE versions listed in the script (those that support the command line interface, 1.5.2 and newer). In the context of all other functions this means all IDE versions that were installed via `install_ide`.
  - `oldest`: The oldest release version of the Arduino IDE. In the context of `install_ide` this is the oldest of the IDE versions listed in the script (1.5.2, the first version to have a command line interface). In the context of build_sketch this means the oldest IDE version that was installed via `install_ide`.
  - `newest`: Refers to the newest release version of the Arduino IDE (not including the hourly build). In the context of `install_ide` this means the newest IDE version listed in the script. In the context of all other functions this means the newest IDE version that was installed via `install_ide`.
  - `hourly`: The hourly build of the Arduino IDE. Note that this is intended for beta testing only.

##### `set_parameters APPLICATION_FOLDER SKETCHBOOK_FOLDER verboseArduinoOutput`
Used to pass some parameters from .travis.yml to the script.
- Parameter: **APPLICATION_FOLDER** - This should be set to `/usr/local/share`. The Arduino IDE will be installed in the `arduino` subfolder.
- Parameter: **SKETCHBOOK_FOLDER** - The folder to be set as the Arduino IDE's sketchbook folder. Libraries installed via the Arduino IDE CLI's `--install-library` option will be installed to the `libraries` subfolder of this folder. You can also use the `libraries` subfolder of this folder for [manually installing libraries in the recommended manner](https://www.arduino.cc/en/Guide/Libraries#toc5). This setting is only supported by Arduino IDE 1.5.6 and newer.
- Parameter: **verboseArduinoOutput** - Set to `true` to turn on verbose output during compilation.

##### `install_ide [IDE_VERSIONS]`
##### `install_ide [startVersion [endVersion]]`
Install all versions of the Arduino IDE specified in the script file. If no arguments are supplied all IDE versions will be installed.
- Parameter(optional): **IDE_VERSIONS** - A list of the versions of the Arduino IDE you want installed. e.g. `'("1.6.5-r5" "1.6.9" "1.8.2")'`
  - Problematic IDE versions - Some older versions of the Arduino IDE have bugs or limitations that may cause problems if used with this script:
    - 1.5.1 and older - The command line interface was added in 1.5.2, thus no version older than that can be used.
    - 1.5.4 and older - Do not support board-specific parameters, set by custom **Tools** menu items.
    - 1.5.5 and older - Do not support setting preferences (`--pref`), thus the sketchbook folder argument of `set_parameters` will not be used.
    - 1.5.6 and older - `-` or `.` are not allowed in sketch or library folder names. If any are present the Arduino IDE will hang indefinitely when it's executed.
    - 1.6.2 - Moves its hardware packages to the .arduino15 folder, causing all other IDE versions to use those cores, some of which are not compatible. For this reason 1.6.2 has been removed from the default list of versions but may still be specified via the `IDE_VERSIONS` argument.
    - 1.6.3 and older - Do not support installing boards (`--install-boards`), thus `install_package` can't be used.
- Parameter(optional): **startVersion** - The oldest version of the Arduino IDE to install.
- Parameter(optional): **endVersion** - The newest version of the Arduino IDE to install. If this argument is omitted then ONLY startVersion will be installed.

##### `install_package packageID [packageURL]`
Install a hardware package. Only the **Arduino AVR Boards** package is included with the Arduino IDE installation. Packages are installed to `$HOME/.arduino15/packages. You must call `install_ide` before this function. This feature is only available with Arduino IDE 1.6.4 and newer.
- Parameter: **packageID** - `package name:platform architecture[:version]`. If `version` is omitted the most recent version will be installed. e.g. `arduino:samd` will install the most recent version of **Arduino SAM Boards**.
- Parameter(optional): **packageURL** - The URL of the Boards Manager JSON file for 3rd party hardware packages. This can be omitted for hardware packages that are included in the official Arduino JSON file (e.g. Arduino SAM Boards, Arduino SAMD Boards, Intel Curie Boards).

##### `install_library_from_repo`
Install the library from the current repository. Assumes the library is in the root of the repository. The library is installed to the `libraries` subfolder of the sketchbook folder.

##### `install_library_dependency libraryDependencyURL`
Install a library to the `libraries` subfolder of the sketchbook folder.
- Parameter: **libraryDependencyURL** - The URL of the library download. This can be any compressed file format or a .git file will cause that repository to be cloned. Assumes the library is located in the root of the file.

##### `install_library_dependency_via_library_manager libraryName`
Install a library that is listed in the Arduino Library Manager index. The library is installed to the `libraries` subfolder of the sketchbook folder. You must call `install_ide` before this function. This feature is only available with Arduino IDE 1.6.4 and newer installed.
- Parameter: **libraryName** - The name of the library to install. You can specify a version separated from the name by a colon, e.g. "LiquidCrystal I2C:1.1.2". If no version is specified the most recent version will be installed. You can also specify comma-separated lists of library names.

##### `build_sketch sketchPath boardID IDEversion allowFail`
Pass some parameters from .travis.yml to the script. `build_sketch` will echo the arduino exit code to the log, which is documented at https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#exit-status.
- Parameter: **sketchPath** - Path to a sketch or folder containing sketches. If a folder is specified it will be recursively searched and all sketches will be verified.
- Parameter: **boardID** - `package:arch:board[:parameters]` ID of the board to be compiled for. e.g. `arduino:avr:uno`. Board-specific parameters are only supported by Arduino IDE 1.5.5 and newer.
- Parameter: **IDEversion** - The version of the Arduino IDE to use to verify the sketch.
- Parameter: **allowFail** - `true` or `false`. Allow the verification to fail without causing the CI build to fail.

##### `display_report`
Echo a tab separated report of all verification results to the log. The report consists of:
- Build timestamp
- Travis build number
- Branch
- Commit hash of the build
- Commit subject
- Sketch filename
- Board ID
- IDE version
- Program storage usage
- Dynamic memory usage by global variables (not available for some boards)
- Number of warnings
- Allowed to fail
- Sketch verification exit code

Note that Travis CI runs each build of the job in a separate virtual machine so if you have multiple jobs you will have multiple reports. The only way I have found to generate a single report for all tests is to run them as a single job. This means not setting multiple matrix environment variables in the `env` array. See https://docs.travis-ci.com/user/environment-variables.

##### `check_success`
This function returns an exit code of 1 if any sketch verification failed except for those that were allowed failure by setting the `build_sketch` function's `allowFail` argument to `"true"`. Returns 0 otherwise.


#### Contributing
Pull requests or issue reports are welcome! Please see the [contribution rules](https://github.com/per1234/arduino-ci-script/blob/master/CONTRIBUTING.md) for instructions.

