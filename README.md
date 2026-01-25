### Prerequisites

1. **Install pipx (if not already installed):**
   
   Bazzite comes with Homebrew pre-installed, so you can use it to install pipx:
   ```bash
   brew install pipx
   pipx ensurepath
   ```
   
   > **Note:** You may need to restart your terminal or source your shell configuration after running `pipx ensurepath`.

2. **Install alga:**
   ```bash
   pipx install alga
   ```

3. **Pair with your TV:**
   ```bash
   # This will prompt you to accept the connection on your TV
   alga tv add <identifier> [TV_IP_or_hostname]
   ```
   
   > **Note:** If no hostname or IP is provided, alga will default to "lgwebostv" which should work if your TV is discoverable on your network.