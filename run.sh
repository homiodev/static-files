#!/bin/bash

set -e

echo "Check required commands are present"
abort=0
for cmd in wget tar unzip; do
    if [ -z "$(command -v $cmd)" ]; then
        cat >&2 <<-EOF
        Error: unable to find required command: $cmd
        EOF
        abort=1
    fi
done
[ $abort = 1 ] && exit 1

echo "Check sudo"
sudo=
if [ "$(id -u)" -ne 0 ]; then
    if [ -z "$(command -v sudo)" ]; then
        cat >&2 <<-EOF
        Error: this app needs the ability to run commands as root.
        You are not running as root and we are unable to find "sudo" available.
        EOF
        exit 1
    fi
    sudo="sudo -E"
fi

root_path="/opt/homio"

if [[ -f "homio.properties" ]]; then
    while IFS="=" read -r key value; do
        if [[ "$key" == "rootPath" && -d "$value" ]]; then
            root_path="$value"
        fi
    done < "homio.properties"
fi

$sudo mkdir -p "$root_path"
echo "root_path: '$root_path'"

# Standard Java installation path
java_home="/usr/lib/jvm/jdk-21-jre"
java_path="$java_home/bin/java"

# Check if Java 21 is already installed in standard location
if [ -x "$java_path" ]; then
    java_version=$("$java_path" -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [[ "$java_version" == "21" ]]; then
        echo "Found Java 21 in standard location: $java_path"
    else
        # Handle version mismatch
        echo "Found Java $java_version at $java_path - requires Java 21"
        java_path=""
    fi
fi

if [[ ! -x "$java_path" ]]; then
    echo "Java 21 not found. Installing to $java_home..."
    
    # Download Java 21
    $sudo mkdir -p /usr/lib/jvm
    $sudo wget -O /tmp/jre.tar.gz 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21+35/OpenJDK21U-jre_x64_linux_hotspot_21_35.tar.gz'
    
    # Extract to standard location
    $sudo tar xzf /tmp/jre.tar.gz -C /usr/lib/jvm
    $sudo mv "/usr/lib/jvm/$(ls /usr/lib/jvm | grep jdk-21)" "$java_home"
    $sudo rm -f /tmp/jre.tar.gz
    
    echo "Java 21 installed to $java_home"
else
    echo "Using existing Java 21 installation"
fi

echo "Java path: $java_path"

# Define the file name and path
launcher="$root_path/homio-launcher.jar"

# Check if launcher exists
if [[ ! -f "$launcher" ]]; then
    echo "Downloading launcher from GitHub..."
    wget -O "$launcher" 'https://github.com/homiodev/static-files/raw/master/homio-launcher.jar'
    echo "Launcher downloaded successfully"
fi

update_application() {
    if [[ -f "$root_path/homio-app.zip" ]]; then
        echo "Update package found"
        if [[ -f "$root_path/homio-app.jar" ]]; then
            echo "Creating backup of homio-app.jar"
            cp "$root_path/homio-app.jar" "$root_path/homio-app.jar_backup"
        fi

        echo "Extracting update package"
        if unzip -o "$root_path/homio-app.zip" -d "$root_path"; then
            echo "Update applied successfully"
            rm -f "$root_path/homio-app.zip"
        else
            echo "Update failed! Restoring backup"
            if [[ -f "$root_path/homio-app.jar_backup" ]]; then
                mv "$root_path/homio-app.jar_backup" "$root_path/homio-app.jar"
            fi
            rm -f "$root_path/homio-app.zip"
        fi
    elif [[ -f "$root_path/homio-app.jar_backup" ]]; then
        echo "Restoring homio-app.jar from backup"
        mv "$root_path/homio-app.jar_backup" "$root_path/homio-app.jar"
    fi
}

update_application

if [[ -f "$root_path/homio-app.jar" ]]; then
    app="homio-app.jar"
else
    app="homio-launcher.jar"
fi

echo "Starting Homio: $java_path -jar $root_path/$app"
$sudo "$java_path" -jar "$root_path/$app"

echo "Restarting Homio"
exec "$0"
