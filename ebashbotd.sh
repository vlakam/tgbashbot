#!/bin/bash

token=''
tele_url="https://api.telegram.org/bot$token"
file="/tmp/ebashbotd"

[[ "$1" != "slave" ]] && {
	echo "$$" > "$file"
	./ebashbotd.sh slave &
	./ebashbot.sh "$tele_url" &
}

while true; do
	[[ "$(cat "$file")" == "$$" ]] && {
		ping -c1 $(echo "$tele_url" | cut -d '/' -f 3) && {
			(( "$(curl -s "$tele_url/getUpdates" | jq -r ".result | length")" >= 10 )) && {
				pkill ebashbot.sh
				./ebashbot.sh "$tele_url" &
			}
		}
		sleep 60
	} || {
		[[ $(ps aux | tr -s " " | cut -d " " -f 2 | grep -o "$(cat /tmp/ebashbotd)") ]] && {
			sleep 5
		} || {
                        echo "$$" > "$file"
                        ./ebashbotd.sh slave &
		}
	}
done