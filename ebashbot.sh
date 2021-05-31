#!/bin/bash

cd "$(dirname "$0")"

api_url="$1"
token="$2"
host="$3"
pic_path="$4"
clarifai_key="$5"
tele_url="$api_url/bot$token"
users_per_send=5
covid_api='https://corona.lmao.ninja/v2'
rm_lim='3'

last_id=0
if [[ ! -f alias ]]; then
	sqlite3 alias <<< 'create table alias(name varchar(10), user_id smallint, chat_id smallint, reply_id smallint, timestamp smallint);'
fi

send() {
	for ((count=1; count<=5; count++)); do
		curl -s "$tele_url/sendMessage" \
			--data-urlencode "chat_id=$1" \
			--data-urlencode "reply_to_message_id=$2" \
			--data-urlencode "text=$3"
		[[ "$?" == 0 ]] && break
	done
}

send_formatted() {
	for ((count=1; count<=5; count++)); do
		if [[ "$1" != 'reply' ]]; then
			curl -s "$tele_url/sendMessage" \
				--data-urlencode "parse_mode=html" \
				--data-urlencode "chat_id=$1" \
				--data-urlencode "text=<i>$(echo -e "$2" | sed 's/<i>//g;s/<\/i>//g')</i>"
		else
			curl -s "$tele_url/sendMessage" \
				--data-urlencode "parse_mode=html" \
				--data-urlencode "chat_id=$2" \
				--data-urlencode "reply_to_message_id=$3" \
				--data-urlencode "text=<i>$(echo -e "$4" | sed 's/<i>//g;s/<\/i>//g')</i>$5"
		fi
		[[ "$?" == 0 ]] && break
	done
}

message_id() {
	echo "$updates" | jq ".result[$i].message.message_id"
}

reply_id() {
	reply_id="$(echo "$updates" | jq ".result[$i].message.reply_to_message.message_id")"
}

reply_text() {
	reply_text="$(echo "$updates" | jq ".result[$i].message.reply_to_message.text")"
	if [[ $reply_text == 'null' ]]; then
		reply_text="$(echo "$updates" | jq ".result[$i].message.reply_to_message.caption")"
	fi
	reply_text="$(echo "$reply_text" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
}

get_hashtags() {
	pic_name="$(cat /dev/urandom | tr -cd '[:alnum:]' | head -c 8).png"
	rec_hashtags=""
	if [[ $1 == 'reply' ]]; then
		reply='.reply_to_message'
	fi
	file_id_num="$(echo "$updates" | jq -r ".result[$i].message$reply.photo | length")"
	if [[ $file_id_num != 0 ]]; then
		file_id="$(echo "$updates" | jq -r ".result[$i].message$reply.photo[$(( $file_id_num - 1 ))].file_id")"
		file_path="$(curl --data-urlencode "file_id=$file_id" "$tele_url/getFile" | jq ".result.file_path" | tr -d '"')"
		curl "$api_url/file/bot$token/$file_path" > "$pic_path/$pic_name"
		clarifai="$(curl -X POST \
			-H "Authorization: Key $clarifai_key" \
			-H "Content-Type: application/json" \
			-d '
				{
					"inputs": [
						{
							"data": {
								"image": {
									"url": "'$host'/'$pic_name'"
								}
							}
						}
					]
				}'\
			https://api.clarifai.com/v2/models/aaa03c23b3724a16a56b629203edc62c/outputs | jq ".outputs[0].data.concepts")"
		rm "$pic_path/$pic_name"
		clarifai_length="$(echo "$clarifai" | jq ". | length")"
		rec_hashtags=""
		for ((rec_num=0; rec_num<"$clarifai_length"; rec_num++)); do
			hashtag="$(echo $clarifai | jq ".[$rec_num].name" | sed 's/"//g;s/ /_/g;s/-//g')"
			rec_hashtags="$rec_hashtags "'#'"$hashtag"
		done
	fi
}

story(){
	story="$(curl -s 'https://models.dobro.ai/gpt2/medium/' --data-binary '{"prompt":"'"$*"'","length":50,"num_samples":1}' | jq -r ".replies[]")"
}

covid_top(){
	timeout 3s curl -s "$covid_api/countries?sort=$1" | jq -r '.[0,1,2,3,4,5,6,7,8,9] | "\(.country) - \(.'"$1"')"'
}

