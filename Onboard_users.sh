#!/bin/bash

# Define the log file path
LOGFILE="/var/log/user_onboarding_audit.log"

# Function to log actions with timestamp
log_action() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$timestamp - $message" | sudo tee -a "$LOGFILE" > /dev/null
}

# Define a regex pattern for valid usernames and group names
VALID_NAME_REGEX="^[a-zA-Z0-9._-]+$"

# Read users.csv, skipping the header
tail -n +2 users.csv | while IFS=',' read -r username groupname shell
do
  # Trim whitespace from fields
  username=$(echo "$username" | xargs)
  groupname=$(echo "$groupname" | xargs)
  shell=$(echo "$shell" | xargs)

  # Log the user entry being processed
  log_action "Processing entry: username='$username', groupname='$groupname', shell='$shell'"

  # Skip entry if any field is missing
  if [[ -z "$username" || -z "$groupname" || -z "$shell" ]]; then
    log_action "ERROR: Missing field(s) for entry: '$username', '$groupname', '$shell'. Skipping."
    continue
  fi

  # Validate username format
  if ! [[ "$username" =~ $VALID_NAME_REGEX ]]; then
    log_action "ERROR: Invalid characters in username '$username'. Skipping."
    continue
  fi

  # Validate group name format
  if ! [[ "$groupname" =~ $VALID_NAME_REGEX ]]; then
    log_action "ERROR: Invalid characters in groupname '$groupname'. Skipping."
    continue
  fi

  # Replace any slashes in groupname to make it valid
  groupname="${groupname//\//_}"

  # Check if shell exists and is executable, else skip user
  if [ ! -x "$shell" ]; then
    log_action "ERROR: Shell '$shell' does not exist or is not executable. Skipping user $username."
    continue
  fi

  # Create group if it doesn't already exist
  if ! getent group "$groupname" > /dev/null; then
    log_action "Group $groupname does not exist, creating group."
    if sudo groupadd "$groupname"; then
      log_action "Group $groupname created successfully."
    else
      log_action "ERROR: Failed to create group $groupname. Skipping user $username."
      continue
    fi
  fi

  # If user exists, update shell only if different; otherwise, create the user
  if id "$username" &>/dev/null; then
    current_shell=$(getent passwd "$username" | cut -d: -f7)
    if [ "$current_shell" != "$shell" ]; then
      log_action "User $username exists. Updating shell to $shell."
      if sudo usermod -s "$shell" "$username"; then
        log_action "Shell updated for $username."
      else
        log_action "ERROR: Failed to update shell for $username."
      fi
    else
      log_action "Shell for user $username already set to $shell. No change needed."
    fi
  else
    log_action "User $username does not exist. Creating user with shell $shell."
    if sudo useradd -m -s "$shell" "$username"; then
      log_action "User $username created."
    else
      log_action "ERROR: Failed to create user $username. Skipping."
      continue
    fi
  fi

  # Ensure user is added to the correct group
  if id -nG "$username" | grep -qw "$groupname"; then
    log_action "User $username already in group $groupname."
  else
    if sudo usermod -aG "$groupname" "$username"; then
      log_action "User $username added to group $groupname."
    else
      log_action "ERROR: Failed to add $username to group $groupname."
    fi
  fi

  # Setup or correct user's home directory
  homedir="/home/$username"
  if [ -d "$homedir" ]; then
    log_action "Home directory $homedir exists. Checking permissions."
    # Set correct permissions if needed
    if [ "$(stat -c "%a" "$homedir")" != "700" ]; then
      sudo chmod 700 "$homedir"
      log_action "Set permissions of $homedir to 700."
    fi
    # Correct ownership if needed
    if [ "$(stat -c "%U" "$homedir")" != "$username" ]; then
      sudo chown "$username:$groupname" "$homedir"
      log_action "Changed ownership of $homedir to $username:$groupname."
    fi
  else
    # Create and configure home directory if it doesn't exist
    log_action "Creating home directory $homedir."
    if sudo mkdir "$homedir" && sudo chown "$username:$groupname" "$homedir" && sudo chmod 700 "$homedir"; then
      log_action "Home directory $homedir created and configured."
    else
      log_action "ERROR: Failed to create home directory $homedir for $username."
    fi
  fi

  # Setup or validate project directory
  project_dir="/opt/projects/$username"
  if [ -d "$project_dir" ]; then
    log_action "Project directory $project_dir already exists."
  else
    log_action "Creating project directory $project_dir."
    if sudo mkdir -p "$project_dir" && sudo chown "$username:$groupname" "$project_dir" && sudo chmod 750 "$project_dir"; then
      log_action "Project directory $project_dir created and configured."
    else
      log_action "ERROR: Failed to create project directory $project_dir."
    fi
  fi

done

