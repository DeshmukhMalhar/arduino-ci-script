# This script is used to automate continuous integration tasks for Arduino projects
# https://github.com/per1234/arduino-ci-script

#!/bin/bash

# https://docs.travis-ci.com/user/customizing-the-build/#Implementing-Complex-Build-Steps
# -e will cause the script to exit as soon as one command returns a non-zero exit code
set -e


# Based on https://github.com/adafruit/travis-ci-arduino/blob/eeaeaf8fa253465d18785c2bb589e14ea9893f9f/install.sh#L11
# It seems that arrays can't been seen in other functions. So instead I'm setting $IDE_VERSIONS to a string that is the command to create the array
# https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#history shows CLI was added in IDE 1.5.2, Boards and Library Manager support added in 1.6.4
# This is a list of every version of the Arduino IDE that supports CLI. As new versions are released they will be added to the list.
# The newest IDE version must always be placed at the end of the array because the code for setting $NEWEST_IDE_VERSION assumes that
# Arduino IDE 1.6.2 has the nasty behavior of copying the included hardware cores to the .arduino15 folder, causing those versions to be used for all builds after Arduino IDE 1.6.2 is used. For this reason 1.6.2 has been left off the list.
# Arduino IDE 1.6.4 is causing errors due to "cc.arduino.contributions.SignatureVerificationFailedException: package_index.json file signature verification failed" so I'm removing it from the list.
IDE_VERSIONS='declare -a ide_versions=("1.6.0" "1.6.1" "1.6.3" "1.6.4" "1.6.5-r5" "1.6.6" "1.6.7" "1.6.8" "1.6.9" "1.6.10" "1.6.11" "1.6.12" "1.6.13" "1.8.0" "1.8.1" "1.8.2")'

TEMPORARY_FOLDER="$HOME/temporary"
VERIFICATION_OUTPUT_FILENAME="$TEMPORARY_FOLDER/verification_output.txt"
REPORT_FILENAME="$HOME/report.txt"
# The Arduino IDE returns exit code 255 after a failed file signature verification of the boards manager JSON file. This does not indicate an issue with the sketch and the problem may go away after a retry.
SKETCH_VERIFY_RETRIES=3


# Add column names to report
echo "Build Timestamp (UTC)"$'\t'"Build #"$'\t'"Branch"$'\t'"Commit"$'\t'"Commit Message"$'\t'"Sketch Filename"$'\t'"Board ID"$'\t'"IDE Version"$'\t'"Program Storage (bytes)"$'\t'"Dynamic Memory (bytes)"$'\t'"# Warnings"$'\t'"Allow Failure" > "$REPORT_FILENAME"

# Create the temporary folder
mkdir "$TEMPORARY_FOLDER"


# Start the virtual display required by the Arduino IDE CLI: https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#bugs
# based on https://learn.adafruit.com/continuous-integration-arduino-and-you/testing-your-project
/sbin/start-stop-daemon --start --quiet --pidfile /tmp/custom_xvfb_1.pid --make-pidfile --background --exec /usr/bin/Xvfb -- :1 -ac -screen 0 1280x1024x16
sleep 3
export DISPLAY=:1.0


function set_parameters()
{
  APPLICATION_FOLDER="$1"
  SKETCHBOOK_FOLDER="$2"
  local verboseArduinoOutput="$3"

  if [[ "$verboseArduinoOutput" == "true" ]]; then
    VERBOSE_BUILD="--verbose-build"
  fi
}


# Install all versions of the Arduino IDE defined in the ide_versions array in set_parameters()
function install_ide()
{
  if [[ "$1" != "" ]]; then
    # IDE versions argument was supplied
    IDE_VERSIONS="$1"
  fi

  # This runs the command contained in the $IDE_VERSIONS string, thus declaring the array locally as $ide_versions. This must be done in any function that uses the array
  eval "$IDE_VERSIONS"

  for IDEversion in "${ide_versions[@]}"; do
    wget "http://downloads.arduino.cc/arduino-${IDEversion}-linux64.tar.xz"
    tar xf "arduino-${IDEversion}-linux64.tar.xz"
    rm "arduino-${IDEversion}-linux64.tar.xz"
    sudo mv "arduino-${IDEversion}" "$APPLICATION_FOLDER/arduino-${IDEversion}"
    NEWEST_IDE_VERSION="$IDEversion"
  done

  # Temporarily install the latest IDE version
  install_ide_version "$NEWEST_IDE_VERSION"
  # Create the link that will be used for all IDE installations
  sudo ln -s "$APPLICATION_FOLDER/arduino/arduino" /usr/local/bin/arduino
  # Create the sketchbook folder. The location can't be set in preferences if the folder doesn't exist.
  mkdir "$SKETCHBOOK_FOLDER"
  # Set the preferences
  arduino --pref compiler.warning_level=all --pref sketchbook.path="$SKETCHBOOK_FOLDER" --save-prefs
  # Uninstall the IDE
  uninstall_ide_version "$NEWEST_IDE_VERSION"
}