covid_answer() {
	answer_text="$(covid_top $1)"
	if [[ "$?" != '0' ]]; then
		answer_text='API response error'
	else
		answer_text="Top 10 countries by $2:\n\n$answer_text"
	fi
}

while true; do
	ping -c1 $(echo "$tele_url" | cut -d '/' -f 3) 2>&1 > /dev/null && {
		updates=$(curl -s "$tele_url/getUpdates" \
			--data-urlencode "offset=$(( $last_id + 1 ))" \
			--data-urlencode "timeout=60")
		updates_count=$(echo "$updates" | jq -r ".result | length")
		last_id=$(echo "$updates" | jq -r ".result[$(( "$updates_count" - 1 ))].update_id")
		for ((i=0; i<"$updates_count"; i++)); do
			(
			date +%F-%T >> ebash.log
			echo "$updates" | jq ".result[$i]" >> ebash.log
			chat_id="$(echo "$updates" | jq ".result[$i].message.chat.id")"
			message_text="$(echo "$updates" | jq ".result[$i].message.text")"
			if [[ $message_text == 'null' ]]; then
				message_text="$(echo "$updates" | jq ".result[$i].message.caption")"
			fi
			message_text="$(echo "$message_text" | sed --sandbox 's#\\"#"#g;s#\\\\#\\#g;s/^"//;s/"$//')"
			case $message_text in
				's/'*|'s#'*|'y/'*)
					reply_id
					if [[ "$reply_id" != 'null' ]]; then
						reply_text
						if [[ "$reply_text" != 'null' ]]; then
							send "$chat_id" "$reply_id" "$(echo -e "$reply_text" | timeout 0.1s sed -E --sandbox "$message_text")"
						fi
					fi
				;;
				'grep '*|'cut '*|'rev'|'bc'|'bc -l')
					reply_id
					if [[ "$reply_id" != 'null' ]]; then
						reply_text
						if [[ "$reply_text" != 'null' ]]; then
							message_text="$(echo "$message_text" | tr -d '(){}`<>;|&$')"
							if [[ ! "$(echo "$message_text" | grep -i 'recurs\|--help\|-.*r')" ]]; then
								for f in ${message_text//=/ }; do
									if [[ -e "$f" ]]; then
										file_found=1
										break
									fi
								done
								if [[ "$file_found" != '1' ]]; then
									send "$chat_id" "$reply_id" "$(echo -e "$reply_text" | eval "$message_text"' & pid='"$?"'; sleep 1; kill '"$pid" | head -n 10)"
								else
									file_found=0
								fi
							fi
						fi
					fi
				;;
				'alias '*)
					message_text="${message_text//;}"
					case $message_text in
						'alias -a '*)
							reply_id
							if [[ "$reply_id" != 'null' ]]; then
								message_text="${message_text:9}"
								if (( $(echo $message_text | wc -m) < 14 )); then
									if [[ $message_text =~ ^[[:alnum:]]+$ ]] && [[ ! "$(sqlite3 alias <<< "select chat_id from alias where name = '$message_text' and chat_id = '$chat_id';")" ]]; then
										user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
										timestamp="$(echo "$updates" | jq ".result[$i].message.date")"
										sqlite3 alias <<< "insert into alias values('"$message_text"',$user_id,$chat_id,$reply_id,$timestamp);"
										message_text='Alias created'
									else
										message_text='Alias already exists or name contains non-alphanumeric characters.'
									fi
								else
									message_text='Alias name should not exceed 12 characters.'
								fi
							else
								message_text='No reply message.'
							fi
							send "$chat_id" "$reply_id" "$message_text"
						;;
						'alias -lm'*)
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
							send "$chat_id" "$(message_id)" "$(sqlite3 alias <<< "select name from alias where user_id = '$user_id' and chat_id = '$chat_id';" | sort | tr '\n' ' ')"
						;;
						'alias -l'*)
							answer_text="$(sqlite3 alias <<< "select name from alias where chat_id='$chat_id';" | sort | tr '\n' ' ')"
							message_length=4096
							if (( $(echo "$answer_text" | wc -m) > $message_length )); then
								pile=''
								for i2 in $answer_text; do
									if (( $(echo "$pile $i2" | wc -m) >= $message_length )); then
										send "$chat_id" "$(message_id)" "$pile"
										pile="$i2"
									else
										pile="$pile | $i2"
									fi
								done
								answer_text="$pile"
							else
								answer_text="$(echo "$answer_text" | sed 's/ / | /g')"
							fi
							send "$chat_id" "$(message_id)" "$answer_text"
						;;
						'alias -r '*)
							message_text="${message_text:9}"
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
							if [[ "$(sqlite3 alias <<< "select user_id from alias where name = '$message_text' and chat_id = '$chat_id';")" == "$user_id" ]]; then
								sqlite3 alias <<< "delete from alias where name = '"$message_text"';"
								answer_text='Alias deleted.'
							else
								answer_text="Alias doesn't exist or you do not own it."
							fi
							send "$chat_id" "$(message_id)" "$answer_text"
						;;
						'alias -h'*)
							send "$chat_id" "$(message_id)" "$(cat alias_help.txt)"
						;;
						*)
							message_text="${message_text:6}"
							if [[ "$(sqlite3 alias <<< "select name from alias where name = '$message_text' and chat_id = '$chat_id';")" ]]; then
								curl -s "$tele_url/forwardMessage" \
									--data-urlencode "chat_id=$chat_id" \
									--data-urlencode "from_chat_id=$(sqlite3 alias <<< "select chat_id from alias where name = '"$message_text"';")" \
									--data-urlencode "message_id=$(sqlite3 alias <<< "select reply_id from alias where name = '"$message_text"';")"
								timestamp="$(echo "$updates" | jq ".result[$i].message.date")"
								sqlite3 alias <<< "update alias set timestamp = $timestamp where name='$message_text' and chat_id = '$chat_id';"
							fi
						;;
					esac
				;;
				'hashtag'*)
					message_text="${message_text//;}"
					content_text="${message_text:11}"
					user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
					user_name="$(echo "$updates" | jq ".result[$i].message.from.username")"
					case $message_text in
						'hashtag -s'*)
							user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
							if (( $(echo $content_text | wc -m) < 18 )); then
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
								answer_text='Hashtag name should not exceed 16 characters.'
							fi
							send "$chat_id" "$(message_id)" "$answer_text"
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
							send "$chat_id" "$(message_id)" "$answer_text"
						;;
						'hashtag -l'*)
							if [[ $content_text ]]; then
								answer_text=""
								for user in $(sqlite3 hashtag <<< "select user_id from '"$content_text"';"); do
									userinfo="$(curl -s "$tele_url/getChatMember" \
										--data-urlencode "chat_id=$chat_id" \
										--data-urlencode "user_id=$user")"
									username="$(echo "$userinfo" | jq '.result.user.username' | sed 's/"//g')"
									status="$(echo "$userinfo" | jq -r '.result.status')"
									if [[ $username != 'null' ]] && [[ $status != 'left' ]] && [[ $status != 'kicked' ]]; then
										answer_text="$answer_text $username"
									fi
								done
							else
								answer_text=""
								for hashtag in $(sqlite3 hashtag <<< "select name from sqlite_master;"); do
									if [[ $(sqlite3 hashtag <<< "select user_id from '"$hashtag"' where user_id=$user_id;") ]]; then
										answer_text="$answer_text "'#'"$hashtag"
										temp "$answer_text"
									fi
								done
								wait
							fi
							send "$chat_id" "$(message_id)" "$answer_text"
						;;
						'hashtag -g'*)
							reply_id
							if [[ "$reply_id" != 'null' ]]; then
								get_hashtags reply
								if [[ ! -z $rec_hashtags ]]; then
									send "$chat_id" "$reply_id" "$rec_hashtags"
								fi
							fi
						;;
						'hashtag -h'*)
							send "$chat_id" "$(message_id)" "$(cat hashtag_help.txt)"
						;;
					esac
				;;
				'distort'*)
					message_text="${message_text:8}"
					if [[ $message_text =~ ^[[:digit:]]+$ ]]; then
						if (( $message_text < 100 )); then
							distort_value=$message_text
						else
							distort_value=100
						fi
					else
						distort_value=50
					fi
					reply_id
					if [[ "$reply_id" != 'null' ]]; then
						reply='.reply_to_message'
					else
						reply_id="$(message_id)"
					fi
					file_id_num="$(echo "$updates" | jq -r ".result[$i].message$reply.photo | length")"
					if [[ $file_id_num != 0 ]]; then
						file_id="$(echo "$updates" | jq -r ".result[$i].message$reply.photo[$(( $file_id_num - 1 ))].file_id")"
						file_path="$(curl --data-urlencode "file_id=$file_id" "$tele_url/getFile" | jq ".result.file_path" | tr -d '"')"
						pic_name_gen="$(cat /dev/urandom | tr -cd "[:alnum:]" | head -c 8).png"
						curl "$api_url/file/bot$token/$file_path" > "$pic_path/$pic_name_gen"
						dimensions="$(identify -format '%wx%h' $pic_path/$pic_name_gen)"
						convert "$pic_path/$pic_name_gen" \
							-liquid-rescale "$(( 101 - $distort_value ))"%x"$(( 101 - $distort_value ))"%! \
							-resize "$dimensions"! \
							"$pic_path/$pic_name_gen"
 						curl -s "$tele_url/sendPhoto" \
							-F "chat_id=$chat_id" \
							-F "reply_to_message_id=$reply_id" \
							-F "photo=@./$pic_path/$pic_name_gen"
						rm "$pic_path/$pic_name_gen"
					else
						send "$chat_id" "$(message_id)" "No image specified!"
					fi
				;;
				'ping'*)
					send "$chat_id" "$(message_id)" "pong"
				;;
				'sources'*)
					send "$chat_id" "$(message_id)" "https://gitlab.com/madicine6/eBashBot"
				;;
				'/me '*)
					reply_id
					curl -s "$tele_url/deleteMessage" \
						--data-urlencode "chat_id=$chat_id" \
						--data-urlencode "message_id=$(message_id)"
					user_name="$(echo "$updates" | jq -r ".result[$i].message.from.first_name")"
					last_name="$(echo "$updates" | jq -r ".result[$i].message.from.last_name")"
					if [[ ! "$last_name" == 'null' ]]; then
						user_name="$user_name $last_name"
					fi
					if [[ "$reply_id" ]]; then
						send_formatted 'reply' "$chat_id" "$reply_id" "$user_name ${message_text:4}"
					else
						send_formatted "$chat_id" "$user_name ${message_text:4}"
					fi
				;;
				'story'*)
					reply_id
					if [[ "$reply_id" != 'null' ]]; then
						reply_text
						if [[ "$reply_text" != 'null' ]]; then
							story "${reply_text//\\}"
							send_formatted 'reply' "$chat_id" "$reply_id" "$reply_text" "$story"
						else
							send "$chat_id" "$(message_id)" "Reply message has no text."
						fi
					else
						if [[ "${message_text:6}" ]]; then
							story "${message_text:6}"
							send_formatted 'reply' "$chat_id" "$(message_id)" "${message_text:6}" "$story"
						else
							send "$chat_id" "$(message_id)" "No text specified."
						fi
					fi
				;;
				'covid'*)
					case $message_text in
						'covid')
							covid_response="$(timeout 3s curl -s "$covid_api/all")"
							if [[ "$?" != '0' ]]; then
								answer_text='API response error'
							else
								covid_lastupdated="$(echo "$covid_response" | jq -r ".updated")"
								answer_text="Covid-19 worldwide information:

