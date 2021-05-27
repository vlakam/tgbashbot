# eBashBot

Telegram bot writen in Bash, which implements grep, sed, cut and some other features.

# Prerequisites
    jq, sqlite3, curl

# Usage

1. Register clarifai account
2. Put your bot and clarifai token into ebashbotd.sh
3. (Optional) Use any scheduler to periodically trigger clean_bd.sh, which will clean your alias database from aliases that were not used for more then 3 month. I use crontab for this:

0 * * * * bash -c "<path_to_ebobot_directory>/clean_bd.sh"