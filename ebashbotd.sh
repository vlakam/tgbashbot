#!/bin/bash

token=''
api_url="https://api.telegram.org"
file="/tmp/ebashbotd"
host=''
pic_path='image_serve'
pic_name='image.png'
clarifai_key=''

start_bot() {
	./ebashbot.sh "$api_url" "$token" "$host" "$pic_path" "$pic_name" "$clarifai_key"
}

[[ "$1" != "slave" ]] && {
	echo "$$" > "$file"
	./ebashbotd.sh slave &
	start_bot &
}

while true; do
	[[ "$(cat "$file")" == "$$" ]] && {
		ping -c1 $(echo "$tele_url" | cut -d '/' -f 3) && {
			(( "$(curl -s "$tele_url/getUpdates" | jq -r ".result | length")" >= 10 )) && {
				pkill ebashbot.sh
				start_bot &
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