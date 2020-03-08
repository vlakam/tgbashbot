# eBashBot

Telegram bot writen in Bash, which implements grep, sed, cut and some other features.

# Prerequisites
    jq, sqlite3, curl

# Usage

1. Make clarifai account
2. Make a directory and make it accessible from outside using any web server
3. Put your bot and clarifai token into ebashbotd.sh
4. Put directory path from step 2 into "pic_path" variable in ebashbotd.sh
5. Put link to directory into "host" variable in ebashbotd.sh (host="<http/https>://<ip/dns>:<port>")
6. Use any scheduler to periodically trigger clean_bd.sh, which will clean your alias database from alias that were not used for over 3 month. I use crontab for this:
    0 * * * * bash -c "/root/ebashbot/clean_bd.sh"