function install_ide_version()
{
  local IDEversion="$1"
  sudo mv "${APPLICATION_FOLDER}/arduino-${IDEversion}" "${APPLICATION_FOLDER}/arduino"
}


function uninstall_ide_version()
{
  local IDEversion="$1"
  sudo mv "${APPLICATION_FOLDER}/arduino" "${APPLICATION_FOLDER}/arduino-${IDEversion}"
}


# Install hardware packages
function install_package()
{
  local packageID="$1"
  local packageURL="$2"

  # Temporarily install the latest IDE version to use for the package installation
  install_ide_version "$NEWEST_IDE_VERSION"

  # If defined add the boards manager URL to preferences
  if [[ "$packageURL" != "" ]]; then
    arduino --pref boardsmanager.additional.urls="$packageURL" --save-prefs
  fi

  # Install the package
  arduino --install-boards "$packageID"

  # Uninstall the IDE
  uninstall_ide_version "$NEWEST_IDE_VERSION"
}


# Install the library from the current repository
function install_library_from_repo()
{
  # https://docs.travis-ci.com/user/environment-variables#Global-Variables
  local library_name="$(echo $TRAVIS_REPO_SLUG | cut -d'/' -f 2)"
  mkdir "${SKETCHBOOK_FOLDER}/libraries/$library_name"
  cd "$TRAVIS_BUILD_DIR"
  cp -r -v * "${SKETCHBOOK_FOLDER}/libraries/${library_name}"
  # * doesn't copy .travis.yml but that file will be present in the user's installation so it should be there for the tests too
  cp -v "${TRAVIS_BUILD_DIR}/.travis.yml" "${SKETCHBOOK_FOLDER}/libraries/${library_name}"
}


# Install external libraries
# Note: this assumes the library is in the root of the file
function install_library_dependency()
{
  local libraryDependencyURL="$1"

  if [[ "$libraryDependencyURL" =~ \.git$ ]]; then
    # Clone the repository
    cd "${SKETCHBOOK_FOLDER}/libraries"
    git clone "$libraryDependencyURL"
  else
    # Assume it's a compressed file

    # Download the file to the temporary folder
    cd "$TEMPORARY_FOLDER"
    wget "$libraryDependencyURL"

    # This script handles any compressed file type
    source "${TRAVIS_BUILD_DIR}/extract.sh"
    extract *.*
    # Clean up the temporary folder
    rm *.*
    # Install the library
    mv * "${SKETCHBOOK_FOLDER}/libraries"
  fi
}


# Verify the sketch
function build_sketch()
{
  local sketchPath="$1"
  local boardID="$2"
  local IDEversion="$3"
  local allowFail="$4"

  if [[ "$IDEversion" == "all" ]]; then
    eval "$IDE_VERSIONS"
    for IDEversion in "${ide_versions[@]}"; do
      find_sketches "$sketchPath" "$boardID" "$IDEversion" "$allowFail"
    done
  else
    if [[ "$IDEversion" == "newest" ]]; then
      local IDEversion="$NEWEST_IDE_VERSION"
    fi
    find_sketches "$sketchPath" "$boardID" "$IDEversion" "$allowFail"
  fi
}


