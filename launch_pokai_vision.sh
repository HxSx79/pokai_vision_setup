#!/bin/bash

# Script to launch the Pokai Vision application inside its Docker container
# and then open Chromium (with GPU acceleration disabled) to its web interface.

echo "------------------------------------------"
echo "  Attempting to launch Pokai Vision...  "
echo "------------------------------------------"

# Check if autotag command is available
if ! command -v autotag &> /dev/null; then
    echo "Error: 'autotag' command not found. Please ensure jetson-containers is correctly installed and 'autotag' is in your PATH."
    echo "You might need to run the install.sh script from the jetson-containers directory."
    read -p "Press Enter to exit."
    exit 1
fi

# Check if jetson-containers command is available
if ! command -v jetson-containers &> /dev/null; then
    echo "Error: 'jetson-containers' command not found. Please ensure jetson-containers is correctly installed and is in your PATH."
    echo "You might need to run the install.sh script from the jetson-containers directory."
    read -p "Press Enter to exit."
    exit 1
fi

# Determine the full image tag using autotag
echo "Determining image tag for 'pokai_vision'..."
POKAI_IMAGE_TAG=$(autotag pokai_vision)

if [ -z "$POKAI_IMAGE_TAG" ]; then
    echo "Error: Could not determine image tag for 'pokai_vision' using autotag."
    echo "Ensure 'autotag' can find the 'pokai_vision' image (it might need to be built or pulled)."
    read -p "Press Enter to exit."
    exit 1
fi

echo "Found image: $POKAI_IMAGE_TAG"
echo "Preparing to launch application..."
echo ""

# Define the command to run your application inside the container
APP_COMMAND_INSIDE_CONTAINER="cd /app/P-Y_V8 && python3 app.py"

echo "Launching Pokai Vision server in the background..."
echo "Server command: jetson-containers run \"$POKAI_IMAGE_TAG\" bash -c \"$APP_COMMAND_INSIDE_CONTAINER\""
echo "------------------------------------------"

# Launch the jetson-containers command (which runs your app.py server) in the background
jetson-containers run "$POKAI_IMAGE_TAG" bash -c "$APP_COMMAND_INSIDE_CONTAINER" &
SERVER_JOB_PID=$! # Get the Process ID of the backgrounded jetson-containers job

echo ""
echo "Pokai Vision server should be starting in the background (Job PID: $SERVER_JOB_PID)."
echo "Please allow a few moments for the server to fully initialize."
echo "(Note: You might see a 'the input device is not a TTY' warning from the backgrounded server; this is usually okay.)"
echo ""

# Wait for a few seconds to give the server time to start up.
# Adjust this duration if your server takes longer or shorter to be ready.
SLEEP_DURATION=10
echo "Waiting for $SLEEP_DURATION seconds before opening Chromium..."

# Simple countdown visual
COUNT=$SLEEP_DURATION
while [ $COUNT -gt 0 ]; do
    echo -n "$COUNT... "
    sleep 1
    COUNT=$(($COUNT - 1))
done
echo "Done waiting."
echo ""

# Check if chromium-browser (apt version) is available
if ! command -v chromium-browser &> /dev/null; then
    echo "Error: 'chromium-browser' command not found. Please ensure it is installed (e.g., via 'sudo apt install chromium-browser')."
    echo "The Pokai Vision server might still be running in the background (Job PID: $SERVER_JOB_PID)."
    echo "You can try to manually open a browser to http://localhost:8080 if the server started successfully."
    read -p "Press Enter to exit this script."
    exit 1
fi

# Define the target URL for Chromium
TARGET_URL="http://localhost:8080"

echo "Opening Chromium at $TARGET_URL (with GPU acceleration disabled for stability)..."
# Launch Chromium with --disable-gpu flag and also send it to the background
chromium-browser --disable-gpu "$TARGET_URL" &

echo "------------------------------------------"
echo "Chromium has been launched to connect to the Pokai Vision server."
echo "The Pokai Vision server (Job PID: $SERVER_JOB_PID) is intended to be running in the background."
echo ""
echo "You can typically close this terminal window now;"
echo "the server (inside Docker) and Chromium will continue to run independently."
echo ""
echo "To stop the Pokai Vision server, you will usually need to:"
echo "1. Find the Docker container: 'docker ps' (Look for an image like '$POKAI_IMAGE_TAG' or a name like 'jetson_container_...')"
echo "2. Stop the container: 'docker stop <container_id_or_name>'"
echo "------------------------------------------"

exit 0