Cases total: $(echo "$covid_response" | jq -r ".cases")
Cases today: $(echo "$covid_response" | jq -r ".todayCases")
Deaths total: $(echo "$covid_response" | jq -r ".deaths")
Deaths today: $(echo "$covid_response" | jq -r ".todayDeaths")
Recovered: $(echo "$covid_response" | jq -r ".recovered")
Active cases: $(echo "$covid_response" | jq -r ".active")
In critical condition: $(echo "$covid_response" | jq -r ".critical")
Cases per million: $(echo "$covid_response" | jq -r ".casesPerOneMillion")
Deaths per illion: $(echo "$covid_response" | jq -r ".deathsPerOneMillion")
Tests total: $(echo "$covid_response" | jq -r ".tests")
Tests per million: $(echo "$covid_response" | jq -r ".testsPerOneMillion")
Affected countries: $(echo "$covid_response" | jq -r ".affectedCountries")

Last time updated: $(date -d @${covid_lastupdated::-3})"
							fi
						;;
						'covid -t '*)
							message_text="${message_text:9}"
							case $message_text in
								'cases'*)
									message_text="${message_text:5}"
									if [[ "$message_text" ]]; then
										case $message_text in
											' today')
												covid_answer "todayCases" "new cases today"
											;;
											' per1kk')
												covid_answer "casesPerOneMillion" "cases per million"
											;;
											*)
												answer_text='Wrong parameter specified'
											;;
										esac
									else
										covid_answer "cases" "cases total"
									fi
								;;
								'deaths'*)
									message_text="${message_text:6}"
									if [[ "$message_text" ]]; then
										case $message_text in
											' today')
												covid_answer "todayDeaths" "deaths today"
											;;
											' per1kk')
												covid_answer "deathsPerOneMillion" "deaths per million"
											;;
											*)
												answer_text='Wrong parameter specified'
											;;
										esac
									else
										covid_answer "deaths" "deaths total"
									fi
								;;
								'recovered')
									covid_answer "recovered" "recovery cases"
								;;
								'active')
									answer_text="Top 10 countries by active cases:\n\n$(covid_top active)"
									covid_answer "active" "active cases"
								;;
								'critical')
									covid_answer "critical" "critical cases"
								;;
								*)
									answer_text='Wrong parameter specified'
								;;
							esac
						;;
						'covid -p '*)
							message_text="${message_text:9}"
							country="$(echo "$message_text" | cut -d ' ' -f 2)"
							filter="$(echo "$message_text" | cut -d ' ' -f 1)"
							if [[ "$country" ]]; then
								if [[ "$filter" == 'cases' ]] || [[ "$filter" == 'deaths' ]] || [[ "$filter" == 'recovered' ]]; then
									covid_response="$(timeout 3s curl -s "$covid_api/historical/$(echo "$country" | sed --sandbox 's/[[:blank:]]/%20/g')?lastdays=15")"
									if [[ "$?" != '0' ]]; then
										answer_text='API response error'
									else
										if [[ "$(echo "$covid_response" | jq -r ".message")" == "Country not found or doesn't have any historical data" ]]; then
											answer_text="$(echo "$covid_response" | jq -r ".message")"
										else
											answer_text="Number of $filter for $country in the last 15 days:

