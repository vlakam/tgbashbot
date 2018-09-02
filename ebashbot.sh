#!/bin/bash

token=''
tele_url="https://api.telegram.org/bot$token"
last_id=0
[[ ! -f alias ]] && sqlite3 alias <<< 'create table alias(name varchar(10), user_id smallint, chat_id smallint, reply_id smallint);'

while true; do
	updates=$(curl -s "$tele_url/getUpdates" \
		--data-urlencode "offset=$(( $last_id + 1 ))" \
		--data-urlencode "timeout=60")
	updates_count=$(echo "$updates" | jq -r ".result | length")
	last_id=$(echo "$updates" | jq -r ".result[$(( "$updates_count" - 1 ))].update_id")
	for ((i=0; i<"$updates_count"; i++)); {
		chat_id="$(echo "$updates" | jq ".result[$i].message.chat.id")"
		reply_id="$(echo "$updates" | jq ".result[$i].message.reply_to_message.message_id")"
		reply_text="$(echo "$updates" | jq ".result[$i].message.reply_to_message.text" | sed --sandbox 's#\\\\#\\#g;s#\\\"#"#g;s/^"//;s/"$//')"
		message_text="$(echo "$updates" | jq ".result[$i].message.text" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
		case $message_text in
			's/'*|'s#'*|'y/'*)
				[[ "$reply_id" != 'null' ]] &&
				curl -s "$tele_url/sendMessage" \
					--data-urlencode "chat_id=$chat_id" \
					--data-urlencode "reply_to_message_id=$reply_id" \
					--data-urlencode "text=$(echo -e "$reply_text" | timeout 0.1s sed --sandbox "$message_text")"
			;;
			'grep '*|'cut '*)
				[[ "$reply_id" != 'null' ]] && {
					message_text="$(echo "$message_text" | tr -d '(){}`<>;|&$' | sed 's/--help//')"
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
			;;
			'alias '*)
                                message_text="${message_text//;}"
				case $message_text in
					'alias -a '*)
						[[ "$reply_id" != 'null' ]] && {
							message_text="${message_text:9}"
							[[ $message_text =~ ^[[:alnum:]]+$ ]] && [[ ! "$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" ]] && {
								user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
								chat_id="$(echo "$updates" | jq ".result[$i].message.chat.id")"
								sqlite3 alias <<< "insert into alias values('"$message_text"',$user_id,$chat_id,$reply_id);"
								message_text='Alias created'
							} || message_text='Alias already exists or name contains non-alphanumeric characters.'
						} || message_text='No reply message.'
						curl -s "$tele_url/sendMessage" \
                                                	--data-urlencode "chat_id=$chat_id" \
                                                        --data-urlencode "reply_to_message_id=$reply_id" \
                                                        --data-urlencode "text=$message_text"
					;;
##					'alias -r '*)
##					;;
		                        *)
						message_text="${message_text:6}"
						[[ "$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" ]] &&
                		                curl -s "$tele_url/forwardMessage" \
                                		        --data-urlencode "chat_id=$chat_id" \
							--data-urlencode "from_chat_id=$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" \
                		                        --data-urlencode "message_id=$(sqlite3 alias <<< "select reply_id from alias where name = '"$message_text"';")"
                     		   	;;
				esac
			;;
		esac
	}
done