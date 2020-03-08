#!/bin/bash

/usr/bin/sqlite3 /root/ebashbot/alias <<< "delete from alias where timestamp < '"$(( $(date +%s) - 7776000 ))"';"