function find_sketches()
{
  local sketchPath="$1"
  local boardID="$2"
  local IDEversion="$3"
  local allowFail="$4"

  # Install the IDE
  # This must be done before searching for sketches in case the path specified is in the Arduino IDE installation folder
  install_ide_version "$IDEversion"

  if [[ "$sketchPath" =~ \.ino$ || "$sketchPath" =~ \.pde$ ]]; then
    # A sketch was specified
    build_this_sketch "$sketchPath" "$boardID" "$IDEversion" "$allowFail"
  else
    # Search for all sketches in the path and put them in an array
    # https://github.com/adafruit/travis-ci-arduino/blob/eeaeaf8fa253465d18785c2bb589e14ea9893f9f/install.sh#L100
    declare -a sketches
    sketches=($(find "$sketchPath" -name "*.pde" -o -name "*.ino"))
    for sketchName in "${sketches[@]}"; do
      # Only verify the sketch that matches the name of the sketch folder, otherwise it will cause redundant verifications for sketches that have multiple .ino files
      local sketchFolder="$(echo $sketchName | rev | cut -d'/' -f 2 | rev)"
      local sketchNameWithoutPathWithExtension=$(echo $sketchName | rev | cut -d'/' -f 1 | rev)
      local sketchNameWithoutPathWithoutExtension=$(echo $sketchNameWithoutPathWithExtension | cut -d'.' -f1)
      if [[ "$sketchFolder" == "$sketchNameWithoutPathWithoutExtension" ]]; then
        build_this_sketch "$sketchName" "$boardID" "$IDEversion" "$allowFail"
      fi
    done
  fi
  # Uninstall the IDE
  uninstall_ide_version "$IDEversion"
}


function build_this_sketch()
{
  echo -e "travis_fold:start:build_sketch"

  local sketchName="$1"
  local boardID="$2"
  local IDEversion="$3"
  local allowFail="$4"

  # Produce a useful label for the fold in the Travis log for this function call
  echo "build_sketch $sketchName $boardID $IDEversion $allowFail"

  local sketchBuildExitCode=255
  # Retry the verification if it returns exit code 255
  while [[ "$sketchBuildExitCode" == "255" && $verifyCount < $SKETCH_VERIFY_RETRIES ]]; do
    # Verify the sketch
    arduino $VERBOSE_BUILD --verify "$sketchName" --board "$boardID" 2>&1 | tee "$VERIFICATION_OUTPUT_FILENAME"; local sketchBuildExitCode="${PIPESTATUS[0]}"
    local verifyCount=$((verifyCount + 1))
  done

  # Parse through the output from the sketch verification to count warnings and determine the compile size
  local warningCount=0
  while read line; do
    # Determine program storage memory usage
    local re="Sketch uses ([0-9,]+) *"
    if [[ "$line" =~ $re ]] > /dev/null; then
      local programStorage=${BASH_REMATCH[1]}
    fi

    # Determine dynamic memory usage
    local re="Global variables use ([0-9,]+) *"
    if [[ "$line" =~ $re ]] > /dev/null; then
      local dynamicMemory=${BASH_REMATCH[1]}
    fi

    # Increment warning count
    local re="warning: "
    if [[ "$line" =~ $re ]] > /dev/null; then
      local warningCount=$((warningCount + 1))
    fi
  done < "$VERIFICATION_OUTPUT_FILENAME"

  rm "$VERIFICATION_OUTPUT_FILENAME"

  # Remove the stupid comma from the memory values if present
  local programStorage=${programStorage//,}
  local dynamicMemory=${dynamicMemory//,}

  # Add the build data to the report file
  echo `date -u "+%Y-%m-%d %H:%M:%S"`$'\t'"$TRAVIS_BUILD_NUMBER"$'\t'"$TRAVIS_BRANCH"$'\t'"$TRAVIS_COMMIT"$'\t'"${TRAVIS_COMMIT_MESSAGE%%$'\n'*}"$'\t'"$sketchName"$'\t'"$boardID"$'\t'"$IDEversion"$'\t'"$programStorage"$'\t'"$dynamicMemory"$'\t'"$warningCount"$'\t'"$allowFail" >> "$REPORT_FILENAME"

  # If the sketch build failed and failure is not allowed for this test then fail the Travis build after completing all sketch builds
  if [[ "$sketchBuildExitCode" != 0 ]]; then
    if [[ "$allowFail" != "true" ]]; then
      TRAVIS_BUILD_EXIT_CODE=1
    fi
  fi

  echo -e "travis_fold:end:build_sketch"
  echo "arduino exit code: $sketchBuildExitCode"
}


# Print the contents of the report file
function display_report()
{
  if [ -e "$REPORT_FILENAME" ]; then
    echo -e "\n\n\n**************Begin Report**************\n\n\n"
    cat "$REPORT_FILENAME"
    echo -e "\n\n"
  else
    echo "No report file available for this job"
  fi
}


# Return 1 if any of the sketch builds failed
function check_success()
{
  if [[ "$TRAVIS_BUILD_EXIT_CODE" != "" ]]; then
    return 1
  fi
}
