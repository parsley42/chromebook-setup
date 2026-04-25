#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


prompt_upgrade() {
  local name=$1
  local current=$2
  local latest=$3
  
  if [ -z "$current" ]; then
    echo "Installing $name ($latest)..."
    return 0 # Proceed with install
  fi
  
  if [ "$current" != "$latest" ]; then
    read -p "$name is installed ($current), but a newer version ($latest) is available. Do you want to upgrade? [y/N] " response
    case "$response" in
      [yY][eE][sS]|[yY]) 
        echo "Upgrading $name..."
        return 0 
        ;;
      *) 
        echo "Skipping $name upgrade."
        return 1 
        ;;
    esac
  fi
  
  echo "$name is already at the latest version ($current)."
  return 1
}

if ! which unzip > /dev/null
then
  sudo apt update
  sudo apt install -y unzip
fi


if [ ! -f "$HOME/.config/systemd/user/ssh-agent.service" ]
then
  mkdir -p $HOME/.config/systemd/user
  cat << "EOF" > $HOME/.config/systemd/user/ssh-agent.service
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
EOF
  systemctl --user enable ssh-agent
fi

# Set up SSH config for automatic key loading
mkdir -p -m 700 $HOME/.ssh
if [ ! -f $HOME/.ssh/config ] || ! grep -q '# MANAGED BY Chromebook setup.sh' $HOME/.ssh/config
then
  touch $HOME/.ssh/config
  chmod 600 $HOME/.ssh/config
  cat <<EOF >> $HOME/.ssh/config

# MANAGED BY Chromebook setup.sh
Host *
  AddKeysToAgent yes
EOF
fi

# Set up Git config if missing
if [ ! -f $HOME/.gitconfig ]
then
  echo "Git configuration not found. Let's set it up."
  read -p "Enter your Git user.name: " git_name
  read -p "Enter your Git user.email: " git_email
  
  if [ -n "$git_name" ]; then
    git config --global user.name "$git_name"
  fi
  
  if [ -n "$git_email" ]; then
    git config --global user.email "$git_email"
  fi
  
  git config --global init.defaultBranch main
fi

if ! which docker > /dev/null
then
  sudo apt update
  sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo gpasswd -a $USER docker
fi

if ! which code > /dev/null
then
  sudo apt-get install -y wget gpg apt-transport-https
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
  sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
  rm -f microsoft.gpg
  cat <<EOF | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  sudo apt update
  sudo apt install -y code
fi

if ! which google-chrome > /dev/null
then
  DEB_PATH="/tmp/google-chrome-stable_current_amd64.deb"
  wget -O "$DEB_PATH" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo apt install -y "$DEB_PATH"
  rm -f "$DEB_PATH"
fi

if ! which antigravity > /dev/null
then
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
  echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
    sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
  sudo apt update
  sudo apt install -y antigravity
fi

if [ ! -e $HOME/.git-completion.bash ]
then
        curl -o $HOME/.git-completion.bash https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash
fi

if [ ! -e $HOME/.git-prompt.sh ]
then
        curl -o $HOME/.git-prompt.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh
fi


if ! grep -q '# MANAGED BY Chromebook bootstrap.sh' $HOME/.bashrc
then
        cat <<EOF >> $HOME/.bashrc

# MANAGED BY Chromebook bootstrap.sh
source "$DIR/chromebookrc"
EOF
fi

# Go Installation
GO_LATEST=$(curl -s "https://go.dev/VERSION?m=text" | head -n1)
GO_CURRENT=$(go version 2>/dev/null | awk '{print $3}')
if prompt_upgrade "Go" "$GO_CURRENT" "$GO_LATEST"; then
  GO_TARBALL="${GO_LATEST}.linux-amd64.tar.gz"
  curl -LO "https://go.dev/dl/$GO_TARBALL"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$GO_TARBALL"
  rm "$GO_TARBALL"
fi

# fnm Installation
FNM_LATEST=$(git ls-remote --tags https://github.com/Schniz/fnm.git | awk -F/ '{print $3}' | grep '^v' | sort -V | tail -n1)
FNM_CURRENT=$(fnm --version 2>/dev/null | awk '{print $2}')
if [[ "$FNM_CURRENT" != v* ]] && [ -n "$FNM_CURRENT" ]; then
  FNM_CURRENT="v$FNM_CURRENT"
fi
if prompt_upgrade "fnm" "$FNM_CURRENT" "$FNM_LATEST"; then
  curl -LO "https://github.com/Schniz/fnm/releases/download/${FNM_LATEST}/fnm-linux.zip"
  unzip fnm-linux.zip
  sudo mv fnm /usr/local/bin/
  sudo chmod +x /usr/local/bin/fnm
  rm fnm-linux.zip
fi

# Node.js Installation
# Ensure fnm is available for this script since we just might have installed it
export PATH=$PATH:/usr/local/bin
eval "$(fnm env)"
NODE_LATEST=$(fnm ls-remote | tail -n 1)
NODE_CURRENT=$(node -v 2>/dev/null || echo "")
if prompt_upgrade "Node.js" "$NODE_CURRENT" "$NODE_LATEST"; then
  fnm install "$NODE_LATEST"
  fnm default "$NODE_LATEST"
fi

# Codex Installation
# Safe to run every time to ensure it is installed and updated
npm i -g @openai/codex@latest

# Fix Wayland Fractional Scaling bug for Electron apps in .desktop files
for app in code antigravity; do
  for desktop_file in /usr/share/applications/${app}*.desktop; do
    if [ -f "$desktop_file" ]; then
      if ! grep -q "WaylandFractionalScaleV1" "$desktop_file"; then
        echo "Patching $desktop_file for Wayland fractional scaling..."
        sudo sed -i 's/^\(Exec=[^ ]*\)/\1 --disable-features=WaylandFractionalScaleV1/' "$desktop_file"
      fi
    fi
  done
done
