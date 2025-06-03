#!/bin/bash

# --- Initial Setup on Jetson Orin Nano ---

echo "Starting initial setup for Jetson Orin Nano..."

# Ensure we're in the user's home directory or a predictable location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR" || { echo "Error: Could not change to script directory. Exiting."; exit 1; }

# 1. git clone https://github.com/dusty-nv/jetson-containers
echo "Cloning jetson-containers repository..."
if [ ! -d "jetson-containers" ]; then
    git clone https://github.com/dusty-nv/jetson-containers
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone jetson-containers. Exiting."
        exit 1
    fi
    echo "jetson-containers cloned successfully."
else
    echo "jetson-containers directory already exists. Skipping clone."
    # Optional: uncomment the following lines if you want to ensure jetson-containers is always up-to-date
    # echo "Updating jetson-containers..."
    # pushd jetson-containers && git pull && popd
fi

# 2. bash jetson-containers/install.sh
echo "Running jetson-containers install.sh..."
pushd jetson-containers
bash install.sh
if [ $? -ne 0 ]; then
    echo "Error: Failed to run install.sh. Exiting."
    popd
    exit 1
fi
popd
echo "jetson-containers install.sh completed."

# Function to clean up temporary container and directory on exit or error
cleanup() {
    echo "Performing cleanup..."
    # Check if the temporary container exists (running or stopped)
    if docker ps -a --format '{{.Names}}' | grep -q "temp_l4t_pytorch"; then
        echo "Stopping and removing temporary l4t-pytorch container..."
        # Use || true to prevent script exit if stop/rm fails (e.g., already stopped/removed)
        docker stop temp_l4t_pytorch &>/dev/null || true
        docker rm temp_l4t_pytorch &>/dev/null || true
        echo "Temporary container cleaned up."
    else
        echo "Temporary l4t-pytorch container not found, skipping removal."
    fi

    # Clean up temporary build directory
    if [ -d "build_pokai_vision" ]; then
        echo "Cleaning up temporary build directory..."
        rm -rf build_pokai_vision
        echo "Temporary build directory removed."
    fi
}

# Trap signals for robust cleanup
trap cleanup EXIT      # Run cleanup on script exit (success or failure)
trap "cleanup; exit 1" INT TERM # Run cleanup and exit on Ctrl+C or kill

# 3. jetson-containers run $(autotag l4t-pytorch)
# This step will pull the l4t-pytorch container and keep it running in the background.
echo "Running l4t-pytorch container in detached mode..."

# First, ensure no old 'temp_l4t_pytorch' container is lingering from a previous failed run
if docker ps -a --format '{{.Names}}' | grep -q "temp_l4t_pytorch"; then
    echo "Found existing 'temp_l4t_pytorch' container. Attempting to remove it first."
    docker stop temp_l4t_pytorch &>/dev/null || true
    docker rm temp_l4t_pytorch &>/dev/null || true
fi

# Run the container
jetson-containers run --detach --name temp_l4t_pytorch $(autotag l4t-pytorch)
if [ $? -ne 0 ]; then
    echo "Error: Failed to run l4t-pytorch container. Check previous errors for container startup issues."
    exit 1 # Cleanup trap will handle removal
fi
echo "l4t-pytorch container is running or started successfully."

# Give Docker a moment to ensure the container is actually running
sleep 5

# Verify the container is truly running before proceeding
if ! docker ps --format '{{.Names}}' | grep -q "temp_l4t_pytorch"; then
    echo "Error: l4t-pytorch container 'temp_l4t_pytorch' did not stay running. Check 'docker logs temp_l4t_pytorch' for details."
    exit 1 # Cleanup trap will handle removal
fi

echo "Initial setup completed. Now proceeding to build the custom Docker image."

---

## Build Custom Docker Image with Chromium (APT version)

# Create a temporary directory for Dockerfile and context
mkdir -p build_pokai_vision
cd build_pokai_vision
if [ $? -ne 0 ]; then
    echo "Error: Could not create/enter build_pokai_vision directory. Exiting."
    exit 1
fi

# Create the Dockerfile with the fix for ARG BASE_IMAGE and Chromium installation
cat <<EOF > Dockerfile
# Use the l4t-pytorch image as base
# Provide a default value for BASE_IMAGE to satisfy Docker's build checks.
# This default will be overridden by --build-arg in the script.
ARG BASE_IMAGE="nvcr.io/nvidia/l4t-pytorch:r36.2.0-pth2.2-py3"

FROM \$BASE_IMAGE

# Install OS-level dependencies first
RUN apt-get update && apt-get install -y --no-install-recommends \\
    chromium-browser \\
    chromium-browser-l10n \\
    chromium-codecs-ffmpeg \\
    libgl1-mesa-glx \\
    libglib2.0-0 \\
    libxcomposite1 \\
    libxdamage1 \\
    libxext6 \\
    libxfixes3 \\
    libxrandr2 \\
    libxrender1 \\
    libxi6 \\
    libnss3 \\
    libasound2 \\
    libgbm1 \\
    # Clean up apt lists to reduce image size
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies:
# 1. Upgrade pip and setuptools
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools

# 2. Install ultralytics
RUN python3 -m pip install --no-cache-dir ultralytics

# 3. Install flask with --ignore-installed blinker
RUN python3 -m pip install --no-cache-dir flask --ignore-installed blinker

# 4. Install openpyxl
RUN python3 -m pip install --no-cache-dir openpyxl

# 5. Install lap
RUN python3 -m pip install --no-cache-dir "lap>=0.5.12"

# Clone the P-Y_V8 repository into the working directory /app
RUN git clone https://github.com/HxSx79/P-Y_V8.git

# Set the default command to bash, allowing the 'jetson-containers run' command to execute custom logic.
CMD ["bash"]
EOF

echo "Dockerfile created for pokai_vision."

# Get the full image name for l4t-pytorch using autotag
L4T_PYTORCH_IMAGE=$(jetson-containers autotag l4t-pytorch)
if [ -z "$L4T_PYTORCH_IMAGE" ]; then
    echo "Error: Failed to determine l4t-pytorch image using autotag. Exiting."
    exit 1
fi
echo "Determined base image: ${L4T_PYTORCH_IMAGE}"

# Build the new image with --no-cache to force a fresh build
echo "Building pokai_vision:latest Docker image from ${L4T_PYTORCH_IMAGE} with --no-cache..."
docker build --no-cache -t pokai_vision:latest --build-arg BASE_IMAGE="${L4T_PYTORCH_IMAGE}" .
if [ $? -ne 0 ]; then
    echo "Error: Failed to build pokai_vision:latest image. Check build logs above for details."
    echo "If you see 'IncompleteRead' or network errors, it might be a temporary network issue."
    echo "Try running the script again. If it persists, check your Jetson's internet connection."
    exit 1 # Cleanup trap will handle removal of container and directory
fi
echo "pokai_vision:latest image built successfully."

echo "Setup and custom image creation complete!"
echo "You can now run your custom image with the following command:"
echo "jetson-containers run $(autotag pokai_vision) bash -c "cd /app/P-Y_V8 && python3 app.py""