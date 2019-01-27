#!/bin/bash

tele_url="$1"
last_id=0
[[ ! -f alias ]] && sqlite3 alias <<< 'create table alias(name varchar(10), user_id smallint, chat_id smallint, reply_id smallint, timestamp smallint);'

while true; do
	ping -c1 $(echo "$tele_url" | cut -d '/' -f 3) 2>&1 > /dev/null && {
		updates=$(curl -s "$tele_url/getUpdates" \
			--data-urlencode "offset=$(( $last_id + 1 ))" \
			--data-urlencode "timeout=60")
		updates_count=$(echo "$updates" | jq -r ".result | length")
		last_id=$(echo "$updates" | jq -r ".result[$(( "$updates_count" - 1 ))].update_id")
		for ((i=0; i<"$updates_count"; i++)); {
			{
			date +%F-%T >> ebash.log
			echo "$updates" | jq ".result[$i]" >> ebash.log
			chat_id="$(echo "$updates" | jq ".result[$i].message.chat.id")"
			reply_id="$(echo "$updates" | jq ".result[$i].message.reply_to_message.message_id")"
			reply_text="$(echo "$updates" | jq ".result[$i].message.reply_to_message.text" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
			[[ $reply_text == 'null' ]] && reply_text="$(echo "$updates" | jq ".result[$i].message.reply_to_message.caption" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
			reply_text="$(echo "$reply_text" | sed --sandbox 's#\\\\#\\#g;s#\\\"#"#g;s/^"//;s/"$//')"
			message_text="$(echo "$updates" | jq ".result[$i].message.text" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
			[[ $message_text == 'null' ]] && message_text="$(echo "$updates" | jq ".result[$i].message.caption" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
			case $message_text in
				's/'*|'s#'*|'y/'*)
					[[ "$reply_id" != 'null' ]] &&
					curl -s "$tele_url/sendMessage" \
						--data-urlencode "chat_id=$chat_id" \
						--data-urlencode "reply_to_message_id=$reply_id" \
						--data-urlencode "text=$(echo -e "$reply_text" | timeout 0.1s sed -E --sandbox "$message_text")"
				;;
				'grep '*|'cut '*)
					[[ "$reply_id" != 'null' ]] && {
						message_text="$(echo "$message_text" | tr -d '(){}`<>;|&$')"
						[[ ! "$(echo "$message_text" | grep -i 'recurs\|--help\|-.*r')" ]] && {
							for f in ${message_text//=/ }; {
								[[ -e "$f" ]] && file_found=1 && break
							}
							[[ "$file_found" != '1' ]] && {
								curl -s "$tele_url/sendMessage" \
									--data-urlencode "chat_id=$chat_id" \
									--data-urlencode "reply_to_message_id=$reply_id" \
									--data-urlencode "text=$(echo -e "$reply_text" | eval "$message_text")"
							} || file_found=0
						}
					}
				;;
				'alias '*)
					message_text="${message_text//;}"
					message_id="$(echo "$updates" | jq ".result[$i].message.message_id")"
					case $message_text in
						'alias -a '*)
							[[ "$reply_id" != 'null' ]] && {
								message_text="${message_text:9}"
								(( $(echo $message_text | wc -m) < 14 )) && {
									[[ $message_text =~ ^[[:alnum:]]+$ ]] && [[ ! "$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" ]] && {
										user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
										chat_id="$(echo "$updates" | jq ".result[$i].message.chat.id")"
										timestamp="$(echo "$updates" | jq ".result[$i].message.date")"
										sqlite3 alias <<< "insert into alias values('"$message_text"',$user_id,$chat_id,$reply_id,$timestamp);"
										message_text='Alias created'
									} || message_text='Alias already exists or name contains non-alphanumeric characters.'
								} || message_text='Alias name should not exceed 12 characters.'
							} || message_text='No reply message.'
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$reply_id" \
								--data-urlencode "text=$message_text"
						;;
						'alias -lm'*)
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
                                                	curl -s "$tele_url/sendMessage" \
	                                                        --data-urlencode "chat_id=$chat_id" \
        	                                                --data-urlencode "reply_to_message_id=$message_id" \
                	                                        --data-urlencode "text=$(sqlite3 alias <<< "select name from alias where user_id = '"$user_id"';" | sort | tr '\n' ' ')"
						;;
						'alias -l'*)
							message_text="$(sqlite3 alias <<< "select name from alias;" | sort | tr '\n' ' ')"
							message_length=4096
							(( $(echo "$message_text" | wc -m) > $message_length )) && {
								pile=''
								for i2 in $message_text; do
									(( $(echo "$pile $i2" | wc -m) >= $message_length )) && {
										curl -s "$tele_url/sendMessage" \
											--data-urlencode "chat_id=$chat_id" \
											--data-urlencode "reply_to_message_id=$message_id" \
											--data-urlencode "text=$pile"
										pile="$i2"
									} || {
										pile="$pile $i2"
									}
								done
								message_text="$pile"
							}
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$message_text"
						;;
						'alias -r '*)
							message_text="${message_text:9}"
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
							[[ "$(sqlite3 alias <<< "select user_id from alias where name = '"$message_text"';")" == "$user_id" ]] && {
								sqlite3 alias <<< "delete from alias where name = '"$message_text"';"
								response='Alias deleted.'
							} || response="Alias doesn't exist or you do not own it."
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$response"
						;;
						'alias -h'*)
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$(cat alias_help.txt)"
						;;
						*)
							message_text="${message_text:6}"
							[[ "$(sqlite3 alias <<< "select name from alias where name = '"$message_text"';")" ]] && {
								curl -s "$tele_url/forwardMessage" \
									--data-urlencode "chat_id=$chat_id" \
									--data-urlencode "from_chat_id=$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" \
									--data-urlencode "message_id=$(sqlite3 alias <<< "select reply_id from alias where name = '"$message_text"';")"
								timestamp="$(echo "$updates" | jq ".result[$i].message.date")"
								sqlite3 alias <<< "update alias set timestamp=$timestamp where name='"$message_text"';"
							}
						;;
					esac
				;;
				'hashtag'*)
					message_text="${message_text//;}"
					content_text="${message_text:11}"
					user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
					user_name="$(echo "$updates" | jq ".result[$i].message.from.username")"
					message_id="$(echo "$updates" | jq ".result[$i].message.message_id")"
					case $message_text in
						'hashtag -s'*)
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
							if (( $(echo $content_text | wc -m) < 14 )); then
								if [[ $content_text =~ ^[[:alnum:]]+$ ]]; then
									if [[ ! "$(sqlite3 hashtag <<< "select user_id from '"$content_text"' where user_id='"$user_id"';")" ]]; then
										if [[ ! "$(sqlite3 hashtag <<< "select name from sqlite_master where type='table' and name='"$content_text"';")" ]]; then
											sqlite3 hashtag <<< "create table '"$content_text"'(user_id smallint);"
										fi
										sqlite3 hashtag <<< "insert into '"$content_text"' values($user_id);"
										answer_text="You have subscribed to hashtag $content_text."
									else
										answer_text="You are already subscribed to hashtag $content_text."
									fi
								else
									answer_text='Hashtag name contains non-alphanumeric characters.'
								fi
							else
								answer_text='Hashtag name should not exceed 12 characters.'
							fi
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$answer_text"
						;;
						'hashtag -u'*)
							if [[ "$(sqlite3 hashtag <<< "select user_id from '"$content_text"' where user_id='"$user_id"';")" ]]; then
								sqlite3 hashtag <<< "delete from '"$content_text"' where user_id='"$user_id"';"
								answer_text="You have unsubscribed from this tag."
								if [[ ! "$(sqlite3 hashtag <<< "select * from '"$content_text"';")" ]]; then
									sqlite3 hashtag <<< "drop table '"$content_text"';"
								fi
							else
								answer_text="You are not subscribed to this hashtag."
							fi
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$answer_text"
						;;
						'hashtag -l'*)
							if [[ $content_text ]]; then
								answer_text=""
								for user in $(sqlite3 hashtag <<< "select user_id from '"$content_text"';"); do
									username="$(curl -s "$tele_url/getChatMember" \
										--data-urlencode "chat_id=$chat_id" \
										--data-urlencode "user_id=$user" | jq '.result.user.username' | sed 's/"//g')"
									if [[ $username != 'null' ]]; then
										answer_text="$answer_text $username"
									fi
								done
							else
								answer_text=""
								for hashtag in $(sqlite3 hashtag <<< "select name from sqlite_master;"); do
									if [[ $(sqlite3 hashtag <<< "select user_id from '"$hashtag"' where user_id=$user_id;") ]]; then
										answer_text="$answer_text "'#'"$hashtag"
									fi
								done
							fi
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$answer_text"
						;;
						'hashtag -h'*)
							curl -s "$tele_url/sendMessage" \
								--data-urlencode "chat_id=$chat_id" \
								--data-urlencode "reply_to_message_id=$message_id" \
								--data-urlencode "text=$(cat hashtag_help.txt)"
						;;
					esac
				;;
				'ping'*)
					curl -s "$tele_url/sendMessage" \
						--data-urlencode "chat_id=$chat_id" \
						--data-urlencode "reply_to_message_id=$message_id" \
						--data-urlencode "text=pong"
				;;
				'sources'*)
					curl -s "$tele_url/sendMessage" \
						--data-urlencode "chat_id=$chat_id" \
						--data-urlencode "reply_to_message_id=$message_id" \
						--data-urlencode "text=https://gitlab.com/madicine6/eBashBot"
				;;
				*)
					if [[ $(echo "$message_text" | grep '#') ]]; then
						message_text="$(echo "$message_text" | grep -o '#[[:alnum:]]*' | tr " " "\n" | sort | uniq)"
						for word in $message_text; do
							hashtag="$(echo $word | sed 's/.//')"
							if [[ "$(sqlite3 hashtag <<< "select name from sqlite_master where type='table' and name='"$hashtag"';")" ]]; then
								message_text=""
								message_id="$(echo "$updates" | jq ".result[$i].message.message_id")"
								for users in $(sqlite3 hashtag <<< "select user_id from '"$hashtag"';"); do
									username="@$(curl -s "$tele_url/getChatMember" \
										--data-urlencode "chat_id=$chat_id" \
										--data-urlencode "user_id=$users" | jq '.result.user.username' | sed 's/"//g')"
									if [[ $username != '@null' ]]; then
										message_text="$message_text $username"
									fi
								done
								curl -s "$tele_url/sendMessage" \
									--data-urlencode "chat_id=$chat_id" \
									--data-urlencode "reply_to_message_id=$message_id" \
									--data-urlencode "text=$message_text"
							fi
						done
					fi
				;;
			esac
			} &
		}
	} || sleep 1
done