#!/bin/bash
# This script is used to automate continuous integration tasks for Arduino projects
# https://github.com/per1234/arduino-ci-script


# Based on https://github.com/adafruit/travis-ci-arduino/blob/eeaeaf8fa253465d18785c2bb589e14ea9893f9f/install.sh#L11
# It seems that arrays can't been seen in other functions. So instead I'm setting $IDE_VERSIONS to a string that is the command to create the array
readonly ARDUINO_CI_SCRIPT_IDE_VERSION_LIST_ARRAY_DECLARATION="declare -a -r IDEversionListArray="

# https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#history shows CLI was added in IDE 1.5.2, Boards and Library Manager support added in 1.6.4
# This is a list of every version of the Arduino IDE that supports CLI. As new versions are released they will be added to the list.
# The newest IDE version must always be placed at the end of the array because the code for setting $NEWEST_INSTALLED_IDE_VERSION assumes that
# Arduino IDE 1.6.2 has the nasty behavior of moving the included hardware cores to the .arduino15 folder, causing those versions to be used for all builds after Arduino IDE 1.6.2 is used. For this reason 1.6.2 has been left off the list.
readonly ARDUINO_CI_SCRIPT_FULL_IDE_VERSION_LIST_ARRAY="${ARDUINO_CI_SCRIPT_IDE_VERSION_LIST_ARRAY_DECLARATION}"'("1.5.2" "1.5.3" "1.5.4" "1.5.5" "1.5.6" "1.5.6-r2" "1.5.7" "1.5.8" "1.6.0" "1.6.1" "1.6.3" "1.6.4" "1.6.5" "1.6.5-r4" "1.6.5-r5" "1.6.6" "1.6.7" "1.6.8" "1.6.9" "1.6.10" "1.6.11" "1.6.12" "1.6.13" "1.8.0" "1.8.1" "1.8.2" "1.8.3" "hourly")'


readonly ARDUINO_CI_SCRIPT_TEMPORARY_FOLDER="${HOME}/temporary/arduino-ci-script"
readonly ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER="arduino"
readonly ARDUINO_CI_SCRIPT_VERIFICATION_OUTPUT_FILENAME="${ARDUINO_CI_SCRIPT_TEMPORARY_FOLDER}/verification_output.txt"
readonly ARDUINO_CI_SCRIPT_REPORT_FILENAME="travis_ci_job_report_$(printf "%05d\n" "${TRAVIS_BUILD_NUMBER}").$(printf "%03d\n" "$(echo "$TRAVIS_JOB_NUMBER" | cut -d'.' -f 2)").tsv"
readonly ARDUINO_CI_SCRIPT_REPORT_FOLDER="${HOME}/arduino-ci-script_report"
readonly ARDUINO_CI_SCRIPT_REPORT_FILE_PATH="${ARDUINO_CI_SCRIPT_REPORT_FOLDER}/${ARDUINO_CI_SCRIPT_REPORT_FILENAME}"
# The arduino manpage(https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#exit-status) documents a range of exit codes. These exit codes indicate success, invalid arduino command, or compilation failed due to legitimate code errors. arduino sometimes returns other exit codes that may indicate problems that may go away after a retry.
readonly ARDUINO_CI_SCRIPT_HIGHEST_ACCEPTABLE_ARDUINO_EXIT_CODE=4
readonly ARDUINO_CI_SCRIPT_SKETCH_VERIFY_RETRIES=3
readonly ARDUINO_CI_SCRIPT_REPORT_PUSH_RETRIES=10

readonly ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS=0
readonly ARDUINO_CI_SCRIPT_FAILURE_EXIT_STATUS=1


# Create the folder if it doesn't exist
function create_folder()
{
  local -r folderName="$1"
  if ! [[ -d "$folderName" ]]; then
    # shellcheck disable=SC2086
    mkdir --parents $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "$folderName"
  fi
}


