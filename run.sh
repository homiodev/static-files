#!/bin/bash

set -e

echo "Check wget, tar, unzip, command is present"
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

jdk_dir="/usr/lib/jvm/jdk-21"
java_path=$(command -v java)
arch=$(uname -m)
os=$(uname -s | tr '[:upper:]' '[:lower:]')

# Detect JDK URL based on arch
case "$arch" in
  armv7l)
    jdk_url="https://download.bell-sw.com/java/21.0.3+10/bellsoft-jdk21.0.3+10-linux-arm32-vfp-hflt.tar.gz"
    ;;
  aarch64)
    jdk_url="https://download.bell-sw.com/java/21.0.3+10/bellsoft-jdk21.0.3+10-linux-aarch64.tar.gz"
    ;;
  x86_64)
    jdk_url="https://download.bell-sw.com/java/21.0.3+10/bellsoft-jdk21.0.3+10-linux-amd64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture: $arch"
    exit 1
    ;;
esac

if [[ -z "$java_path" || "$($java_path -version 2>&1 | grep -oP 'version \"\K\d+')" != "21" ]]; then
  echo "Unable to find Java 21 in classpath"
  java_path="$jdk_dir/bin/java"
  if [ -x "$java_path" ]; then
    echo "Java is installed at path $java_path"
  else
    echo "Java not installed. Installing..."

    wget -O /tmp/jre.tar.gz "$jdk_url"
    sudo mkdir -p "$jdk_dir"
    sudo tar xzf /tmp/jre.tar.gz --strip-components=1 -C "$jdk_dir"
    sudo ln -sf "$jdk_dir/bin/java" /usr/bin/java
    rm -f /tmp/jre.tar.gz

    echo "Java 21 has been installed to $jdk_dir"
  fi
else
  echo "Found Java 21 in classpath"
fi

echo "Java path: $java_path"

# Define the file name and path
launcher="$root_path/homio-launcher.jar"

# Check if the file exists locally
if [[ ! -f "$launcher" ]]; then
    echo "$launcher does not exist locally. Downloading from GitHub..."

    # Download the file from GitHub
    wget -O "$launcher" 'https://github.com/homiodev/static-files/raw/master/homio-launcher.jar'

    echo "File 'homio-launcher.jar' downloaded successfully."
fi

update_application() {
    if [[ -f "$root_path/homio-app.zip" ]]; then
        if [[ -f "$root_path/homio-app.jar" ]]; then
            echo "Backup $root_path/homio-app.jar to $root_path/homio-app.jar_backup"
            cp "$root_path/homio-app.jar" "$root_path/homio-app.jar_backup"
        fi

        echo "Extracting $root_path/homio-app.zip"
        if unzip -o "$root_path/homio-app.zip" -d "$root_path"; then
            echo "Homio ZIP file extracted successfully."
            echo "Remove archive $root_path/homio-app.zip"
            rm -f "$root_path/homio-app.zip"
        else
            echo "Failed to extract Homio ZIP file"
            if [[ -f "$root_path/homio-app.jar_backup" ]]; then
                echo "Recovering backup from $root_path/homio-app.jar_backup"
                mv "$root_path/homio-app.jar_backup" "$root_path/homio-app.jar"
            else
              echo "Remove archive $root_path/homio-app.zip"
              rm -f "$root_path/homio-app.zip"
            fi
        fi
    else
      if [[ -f "$root_path/homio-app.jar_backup" ]]; then
         echo "Recovering homio-app.jar backup"
         mv "$root_path/homio-app.jar_backup" "$root_path/homio-app.jar"
      fi
    fi
}

update_application

if [[ -f "$root_path/homio-app.jar" ]]; then
    app="homio-app.jar"
else
    app="homio-launcher.jar"
fi

echo "Run $java_path -jar $root_path/$app"
$sudo "$java_path" -jar "$root_path/$app"

echo "Restarting Homio"
sleep 1
exec "$0"