$(echo "$covid_response" | jq -r ".timeline.$filter" | head -n -1 | tail -n +2 | tr -d '",')"
										fi
									fi
								else
									answer_text='Wrong parameter specified'
								fi
							else
								answer_text='Not enough parameters'
							fi
						;;
						'covid -h')
							answer_text="$(cat covid_help.txt)"
						;;
						'covid '*)
							message_text="${message_text:6}"
							if [[ ! "$(echo "$message_text" | tr -d '[:alpha:] ')" ]]; then
								covid_response="$(timeout 3s curl -s "$covid_api/countries/$(echo "$message_text" | sed --sandbox 's/[[:blank:]]/%20/g')")"
								if [[ "$?" != '0' ]]; then
									answer_text='API response error'
								else
									if [[ "$(echo "$covid_response" | jq -r ".message")" == "Country not found or doesn't have any cases" ]]; then
										answer_text="$(echo "$covid_response" | jq -r ".message")"
									else
										covid_lastupdated="$(echo "$covid_response" | jq -r ".updated")"
										answer_text="Covid-19 information for $(echo "$covid_response" | jq -r ".country"):

Cases total: $(echo "$covid_response" | jq -r ".cases")
Cases today: $(echo "$covid_response" | jq -r ".todayCases")
Deaths total: $(echo "$covid_response" | jq -r ".deaths")
Deaths today: $(echo "$covid_response" | jq -r ".todayDeaths")
Recovered total: $(echo "$covid_response" | jq -r ".recovered")
Active cases: $(echo "$covid_response" | jq -r ".active")
In critical condition: $(echo "$covid_response" | jq -r ".critical")
Cases per million: $(echo "$covid_response" | jq -r ".casesPerOneMillion")
Deaths per million: $(echo "$covid_response" | jq -r ".deathsPerOneMillion")
Tests total: $(echo "$covid_response" | jq -r ".tests")
Tests per million: $(echo "$covid_response" | jq -r ".testsPerOneMillion")

