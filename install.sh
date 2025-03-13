#!/bin/bash
set -e

echo "DEBUG: Starting environment setup script..."

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "DEBUG: This script must be run as root. Exiting."
  exit 1
fi

# Check OS version (Ubuntu 22.04 LTS)
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$NAME" != "Ubuntu" ] || [[ "$VERSION_ID" != "22.04"* ]]; then
    echo "DEBUG: This script is intended for Ubuntu 22.04 LTS. Detected: $NAME $VERSION_ID"
    exit 1
  fi
  echo "DEBUG: Confirmed Ubuntu 22.04 LTS environment."
else
  echo "DEBUG: Cannot determine OS version. Exiting."
  exit 1
fi

# Update package list
echo "DEBUG: Updating package list..."
apt update

# Install GCC-11 and G++-11
echo "DEBUG: Installing gcc-11 and g++-11..."
apt install -y gcc-11 g++-11

# Verify gcc-11 version
gcc_version=$(gcc-11 --version | head -n 1)
echo "DEBUG: Installed gcc-11 version: $gcc_version"

# -------------------------------
# Install Sublime Text
# -------------------------------
echo "DEBUG: Setting up Sublime Text repository..."
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | apt-key add -
echo "DEBUG: Adding Sublime Text APT repository..."
apt-add-repository "deb https://download.sublimetext.com/ apt/stable/"
echo "DEBUG: Installing Sublime Text..."
apt update && apt install -y sublime-text

# -------------------------------
# Install Visual Studio Code
# -------------------------------
echo "DEBUG: Setting up Visual Studio Code repository..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
rm microsoft.gpg
echo "DEBUG: Adding VS Code repository..."
sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
echo "DEBUG: Installing Visual Studio Code..."
apt update && apt install -y code

# Install C/C++ extension for VS Code (attempt to force version 1.24, if possible)
echo "DEBUG: Installing C/C++ extension for VS Code..."
if [ -n "$SUDO_USER" ]; then
  sudo -u "$SUDO_USER" code --install-extension ms-vscode.cpptools --force
else
  echo "DEBUG: SUDO_USER not defined; skipping VS Code extension installation."
fi

# -------------------------------
# Install Firefox
# -------------------------------
echo "DEBUG: Installing Firefox..."
apt install -y firefox

# -------------------------------
# Create wrapper scripts in /usr/local/bin to override default gcc and g++ commands
# -------------------------------
echo "DEBUG: Creating gcc wrapper script in /usr/local/bin/gcc..."
cat << 'EOF' > /usr/local/bin/gcc
#!/bin/bash
echo "DEBUG: Overriding gcc command with default C flags."
if [ "$#" -lt 1 ]; then
  echo "DEBUG: No source file provided."
  exit 1
fi
src="$1"
echo "DEBUG: Compiling $src using gcc default flags."
exec /usr/bin/gcc-11 -DEVAL -std=c11 -O2 -pipe -static -s -o outputFile "$src" -lm
EOF
chmod +x /usr/local/bin/gcc

echo "DEBUG: Creating g++ wrapper script in /usr/local/bin/g++..."
cat << 'EOF' > /usr/local/bin/g++
#!/bin/bash
echo "DEBUG: Overriding g++ command with default C++ flags."
if [ "$#" -lt 1 ]; then
  echo "DEBUG: No source file provided."
  exit 1
fi
src="$1"
echo "DEBUG: Compiling $src using g++ default flags."
exec /usr/bin/g++-11 -DEVAL -std=c++17 -O2 -pipe -static -s -o outputFile "$src"
EOF
chmod +x /usr/local/bin/g++

# -------------------------------
# Create a build script that selects the compiler based on file extension.
# -------------------------------
echo "DEBUG: Creating build script in /usr/local/bin/build..."
cat << 'EOF' > /usr/local/bin/build
#!/bin/bash
echo "DEBUG: Starting build process..."
if [ "$#" -eq 0 ]; then
  echo "DEBUG: No input file provided. Usage: build <source_file> [output_file]"
  exit 1
fi
src="$1"
out="${2:-outputFile}"
ext="${src##*.}"
if [ "$ext" = "c" ]; then
  echo "DEBUG: Detected C source file."
  /usr/bin/gcc-11 -DEVAL -std=c11 -O2 -pipe -static -s -o "$out" "$src" -lm
elif [ "$ext" = "cpp" ] || [ "$ext" = "cc" ] || [ "$ext" = "cxx" ]; then
  echo "DEBUG: Detected C++ source file."
  /usr/bin/g++-11 -DEVAL -std=c++17 -O2 -pipe -static -s -o "$out" "$src"
else
  echo "DEBUG: Unsupported file extension: $ext"
  exit 1
fi
echo "DEBUG: Build complete."
EOF
chmod +x /usr/local/bin/build

# -------------------------------
# Install and Configure GRUB for UEFI
# -------------------------------
echo "DEBUG: Installing GRUB for UEFI and os-prober..."
apt install -y grub-efi-amd64 os-prober

echo "DEBUG: Running os-prober to detect other operating systems (e.g., Windows)..."
os-prober

echo "DEBUG: Configuring GRUB for UEFI..."
# Enable os-prober
if grep -q "^GRUB_DISABLE_OS_PROBER=" /etc/default/grub; then
  sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
  echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

# Set GRUB timeout to 15 seconds
if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=15/' /etc/default/grub
else
  echo "GRUB_TIMEOUT=15" >> /etc/default/grub
fi

# Use saved default method so we can set a default entry
if grep -q "^GRUB_DEFAULT=" /etc/default/grub; then
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
else
  echo "GRUB_DEFAULT=saved" >> /etc/default/grub
fi

if ! grep -q "^GRUB_SAVEDEFAULT=" /etc/default/grub; then
  echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
fi

echo "DEBUG: Updating GRUB configuration..."
update-grub

echo "DEBUG: Attempting to set Windows Boot Manager as the default boot entry..."
# Extract the Windows Boot Manager menu entry from /boot/grub/grub.cfg.
WINDOWS_MENU=$(grep "menuentry 'Windows Boot Manager" /boot/grub/grub.cfg | head -n 1 | cut -d"'" -f2)
if [ -n "$WINDOWS_MENU" ]; then
  grub-set-default "$WINDOWS_MENU"
  echo "DEBUG: Set default boot entry to '$WINDOWS_MENU'."
else
  echo "DEBUG: Windows Boot Manager not found in grub.cfg; default remains Ubuntu."
fi

echo "DEBUG: Environment setup complete."
