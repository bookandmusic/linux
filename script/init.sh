#!/usr/bin/env bash

# Define proxy URLs and versions for various tools
GITHUB_PROXY="https://mirror.ghproxy.com/"
HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
NVM_INSTALL_VERSION="0.39.7"
NODE_VERSION="20.12.0"
NODE_PROXY="https://mirrors.ustc.edu.cn/node/"
NPM_PROXY="https://registry.npmmirror.com"
GO_VERSION="1.22.3"
GO_PROXY="http://mirrors.ustc.edu.cn/golang/"
GO_MOD_PROXY="https://goproxy.cn"
PYTHON_PROXY="https://registry.npmmirror.com/-/binary/python"
PYTHON_VERSION="3.12.0"
PYPI_PROXY="https://mirrors.ustc.edu.cn/pypi/web/simple"
DATE=$(date +%Y%m%d%H%M%S)
LOG_FILE="env_init_${DATE}.log"

# Function to print informational messages
info() {
    echo -e "\e[1;32m$*\e[0m"
}

# Function to print warning messages
warning() {
    echo -e "\e[1;33m$*\e[0m"
}

# Function to print error messages and exit
error() {
    echo -e "\e[1;31m$*\e[0m"
    exit 1
}

# Function to run a command and exit on failure
run_cmd() {
    local cmd=$1
    info "CMD: $cmd"
    eval "$cmd"
    if [ $? -ne 0 ]; then
        exit 1
    fi
}

# Function to clone or update a Git repository
git_clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local depth_option="$3"

    if [ -d "${target_dir}/.git" ]; then
        echo "Repository already exists. Updating..."
        run_cmd "cd ${target_dir} && git pull"
    else
        echo "Cloning repository..."
        if [ -n "$depth_option" ]; then
            run_cmd "git clone --depth=1 $repo_url $target_dir"
        else
            run_cmd "git clone $repo_url $target_dir"
        fi
    fi
}

# Function to add a configuration block if it doesn't already exist in the files
add_config_if_not_exists() {
    local config_block="$1"
    shift
    local files=("$@")

    for file in "${files[@]}"; do
        if ! awk -v block="$config_block" 'BEGIN { found=0 } { data = data $0 ORS } END { if (index(data, block)) found=1; exit !found }' "$file"; then
            echo -e "$config_block" >> "$file"
            echo "Added configuration block to $file:"
            echo -e "$config_block"
        fi
    done
}

# Function to insert a configuration block before a pattern in the files
insert_config_before() {
    local pattern="$1"
    local insert_text="$2"
    shift
    local files=("$@")

    for file in "${files[@]}"; do
        if ! awk -v block="$insert_text\n$pattern" 'BEGIN { found=0 } { data = data $0 ORS } END { if (index(data, block)) found=1; exit !found }' "$file"; then
            if grep -q "$pattern" "$file"; then
                sed -i "\|$pattern|i\\$insert_text" "$file"
            else
                add_config_if_not_exists "\n$insert_text\n$pattern" "$file"
            fi
        fi
    done
}

# Function to detect the operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="Mac"
        SED_PREFIX="sed -i '' "
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        SED_PREFIX="sed -i "
        if [[ -f /etc/os-release ]]; then
            os=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        elif [[ -f /etc/issue ]]; then
            os=$(awk '{print $1; exit}' /etc/issue)
        fi

        case "$os" in
            Ubuntu*)
                OS="Ubuntu"
                ;;
            Debian*)
                OS="Debian"
                ;;
            CentOS*)
                OS="CentOS"
                ;;
            *)
                error "Unknown Linux distribution: ${os}."
                ;;
        esac
    else
        error "Unknown operating system."
    fi

    info "Detected OS: ${OS}"
}

# Function to detect the system architecture
detect_architecture() {
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        i686|i386)
            ARCH="amd32"
            ;;
        arm64)
            ARCH="arm64"
            ;;
        armv7*)
            ARCH="arm32"
            ;;
        aarch64*)
            ARCH="arm64"
            ;;
        *)
            error "Unknown architecture: $(uname -m)"
            ;;
    esac
    info "Detected architecture: ${ARCH}"
}