function set_script_verbosity()
{
  enable_verbosity

  ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL="$1"

  if [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" == "true" ]]; then
    ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL=1
  fi

  if [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" -eq 1 ]]; then
    ARDUINO_CI_SCRIPT_VERBOSITY_OPTION="--verbose"
    ARDUINO_CI_SCRIPT_QUIET_OPTION=""
    # Show stderr only
    ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT="1>/dev/null"
  elif [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" -eq 2 ]]; then
    ARDUINO_CI_SCRIPT_VERBOSITY_OPTION="--verbose"
    ARDUINO_CI_SCRIPT_QUIET_OPTION=""
    # Show stdout and stderr
    ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT=""
  else
    ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL=0
    ARDUINO_CI_SCRIPT_VERBOSITY_OPTION=""
    # cabextract only takes the short option name so this is more universally useful than --quiet
    ARDUINO_CI_SCRIPT_QUIET_OPTION="-q"
    # Don't show stderr or stdout
    ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT="&>/dev/null"
  fi

  disable_verbosity
}


# Deprecated, use set_script_verbosity
function set_verbose_script_output()
{
  set_script_verbosity 1
}


# Deprecated, use set_script_verbosity
function set_more_verbose_script_output()
{
  set_script_verbosity 2
}


# Turn on verbosity based on the preferences set by set_script_verbosity
function enable_verbosity()
{
  # Store previous verbosity settings so they can be set back to their original values at the end of the function
  shopt -q -o verbose
  ARDUINO_CI_SCRIPT_PREVIOUS_VERBOSE_SETTING="$?"

  shopt -q -o xtrace
  ARDUINO_CI_SCRIPT_PREVIOUS_XTRACE_SETTING="$?"

  if [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" -gt 0 ]]; then
    # "Print shell input lines as they are read."
    # https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
    set -o verbose
  fi
  if [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" -gt 1 ]]; then
    # "Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed. The value of the PS4 variable is expanded and the resultant value is printed before the command and its expanded arguments."
    # https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
    set -o xtrace
  fi
}


# Return verbosity settings to their previous values
function disable_verbosity()
{
  if [[ "$ARDUINO_CI_SCRIPT_PREVIOUS_VERBOSE_SETTING" == "0" ]]; then
    set -o verbose
  else
    set +o verbose
  fi

  if [[ "$ARDUINO_CI_SCRIPT_PREVIOUS_XTRACE_SETTING" == "0" ]]; then
    set -o xtrace
  else
    set +o xtrace
  fi
}


function set_application_folder()
{
  enable_verbosity

  ARDUINO_CI_SCRIPT_APPLICATION_FOLDER="$1"

  disable_verbosity
}


function set_sketchbook_folder()
{
  enable_verbosity

  ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER="$1"

  # Create the sketchbook folder if it doesn't already exist
  create_folder "$ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER"

  disable_verbosity
}


# Deprecated
function set_parameters()
{
  set_application_folder "$1"
  set_sketchbook_folder "$2"
}


# Check for errors with the board definition that don't affect sketch verification
function set_board_testing()
{
  enable_verbosity

  ARDUINO_CI_SCRIPT_TEST_BOARD="$1"

  disable_verbosity
}


# Install all specified versions of the Arduino IDE
function install_ide()
{
  enable_verbosity

  local -r startIDEversion="$1"
  local -r endIDEversion="$2"

  # https://docs.travis-ci.com/user/customizing-the-build/#Implementing-Complex-Build-Steps
  # set -o errexit will cause the script to exit as soon as any command returns a non-zero exit code. Without this the success of the function call is determined by the exit code of the last command in the function
  set -o errexit

  generate_ide_version_list_array "$ARDUINO_CI_SCRIPT_FULL_IDE_VERSION_LIST_ARRAY" "$startIDEversion" "$endIDEversion"
  INSTALLED_IDE_VERSION_LIST_ARRAY="$ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY"

  # Set "$NEWEST_INSTALLED_IDE_VERSION"
  determine_ide_version_extremes "$INSTALLED_IDE_VERSION_LIST_ARRAY"
  NEWEST_INSTALLED_IDE_VERSION="$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION"

  if [[ "$ARDUINO_CI_SCRIPT_APPLICATION_FOLDER" == "" ]]; then
    echo "ERROR: Application folder was not set. Please use the set_application_folder function to define the location of the application folder."
    return "$ARDUINO_CI_SCRIPT_FAILURE_EXIT_STATUS"
  fi
  create_folder "$ARDUINO_CI_SCRIPT_APPLICATION_FOLDER"

  # This runs the command contained in the $INSTALLED_IDE_VERSION_LIST_ARRAY string, thus declaring the array locally as $IDEversionListArray. This must be done in any function that uses the array
  # Dummy declaration to fix the "referenced but not assigned" warning.
  local IDEversionListArray
  eval "$INSTALLED_IDE_VERSION_LIST_ARRAY"
  local IDEversion
  for IDEversion in "${IDEversionListArray[@]}"; do
    # Determine download file extension
    local tgzExtensionVersionsRegex="1.5.[0-9]"
    if [[ "$IDEversion" =~ $tgzExtensionVersionsRegex ]]; then
      # The download file extension prior to 1.6.0 is .tgz
      local downloadFileExtension="tgz"
    else
      local downloadFileExtension="tar.xz"
    fi

    if [[ "$IDEversion" == "hourly" ]]; then
      # Deal with the inaccurate name given to the hourly build download
      local downloadVersion="nightly"
    else
      local downloadVersion="$IDEversion"
    fi

    wget --no-verbose $ARDUINO_CI_SCRIPT_QUIET_OPTION "http://downloads.arduino.cc/arduino-${downloadVersion}-linux64.${downloadFileExtension}"
    tar --extract --file="arduino-${downloadVersion}-linux64.${downloadFileExtension}"
    rm $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "arduino-${downloadVersion}-linux64.${downloadFileExtension}"
    mv $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "arduino-${downloadVersion}" "$ARDUINO_CI_SCRIPT_APPLICATION_FOLDER/arduino-${IDEversion}"
  done

  # Temporarily install the latest IDE version
  install_ide_version "$NEWEST_INSTALLED_IDE_VERSION"

  # Set the preferences
  # --pref option is only supported by Arduino IDE 1.5.6 and newer
  local -r unsupportedPrefOptionVersionsRegex="1.5.[0-5]"
  if ! [[ "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedPrefOptionVersionsRegex ]]; then
    # Create the sketchbook folder if it doesn't already exist. The location can't be set in preferences if the folder doesn't exist.
    create_folder "$ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER"

    # --save-prefs was added in Arduino IDE 1.5.8
    local -r unsupportedSavePrefsOptionVersionsRegex="1.5.[6-7]"
    if ! [[ "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedSavePrefsOptionVersionsRegex ]]; then
      # shellcheck disable=SC2086
      eval ${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino --pref compiler.warning_level=all --pref sketchbook.path="$ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER" --save-prefs "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
    else
      # Arduino IDE 1.5.6 - 1.5.7 load the GUI if you only set preferences without doing a verify. So I am doing an unnecessary verification just to set the preferences in those versions. Definitely a hack but I prefer to keep the preferences setting code all here instead of cluttering build_sketch and this will pretty much never be used.
      # shellcheck disable=SC2086
      eval ${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino --pref compiler.warning_level=all --pref sketchbook.path="$ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER" --verify "${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/arduino/examples/01.Basics/BareMinimum/BareMinimum.ino" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
    fi
  fi

  # Return errexit to the default state
  set +o errexit

  disable_verbosity
}


# Generate an array of Arduino IDE versions as a subset of the list provided in the base array defined by the start and end versions
# This function allows the same code to be shared by install_ide and build_sketch. The generated array is "returned" as a global named "$ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY"
function generate_ide_version_list_array()
{
  local -r baseIDEversionArray="$1"
  local startIDEversion="$2"
  local endIDEversion="$3"

  # Convert "oldest" or "newest" to actual version numbers
  determine_ide_version_extremes "$baseIDEversionArray"
  if [[ "$startIDEversion" == "oldest" ]]; then
    startIDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION"
  elif [[ "$startIDEversion" == "newest" ]]; then
    startIDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION"
  fi

  if [[ "$endIDEversion" == "oldest" ]]; then
    endIDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION"
  elif [[ "$endIDEversion" == "newest" ]]; then
    endIDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION"
  fi


  if [[ "$startIDEversion" == "" || "$startIDEversion" == "all" ]]; then
    # Use the full base array
    ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="$baseIDEversionArray"

  else
    # Start the array
    ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="$ARDUINO_CI_SCRIPT_IDE_VERSION_LIST_ARRAY_DECLARATION"'('

    local -r IDEversionListRegex="\("
    if [[ "$startIDEversion" =~ $IDEversionListRegex ]]; then
      # IDE versions list was supplied
      # Convert it to a temporary array
      local -r suppliedIDEversionListArray="${ARDUINO_CI_SCRIPT_IDE_VERSION_LIST_ARRAY_DECLARATION}${startIDEversion}"
      eval "$suppliedIDEversionListArray"
      local IDEversion
      for IDEversion in "${IDEversionListArray[@]}"; do
        # Convert any use of "oldest" or "newest" special version names to the actual version number
        if [[ "$IDEversion" == "oldest" ]]; then
          IDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION"
        elif [[ "$IDEversion" == "newest" ]]; then
          IDEversion="$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION"
        fi
        # Add the version to the array
        ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="${ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY} "'"'"$IDEversion"'"'
      done

    elif [[ "$endIDEversion" == "" ]]; then
      # Only a single version was specified
      ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="$ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY"'"'"$startIDEversion"'"'

    else
      # A version range was specified
      eval "$baseIDEversionArray"
      local IDEversion
      for IDEversion in "${IDEversionListArray[@]}"; do
        if [[ "$IDEversion" == "$startIDEversion" ]]; then
          # Start of the list reached, set a flag
          local -r listIsStarted="true"
        fi

        if [[ "$listIsStarted" == "true" ]]; then
          # Add the version to the list
          ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="${ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY} "'"'"$IDEversion"'"'
        fi

        if [[ "$IDEversion" == "$endIDEversion" ]]; then
          # End of the list was reached, exit the loop
          break
        fi
      done
    fi

    # Finish the list
    ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY="$ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY"')'
  fi
}


# Determine the oldest and newest (non-hourly unless hourly is the only version on the list) IDE version in the provided array
# The determined versions are "returned" by setting the global variables "$ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION" and "$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION"
function determine_ide_version_extremes()
{
  local -r baseIDEversionArray="$1"

  # Reset the variables from any value they were assigned the last time the function was ran
  ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION=""
  ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION=""

  # Determine the oldest and newest (non-hourly) IDE version in the base array
  eval "$baseIDEversionArray"
  local IDEversion
  for IDEversion in "${IDEversionListArray[@]}"; do
    if [[ "$ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION" == "" ]]; then
      ARDUINO_CI_SCRIPT_DETERMINED_OLDEST_IDE_VERSION="$IDEversion"
    fi
    if [[ "$ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION" == "" || "$IDEversion" != "hourly" ]]; then
      ARDUINO_CI_SCRIPT_DETERMINED_NEWEST_IDE_VERSION="$IDEversion"
    fi
  done
}


function install_ide_version()
{
  local -r IDEversion="$1"

  # Create a symbolic link so that the Arduino IDE can always be referenced from the same path no matter which version is being used.
  ln --symbolic --force $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/arduino-${IDEversion}" "${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}"
}


# Install hardware packages
function install_package()
{
  enable_verbosity

  set -o errexit

  local -r URLregex="://"
  if [[ "$1" =~ $URLregex ]]; then
    # First argument is a URL, do a manual hardware package installation
    # Note: Assumes the package is in the root of the download and has the correct folder structure (e.g. architecture folder added in Arduino IDE 1.5+)

    local -r packageURL="$1"

    # Create the hardware folder if it doesn't exist
    create_folder "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware"

    if [[ "$packageURL" =~ \.git$ ]]; then
      # Clone the repository
      local -r branchName="$2"

      cd "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware"

      if [[ "$branchName" == "" ]]; then
        git clone --quiet "$packageURL"
      else
        git clone --quiet --branch "$branchName" "$packageURL"
      fi
    else
      cd "$ARDUINO_CI_SCRIPT_TEMPORARY_FOLDER"

      # Clean up the temporary folder
      rm --force $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./*.*

      # Download the package
      wget --no-verbose $ARDUINO_CI_SCRIPT_QUIET_OPTION "$packageURL"

      # Uncompress the package
      extract ./*.*

      # Clean up the temporary folder
      rm --force $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./*.*

      # Install the package
      mv $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./* "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware/"
    fi

  elif [[ "$1" == "" ]]; then
    # Install hardware package from this repository
    # https://docs.travis-ci.com/user/environment-variables#Global-Variables
    local packageName
    packageName="$(echo "$TRAVIS_REPO_SLUG" | cut -d'/' -f 2)"
    mkdir --parents $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware/$packageName"
    cd "$TRAVIS_BUILD_DIR"
    cp --recursive $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./* "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware/${packageName}"
    # * doesn't copy .travis.yml but that file will be present in the user's installation so it should be there for the tests too
    cp $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${TRAVIS_BUILD_DIR}/.travis.yml" "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/hardware/${packageName}"

  else
    # Install package via Boards Manager

    local -r packageID="$1"
    local -r packageURL="$2"

    # Check if the newest installed IDE version supports --install-boards
    local -r unsupportedInstallBoardsOptionVersionsRange1regex="1.5.[0-9]"
    local -r unsupportedInstallBoardsOptionVersionsRange2regex="1.6.[0-3]"
    if [[ "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedInstallBoardsOptionVersionsRange1regex || "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedInstallBoardsOptionVersionsRange2regex ]]; then
      echo "ERROR: --install-boards option is not supported by the newest version of the Arduino IDE you have installed. You must have Arduino IDE 1.6.4 or newer installed to use this function."
      return 1
    else
      # Temporarily install the latest IDE version to use for the package installation
      install_ide_version "$NEWEST_INSTALLED_IDE_VERSION"

      # If defined add the boards manager URL to preferences
      if [[ "$packageURL" != "" ]]; then
        # shellcheck disable=SC2086
        eval \"${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino\" --pref boardsmanager.additional.urls="$packageURL" --save-prefs "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
      fi

      # Install the package
      # shellcheck disable=SC2086
      eval \"${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino\" --install-boards "$packageID" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"

    fi
  fi

  set +o errexit

  disable_verbosity
}


function install_library()
{
  enable_verbosity

  set -o errexit

  local -r libraryIdentifier="$1"

  # Create the libraries folder if it doesn't already exist
  create_folder "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries"

  local -r URLregex="://"
  if [[ "$libraryIdentifier" =~ $URLregex ]]; then
    # The argument is a URL
    # Note: this assumes the library is in the root of the file
    if [[ "$libraryIdentifier" =~ \.git$ ]]; then
      # Clone the repository
      local -r branchName="$2"
      local -r newFolderName="$3"

      cd "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries"

      if [[ "$branchName" == "" && "$newFolderName" == "" ]]; then
        git clone --quiet "$libraryIdentifier"
      elif [[ "$branchName" == "" ]]; then
        git clone --quiet "$libraryIdentifier"
      elif [[ "$newFolderName" == "" ]]; then
        git clone --quiet --branch "$branchName" "$libraryIdentifier"
      else
        git clone --quiet --branch "$branchName" "$libraryIdentifier" "$newFolderName"
      fi
    else
      # Assume it's a compressed file
      local -r newFolderName="$2"
      # Download the file to the temporary folder
      cd "$ARDUINO_CI_SCRIPT_TEMPORARY_FOLDER"
      # Clean up the temporary folder
      rm --force $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./*.*
      wget --no-verbose $ARDUINO_CI_SCRIPT_QUIET_OPTION "$libraryIdentifier"

      extract ./*.*
      # Clean up the temporary folder
      rm --force $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./*.*
      # Install the library
      mv $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./* "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries/${newFolderName}"
    fi

  elif [[ "$libraryIdentifier" == "" ]]; then
    # Install library from the repository
    # https://docs.travis-ci.com/user/environment-variables#Global-Variables
    local libraryName
    libraryName="$(echo "$TRAVIS_REPO_SLUG" | cut -d'/' -f 2)"
    mkdir --parents $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries/$libraryName"
    cd "$TRAVIS_BUILD_DIR"
    cp --recursive $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION ./* "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries/${libraryName}"
    # * doesn't copy .travis.yml but that file will be present in the user's installation so it should be there for the tests too
    cp $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${TRAVIS_BUILD_DIR}/.travis.yml" "${ARDUINO_CI_SCRIPT_SKETCHBOOK_FOLDER}/libraries/${libraryName}"

  else
    # Install a library that is part of the Library Manager index
    # Check if the newest installed IDE version supports --install-library
    local -r unsupportedInstallLibraryOptionVersionsRange1regex="1.5.[0-9]"
    local -r unsupportedInstallLibraryOptionVersionsRange2regex="1.6.[0-3]"
    if [[ "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedInstallLibraryOptionVersionsRange1regex || "$NEWEST_INSTALLED_IDE_VERSION" =~ $unsupportedInstallLibraryOptionVersionsRange2regex ]]; then
      echo "ERROR: --install-library option is not supported by the newest version of the Arduino IDE you have installed. You must have Arduino IDE 1.6.4 or newer installed to use this function."
      return 1
    else
      local -r libraryName="$1"

      # Temporarily install the latest IDE version to use for the library installation
      install_ide_version "$NEWEST_INSTALLED_IDE_VERSION"

       # Install the library
      # shellcheck disable=SC2086
      eval \"${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino\" --install-library "$libraryName" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"

    fi
  fi

  set +o errexit

  disable_verbosity
}


# Extract common file formats
# https://github.com/xvoland/Extract
function extract
{
  if [ -z "$1" ]; then
    # display usage if no parameters given
    echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
    echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
    return 1
  else
    local filename
    for filename in "$@"
    do
      if [ -f "$filename" ]; then
        case "${filename%,}" in
          *.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar)
            tar --extract --file="$filename"
          ;;
          *.lzma)
            unlzma $ARDUINO_CI_SCRIPT_QUIET_OPTION ./"$filename"
          ;;
          *.bz2)
            bunzip2 $ARDUINO_CI_SCRIPT_QUIET_OPTION ./"$filename"
          ;;
          *.rar)
            eval unrar x -ad ./"$filename" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
          ;;
          *.gz)
            gunzip ./"$filename"
          ;;
          *.zip)
            unzip -qq ./"$filename"
          ;;
          *.z)
            eval uncompress ./"$filename" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
          ;;
          *.7z|*.arj|*.cab|*.chm|*.deb|*.dmg|*.iso|*.lzh|*.msi|*.rpm|*.udf|*.wim|*.xar)
            7z x ./"$filename"
          ;;
          *.xz)
            unxz $ARDUINO_CI_SCRIPT_QUIET_OPTION ./"$filename"
          ;;
          *.exe)
            cabextract $ARDUINO_CI_SCRIPT_QUIET_OPTION ./"$filename"
          ;;
          *)
            echo "extract: '$filename' - unknown archive method"
            return 1
          ;;
        esac
      else
        echo "extract: '$filename' - file does not exist"
        return 1
      fi
    done
  fi
}


function set_verbose_output_during_compilation()
{
  enable_verbosity

  local -r verboseOutputDuringCompilation="$1"
  if [[ "$verboseOutputDuringCompilation" == "true" ]]; then
    ARDUINO_CI_SCRIPT_DETERMINED_VERBOSE_BUILD="--verbose"
  else
    ARDUINO_CI_SCRIPT_DETERMINED_VERBOSE_BUILD=""
  fi

  disable_verbosity
}


# Verify the sketch
function build_sketch()
{
  enable_verbosity

  local -r sketchPath="$1"
  local -r boardID="$2"
  local -r allowFail="$3"
  local -r startIDEversion="$4"
  local -r endIDEversion="$5"

  # Set default value for buildSketchExitCode
  local buildSketchExitCode="$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS"

  generate_ide_version_list_array "$INSTALLED_IDE_VERSION_LIST_ARRAY" "$startIDEversion" "$endIDEversion"

  eval "$ARDUINO_CI_SCRIPT_GENERATED_IDE_VERSION_LIST_ARRAY"
  local IDEversion
  for IDEversion in "${IDEversionListArray[@]}"; do
    # Install the IDE
    # This must be done before searching for sketches in case the path specified is in the Arduino IDE installation folder
    install_ide_version "$IDEversion"

    # The package_index files installed by some versions of the IDE (1.6.5, 1.6.5) can cause compilation to fail for other versions (1.6.5-r4, 1.6.5-r5). Attempting to install a dummy package ensures that the correct version of those files will be installed before the sketch verification.
    # Check if the newest installed IDE version supports --install-boards
    local unsupportedInstallBoardsOptionVersionsRange1regex="1.5.[0-9]"
    local unsupportedInstallBoardsOptionVersionsRange2regex="1.6.[0-3]"
    if ! [[ "$IDEversion" =~ $unsupportedInstallBoardsOptionVersionsRange1regex || "$IDEversion" =~ $unsupportedInstallBoardsOptionVersionsRange2regex ]]; then
      # shellcheck disable=SC2086
      eval \"${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino\" --install-boards arduino:dummy "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
      if [[ "$ARDUINO_CI_SCRIPT_VERBOSITY_LEVEL" -gt 1 ]]; then
        # The warning is printed to stdout
        echo "NOTE: The warning above \"Selected board is not available\" is caused intentionally and does not indicate a problem."
      fi
    fi

    if [[ "$sketchPath" =~ \.ino$ || "$sketchPath" =~ \.pde$ ]]; then
      # A sketch was specified
      if ! build_this_sketch "$sketchPath" "$boardID" "$IDEversion" "$allowFail"; then
        # build_this_sketch returned a non-zero exit code
        buildSketchExitCode=1
      fi
    else
      # Search for all sketches in the path and put them in an array
      # https://github.com/koalaman/shellcheck/wiki/SC2207
      declare -a sketches
      mapfile -t sketches < <(find "$sketchPath" -name "*.pde" -o -name "*.ino")
      local sketchName
      for sketchName in "${sketches[@]}"; do
        # Only verify the sketch that matches the name of the sketch folder, otherwise it will cause redundant verifications for sketches that have multiple .ino files
        local sketchFolder
        sketchFolder="$(echo "$sketchName" | rev | cut -d'/' -f 2 | rev)"
        local sketchNameWithoutPathWithExtension
        sketchNameWithoutPathWithExtension="$(echo "$sketchName" | rev | cut -d'/' -f 1 | rev)"
        local sketchNameWithoutPathWithoutExtension
        sketchNameWithoutPathWithoutExtension="${sketchNameWithoutPathWithExtension%.*}"
        if [[ "$sketchFolder" == "$sketchNameWithoutPathWithoutExtension" ]]; then
          if ! build_this_sketch "$sketchName" "$boardID" "$IDEversion" "$allowFail"; then
            # build_this_sketch returned a non-zero exit code
            buildSketchExitCode=1;
          fi
        fi
      done
    fi
  done

  disable_verbosity

  return $buildSketchExitCode
}


function build_this_sketch()
{
  # Fold this section of output in the Travis CI build log to make it easier to read
  echo -e "travis_fold:start:build_sketch"

  local -r sketchName="$1"
  local -r boardID="$2"
  local -r IDEversion="$3"
  local -r allowFail="$4"

  # Produce a useful label for the fold in the Travis log for this function call
  echo "build_sketch $sketchName $boardID $IDEversion $allowFail"

  # Arduino IDE 1.8.0 and 1.8.1 fail to verify a sketch if the absolute path to it is not specified
  # http://stackoverflow.com/a/3915420/7059512
  local absoluteSketchName
  absoluteSketchName="$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"

  # Define a dummy value for arduinoExitCode so that the while loop will run at least once
  local arduinoExitCode=255
  # Retry the verification if arduino returns an exit code that indicates there may have been a temporary error not caused by a bug in the sketch or the arduino command
  while [[ $arduinoExitCode -gt $ARDUINO_CI_SCRIPT_HIGHEST_ACCEPTABLE_ARDUINO_EXIT_CODE && $verifyCount -le $ARDUINO_CI_SCRIPT_SKETCH_VERIFY_RETRIES ]]; do
    # Verify the sketch
    # shellcheck disable=SC2086
    "${ARDUINO_CI_SCRIPT_APPLICATION_FOLDER}/${ARDUINO_CI_SCRIPT_IDE_INSTALLATION_FOLDER}/arduino" $ARDUINO_CI_SCRIPT_DETERMINED_VERBOSE_BUILD --verify "$absoluteSketchName" --board "$boardID" 2>&1 | tee "$ARDUINO_CI_SCRIPT_VERIFICATION_OUTPUT_FILENAME"; local arduinoExitCode="${PIPESTATUS[0]}"
    local verifyCount=$((verifyCount + 1))
  done

  if [[ "$arduinoExitCode" != "$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS" ]]; then
    # Sketch build failed
    if [[ "$allowFail" == "true" || "$allowFail" == "require" ]]; then
      # Failure is allowed for this test
      local -r buildThisSketchExitCode="$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS"
    else
      # Failure is not allowed for this test, fail the Travis build after completing all sketch builds
      local -r buildThisSketchExitCode="$ARDUINO_CI_SCRIPT_FAILURE_EXIT_STATUS"
    fi
  else
    # Sketch build succeeded
    if [[ "$allowFail" == "require" ]]; then
      # Failure is required for this test, fail the Travis build after completing all sketch builds
      local -r buildThisSketchExitCode="$ARDUINO_CI_SCRIPT_FAILURE_EXIT_STATUS"
    else
      # Success is allowed
      local -r buildThisSketchExitCode="$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS"
    fi

    # Parse through the output from the sketch verification to count warnings and determine the compile size
    local warningCount=0
    while read -r outputFileLine; do
      # Determine program storage memory usage
      local programStorageRegex="Sketch uses ([0-9,]+) *"
      if [[ "$outputFileLine" =~ $programStorageRegex ]] > /dev/null; then
        local -r programStorageWithComma=${BASH_REMATCH[1]}
      fi

      # Determine dynamic memory usage
      local dynamicMemoryRegex="Global variables use ([0-9,]+) *"
      if [[ "$outputFileLine" =~ $dynamicMemoryRegex ]] > /dev/null; then
        local -r dynamicMemoryWithComma=${BASH_REMATCH[1]}
      fi

      # Increment warning count
      local warningRegex="warning: "
      if [[ "$outputFileLine" =~ $warningRegex ]] > /dev/null; then
        warningCount=$((warningCount + 1))
      fi

      # Check for missing bootloader
      if [[ "$ARDUINO_CI_SCRIPT_TEST_BOARD" == "true" ]]; then
        local bootloaderMissingRegex="Bootloader file specified but missing: "
        if [[ "$outputFileLine" =~ $bootloaderMissingRegex ]] > /dev/null; then
          local boardError="missing bootloader"
          if [[ "$allowFail" != "true" ]]; then
            buildThisSketchExitCode=1
          fi
        fi
      fi
    done < "$ARDUINO_CI_SCRIPT_VERIFICATION_OUTPUT_FILENAME"

    rm $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "$ARDUINO_CI_SCRIPT_VERIFICATION_OUTPUT_FILENAME"

    # Remove the stupid comma from the memory values if present
    local -r programStorage=${programStorageWithComma//,}
    local -r dynamicMemory=${dynamicMemoryWithComma//,}
  fi

  # Add the build data to the report file
  echo "$(date -u "+%Y-%m-%d %H:%M:%S")"$'\t'"$TRAVIS_BUILD_NUMBER"$'\t'"$TRAVIS_JOB_NUMBER"$'\t'"https://travis-ci.org/${TRAVIS_REPO_SLUG}/jobs/${TRAVIS_JOB_ID}"$'\t'"$TRAVIS_EVENT_TYPE"$'\t'"$TRAVIS_ALLOW_FAILURE"$'\t'"$TRAVIS_PULL_REQUEST"$'\t'"$TRAVIS_BRANCH"$'\t'"$TRAVIS_COMMIT"$'\t'"$TRAVIS_COMMIT_RANGE"$'\t'"${TRAVIS_COMMIT_MESSAGE%%$'\n'*}"$'\t'"$sketchName"$'\t'"$boardID"$'\t'"$IDEversion"$'\t'"$programStorage"$'\t'"$dynamicMemory"$'\t'"$warningCount"$'\t'"$allowFail"$'\t'"$arduinoExitCode"$'\t'"$boardError"$'\r' >> "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH"

  # End the folded section of the Travis CI build log
  echo -e "travis_fold:end:build_sketch"
  # Add a useful message to the Travis CI build log

  echo "arduino exit code: $arduinoExitCode"

  return $buildThisSketchExitCode
}


# Print the contents of the report file
function display_report()
{
  enable_verbosity

  if [ -e "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH" ]; then
    echo -e "\n\n\n**************Begin Report**************\n\n\n"
    cat "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH"
    echo -e "\n\n"
  else
    echo "No report file available for this job"
  fi

  disable_verbosity
}


# Add the report file to a Git repository
function publish_report_to_repository()
{
  enable_verbosity

  local -r token="$1"
  local -r repositoryURL="$2"
  local -r reportBranch="$3"
  local -r reportFolder="$4"
  local -r doLinkComment="$5"

  if [[ "$token" != "" ]] && [[ "$repositoryURL" != "" ]] && [[ "$reportBranch" != "" ]]; then
    if [ -e "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH" ]; then
      # Location is a repository
      if git clone --quiet --branch "$reportBranch" "$repositoryURL" "${HOME}/report-repository"; then
        # Clone was successful
        create_folder "${HOME}/report-repository/${reportFolder}"
        cp $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH" "${HOME}/report-repository/${reportFolder}"
        cd "${HOME}/report-repository"
        git add $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "${HOME}/report-repository/${reportFolder}/${ARDUINO_CI_SCRIPT_REPORT_FILENAME}"
        git config user.email "arduino-ci-script@nospam.me"
        git config user.name "arduino-ci-script-bot"
        # Only pushes the current branch to the corresponding remote branch that 'git pull' uses to update the current branch.
        git config push.default simple
        if [[ "$TRAVIS_TEST_RESULT" != "0" ]]; then
          local -r jobSuccessMessage="FAILED"
        else
          local -r jobSuccessMessage="SUCCESSFUL"
        fi
        # Do a pull now in case another job has finished about the same time and pushed a report after the clone happened, which would otherwise cause the push to fail. This is the last chance to pull without having to deal with a merge or rebase.
        git pull $ARDUINO_CI_SCRIPT_QUIET_OPTION
        git commit $ARDUINO_CI_SCRIPT_QUIET_OPTION $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION --message="Add Travis CI job ${TRAVIS_JOB_NUMBER} report (${jobSuccessMessage})" --message="Job log: https://travis-ci.org/${TRAVIS_REPO_SLUG}/jobs/${TRAVIS_JOB_ID}" --message="Commit: https://github.com/${TRAVIS_REPO_SLUG}/commit/${TRAVIS_COMMIT}" --message="$TRAVIS_COMMIT_MESSAGE" --message="[skip ci]"
        local gitPushExitCode="1"
        local pushCount=0
        while [[ "$gitPushExitCode" != "$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS" && $pushCount -le $ARDUINO_CI_SCRIPT_REPORT_PUSH_RETRIES ]]; do
          pushCount=$((pushCount + 1))
          # Do a pull now in case another job has finished about the same time and pushed a report since the last pull. This would require a merge or rebase. Rebase should be safe since the commits will be separate files.
          git pull $ARDUINO_CI_SCRIPT_QUIET_OPTION --rebase
          git push $ARDUINO_CI_SCRIPT_QUIET_OPTION $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION "https://${token}@${repositoryURL#*//}"
          gitPushExitCode="$?"
        done
        rm --recursive --force "${HOME}/report-repository"
        if [[ "$gitPushExitCode" == "$ARDUINO_CI_SCRIPT_SUCCESS_EXIT_STATUS" ]]; then
          if [[ "$doLinkComment" == "true" ]]; then
            # Only comment if it's job 1
            local -r firstJobRegex="\.1$"
            if [[ "$TRAVIS_JOB_NUMBER" =~ $firstJobRegex ]]; then
              local reportURL
              reportURL="${repositoryURL%.*}/tree/${reportBranch}/${reportFolder}"
              comment_report_link "$token" "$reportURL"
            fi
          fi
        else
          echo "ERROR: Failed to push to remote branch."
          return 3
        fi
      else
        echo "ERROR: Failed to clone branch ${reportBranch} of repository URL ${repositoryURL}. Do they exist?"
        return 2
      fi
    else
      echo "No report file available for this job"
    fi
  else
    echo "Publishing report failed. GitHub token, repository URL, and repository branch must be defined to use this function. See https://github.com/per1234/arduino-ci-script#publishing-job-reports for instructions."
    return 1
  fi

  disable_verbosity
}


# Add the report file to a gist
function publish_report_to_gist()
{
  enable_verbosity

  local -r token="$1"
  local -r gistURL="$2"
  local -r doLinkComment="$3"

  if [[ "$token" != "" ]] && [[ "$gistURL" != "" ]]; then
    if [ -e "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH" ]; then
      # Get the gist ID from the gist URL
      local gistID
      gistID="$(echo "$gistURL" | rev | cut -d'/' -f 1 | rev)"

      # http://stackoverflow.com/a/33354920/7059512
      # Sanitize the report file content so it can be sent via a POST request without breaking the JSON
      # Remove \r (from Windows end-of-lines), replace tabs by \t, replace " by \", replace EOL by \n
      local reportContent
      reportContent=$(sed $ARDUINO_CI_SCRIPT_QUIET_OPTION -e 's/\r//' -e's/\t/\\t/g' -e 's/"/\\"/g' "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH" | awk '{ printf($0 "\\n") }')

      # Upload the report to the Gist. I have to use the here document to avoid the "Argument list too long" error from curl with long reports. Redirect output to dev/null because it dumps the whole gist to the log
      eval curl --header "\"Authorization: token ${token}\"" --data @- "\"https://api.github.com/gists/${gistID}\"" <<curlDataHere "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
{"files":{"${ARDUINO_CI_SCRIPT_REPORT_FILENAME}":{"content": "${reportContent}"}}}
curlDataHere

      if [[ "$doLinkComment" == "true" ]]; then
        # Only comment if it's job 1
        local -r firstJobRegex="\.1$"
        if [[ "$TRAVIS_JOB_NUMBER" =~ $firstJobRegex ]]; then
          local reportURL="${gistURL}#file-${ARDUINO_CI_SCRIPT_REPORT_FILENAME//./-}"
          comment_report_link "$token" "$reportURL"
        fi
      fi
    else
      echo "No report file available for this job"
    fi
  else
    echo "Publishing report failed. GitHub token and gist URL must be defined in your Travis CI settings for this repository in order to use this function. See https://github.com/per1234/arduino-ci-script#publishing-job-reports for instructions."
    return 1
  fi

  disable_verbosity
}


# Leave a comment on the commit with a link to the report
function comment_report_link()
{
  local -r token="$1"
  local -r reportURL="$2"

  eval curl $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION --header "\"Authorization: token ${token}\"" --data \"{'\"'body'\"':'\"'Once completed, the job reports for Travis CI [build ${TRAVIS_BUILD_NUMBER}]\(https://travis-ci.org/${TRAVIS_REPO_SLUG}/builds/${TRAVIS_BUILD_ID}\) will be found at:\\n${reportURL}'\"'}\" "\"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/commits/${TRAVIS_COMMIT}/comments\"" "$ARDUINO_CI_SCRIPT_VERBOSITY_REDIRECT"
}


# Deprecated because no longer necessary. Left only to maintain backwards compatibility
function check_success()
{
  echo "The check_success function is no longer necessary and has been deprecated"
}


# Set default verbosity (must be called after the function definitions
set_script_verbosity 0


# Create the temporary folder
create_folder "$ARDUINO_CI_SCRIPT_TEMPORARY_FOLDER"

# Create the report folder
create_folder "$ARDUINO_CI_SCRIPT_REPORT_FOLDER"


# Add column names to report
echo "Build Timestamp (UTC)"$'\t'"Build"$'\t'"Job"$'\t'"Job URL"$'\t'"Build Trigger"$'\t'"Allow Job Failure"$'\t'"PR#"$'\t'"Branch"$'\t'"Commit"$'\t'"Commit Range"$'\t'"Commit Message"$'\t'"Sketch Filename"$'\t'"Board ID"$'\t'"IDE Version"$'\t'"Program Storage (bytes)"$'\t'"Dynamic Memory (bytes)"$'\t'"# Warnings"$'\t'"Allow Failure"$'\t'"Exit Code"$'\t'"Board Error"$'\r' > "$ARDUINO_CI_SCRIPT_REPORT_FILE_PATH"


# Start the virtual display required by the Arduino IDE CLI: https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc#bugs
# based on https://learn.adafruit.com/continuous-integration-arduino-and-you/testing-your-project
/sbin/start-stop-daemon --start $ARDUINO_CI_SCRIPT_QUIET_OPTION $ARDUINO_CI_SCRIPT_VERBOSITY_OPTION --pidfile /tmp/custom_xvfb_1.pid --make-pidfile --background --exec /usr/bin/Xvfb -- :1 -ac -screen 0 1280x1024x16
sleep 3
export DISPLAY=:1.0