Last time updated: $(date -d @${covid_lastupdated::-3})"
									fi
								fi
							fi
						;;
					esac
					send "$chat_id" "$(message_id)" "$(echo -e "$answer_text")"
				;;
				'rm')
					reply_id
					message_id="$(message_id)"
					user_id="$(echo "$updates" | jq ".result[$i].message.from.id")"
					if [[ "$reply_id" == 'null' ]]; then
						message_text="No message specified."
					else
						if [[ ! "$(sqlite3 rm.db <<< "select name from sqlite_master where type='table' and name='"c$(echo "$chat_id" | tr -d '-')"';")" ]]; then
							sqlite3 rm.db <<< 'create table '"c$(echo "$chat_id" | tr -d '-')"'(message_id smallint, user_id smallint, timestamp smallint);'
						fi
						if [[ ! "$(sqlite3 rm.db <<< "select message_id from c$(echo "$chat_id" | tr -d '-') where user_id = '"$user_id"' and message_id = '"$reply_id"'")" ]]; then
							count="$(( $(sqlite3 rm.db <<< "select message_id from c$(echo "$chat_id" | tr -d '-') where user_id != '"$user_id"' and message_id = '"$reply_id"'"| wc -l) + 1 ))"
							if (( $count >= $rm_lim )); then
								curl -s "$tele_url/deleteMessage" \
									--data-urlencode "chat_id=$chat_id" \
									--data-urlencode "message_id=$reply_id"
								message_text="Message removed."
								sqlite3 rm.db <<< "drop table c$(echo "$chat_id" | tr -d '-');"
							else
								timestamp="$(echo "$updates" | jq ".result[$i].message.date")"
								sqlite3 rm.db <<< "insert into c$(echo "$chat_id" | tr -d '-') values($reply_id,$user_id,$timestamp);"
								message_text="Message report count: $count"
							fi
						else
							message_text="You've already reported this message."
						fi
					fi
 					send "$chat_id" "$message_id" "$message_text"
				;;
				*)
					get_hashtags
					if [[ "$(echo "$message_text" | grep '#')" ]] || [[ ! -z "$rec_hashtags" ]]; then
						hashlist="$(echo "$message_text" | grep -o '#[[:alnum:]]*' | tr " " "\n" | sort -u)"
					fi
					if [[ "$rec_hashtags $hashlist" != " " ]]; then
						for word in $rec_hashtags $hashlist; do
							hashtag="${word:1}"
							if [[ "$(sqlite3 hashtag <<< "select name from sqlite_master where type='table' and name='"$hashtag"';")" ]]; then
								mention=0
								for users in $(sqlite3 hashtag <<< "select user_id from '"$hashtag"';"); do
									if [[ ! $(echo "$user_id_list" | grep "$users") ]]; then
										user_id_list="$user_id_list $users"
										userinfo="$(curl -s "$tele_url/getChatMember" \
											--data-urlencode "chat_id=$chat_id" \
											--data-urlencode "user_id=$users")"
										username="@$(echo "$userinfo" | jq -r '.result.user.username')"
										status="$(echo "$userinfo" | jq -r '.result.status')"
										if [[ $username != '@null' ]] && [[ $status != 'left' ]] && [[ $status != 'kicked' ]]; then
											mention=1
											post_users="$post_users $username"
										fi
									fi
								done
								user_id_list=''
								if [[ $mention == 1 ]]; then
									post_hashtags="$post_hashtags "'#'"$hashtag"
								fi
							fi
						done
						if [[ ! -z $post_hashtags ]]; then
							echo -n "$post_hashtags" >> /tmp/post_hashtags
							if [[ ! -f /tmp/chat_id ]]; then
								echo "$chat_id" > /tmp/chat_id
							fi
							if [[ ! -f /tmp/message_id ]]; then
								echo "$(message_id)" > /tmp/message_id
							fi
							echo -n "$post_users" >> /tmp/post_users
						fi
					fi
				;;
			esac
			) &
			wait
		done
		if [[ -f /tmp/post_hashtags ]]; then
			post_hashtags="$(cat /tmp/post_hashtags | tr ' ' '\n' | sort -u | tr '\n' ' ')"
			chat_id="$(cat /tmp/chat_id)"
			message_id="$(cat /tmp/message_id)"
			post_users="$(cat /tmp/post_users | tr ' ' '\n' | sort -u)"
			users_num="$(echo -n "$post_users" | wc -l)"
			if (( "$users_num" > "$users_per_send" )); then
				for ((user_offset=1; user_offset<="$users_num"; user_offset="$(( "$user_offset" + "$users_per_send" ))" )); do
					post_users_chunk="$(echo "$post_users" | tail -n "$(( $users_num - $user_offset + 1 ))" | head -n "$users_per_send" | tr '\n' ' ')"
					send "$chat_id" "$message_id" "$(echo -e "$post_hashtags\n\n$post_users_chunk")"
				done
			else
				post_users="$(echo "$post_users" | tr '\n' ' ')"
				send "$chat_id" "$message_id" "$(echo -e "$post_hashtags\n\n${post_users:1}")"
			fi
			rm /tmp/{chat_id,message_id,post_users,post_hashtags}
			post_users=""
			post_hashtags=""
		fi
	}
done