# Function to detect if the user is root
detect_user() {
    if [ "$(id -u)" -eq 0 ]; then
        COMMAND_PREX=""  # root user
    else
        COMMAND_PREX="sudo "  # non-root user
    fi
    info "Detected user: $(whoami)"
}

# Function to install required packages
pre_start() {
    info "Installing required packages..."
    if [[ ${OS} == "Mac" ]]; then
        info "Running xcode-select --install"
        xcode-select --install &>/dev/null
    elif [[ ${OS} == "CentOS" ]]; then
        run_cmd "${COMMAND_PREX}yum makecache && ${COMMAND_PREX}yum install -y git curl wget zsh vim"
    elif [[ ${OS} == "Ubuntu" ]]; then
        run_cmd "${COMMAND_PREX}sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list &&
                 ${COMMAND_PREX}apt update &&
                 ${COMMAND_PREX}apt install -y sshpass ca-certificates git curl wget zsh vim"
    elif [[ ${OS} == "Debian" ]]; then
        run_cmd "${COMMAND_PREX}sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list &&
                 ${COMMAND_PREX}apt update &&
                 ${COMMAND_PREX}apt install -y sshpass ca-certificates git curl wget zsh vim"
    fi
    info "Installed required packages"
}

# Function to clear unnecessary files after installation
final_clear() {
    info "Cleaning up..."
    if [[ ${OS} == "Debian" || ${OS} == "Ubuntu" ]]; then
        run_cmd "${COMMAND_PREX}apt-get clean && ${COMMAND_PREX}apt-get autoclean &&
                 ${COMMAND_PREX}rm -rf /var/lib/apt/lists/* &&
                 ${COMMAND_PREX}rm -rf /src/*.deb"
    elif [[ ${OS} == "CentOS" ]]; then
        run_cmd "${COMMAND_PREX}yum clean all"
    elif [[ ${OS} == "Mac" ]]; then
        run_cmd "brew cleanup"
    fi
    info "Cleanup complete"
}

# Function to set the local timezone
config_localtime() {
    if [ ! -f "/etc/localtime" ]; then
        info "Setting localtime to Asia/Shanghai"
        run_cmd "${COMMAND_PREX}ln -svf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
    fi
}

# Function to install vimrc
install_vimrc() {
    info "Installing vimrc..."

    git_clone_or_update "${GITHUB_PROXY}https://github.com/amix/vimrc.git" "$HOME/.vim_runtime" "--depth=1"
    run_cmd "sh $HOME/.vim_runtime/install_awesome_vimrc.sh"

    info "vimrc installed"
}

# Function to install Oh My Zsh
install_ohmyzsh() {
    info "Installing Oh My Zsh..."

    git_clone_or_update "${GITHUB_PROXY}https://github.com/ohmyzsh/ohmyzsh.git" "$HOME/.oh-my-zsh"
    git_clone_or_update "${GITHUB_PROXY}https://github.com/zsh-users/zsh-autosuggestions.git" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    git_clone_or_update "${GITHUB_PROXY}https://github.com/zsh-users/zsh-syntax-highlighting.git" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

    if [ ! -e "$HOME/.zshrc" ]; then
        run_cmd "cp $HOME/.oh-my-zsh/templates/zshrc.zsh-template $HOME/.zshrc"
    fi

    run_cmd "${SED_PREFIX}'s@plugins=(git)@plugins=(sudo git zsh-autosuggestions zsh-syntax-highlighting)@g' $HOME/.zshrc"

    info "Oh My Zsh installed"
}

# Function to install NVM
install_nvm() {
    info "Installing NVM..."

    curl -o- "${GITHUB_PROXY}https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_INSTALL_VERSION}/install.sh" | bash

    local nvm_config=$(cat <<EOF
export NVM_NODEJS_ORG_MIRROR=${NODE_PROXY}
export NVM_IOJS_ORG_MIRROR=${NODE_PROXY}
export PATH=\$NVM_DIR/versions/node/\$NODE_VERSION/bin:\$PATH
EOF
)

    add_config_if_not_exists "$nvm_config" "$HOME/.zshrc" "$HOME/.bashrc"

    export NVM_NODEJS_ORG_MIRROR="${NODE_PROXY}"
    export NVM_IOJS_ORG_MIRROR="${NODE_PROXY}"
    [ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"

    info "NVM installed"
}

# Function to install Node.js and npm
install_node() {
    info "Installing Node.js and npm..."

    nvm install ${NODE_VERSION}
    nvm use ${NODE_VERSION}
    nvm alias default ${NODE_VERSION}

    run_cmd "npm config set registry ${NPM_PROXY}"
    run_cmd "npm i -g yarn"

    info "Node.js and npm installed"
}

# Function to install Go
install_go() {
    info "Installing Go..."

    local go_filename="go${GO_VERSION}.linux-${ARCH}.tar.gz"
    local go_download_url="${GO_PROXY}${go_filename}"

    run_cmd "wget -q ${go_download_url} -O /tmp/${go_filename}"
    run_cmd "${COMMAND_PREX}tar -C /usr/local -xzf /tmp/${go_filename}"

    local go_config=$(cat <<EOF
export GOROOT=/usr/local/go
export GOPROXY=${GO_MOD_PROXY}
export PATH=\$GOROOT/bin:\$PATH
EOF
)

    add_config_if_not_exists "$go_config" "$HOME/.zshrc" "$HOME/.bashrc"

    info "Go installed"
}

# Function to install Python
install_python() {
    info "Installing Python..."

    local py_filename="Python-${PYTHON_VERSION}.tgz"
    local py_download_url="${PYTHON_PROXY}/Python-${PYTHON_VERSION}.tgz"

    run_cmd "wget -q ${py_download_url} -O /tmp/${py_filename}"
    run_cmd "tar -xzf /tmp/${py_filename} -C /tmp"
    run_cmd "cd /tmp/Python-${PYTHON_VERSION} && ./configure --enable-optimizations && make -j4"
    run_cmd "${COMMAND_PREX}make altinstall"

    run_cmd "pip${PYTHON_VERSION%.*} config set global.index-url ${PYPI_PROXY}"

    local python_config=$(cat <<EOF
export PATH=/usr/local/bin/python${PYTHON_VERSION%.*}:\$PATH
EOF
)

    add_config_if_not_exists "$python_config" "$HOME/.zshrc" "$HOME/.bashrc"

    info "Python installed"
}

# Function to install Homebrew
install_homebrew() {
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."

        /bin/bash -c "$(curl -fsSL ${GITHUB_PROXY}https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

        run_cmd "brew tap --custom-remote --force-auto-update homebrew/core ${HOMEBREW_CORE_GIT_REMOTE}"
        run_cmd "brew update"

        local brew_config=$(cat <<EOF
export HOMEBREW_BREW_GIT_REMOTE=${HOMEBREW_BREW_GIT_REMOTE}
export HOMEBREW_CORE_GIT_REMOTE=${HOMEBREW_CORE_GIT_REMOTE}
export HOMEBREW_BOTTLE_DOMAIN=${HOMEBREW_BOTTLE_DOMAIN}
export HOMEBREW_API_DOMAIN=${HOMEBREW_API_DOMAIN}
EOF
)

        add_config_if_not_exists "$brew_config" "$HOME/.zshrc" "$HOME/.bashrc"
        info "Homebrew installed"
    fi
}

# Main script logic
main() {
    detect_os
    detect_architecture
    detect_user
    pre_start
    config_localtime
    install_vimrc
    install_ohmyzsh
    install_homebrew
    install_nvm
    install_node
    install_go
    install_python
    final_clear
}

main | tee -a "$LOG_FILE"
