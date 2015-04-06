#!/bin/bash

export game=`./Mojo-Server.pl get '/?method=start'`
export p1=`./Mojo-Server.pl get "/?method=connect&gameid=${game}"`
export p2=`./Mojo-Server.pl get "/?method=connect&gameid=${game}"`
export toMove=$p1

rm -f output.txt

for i in 0 1 2 3 4 5 6; do 
	`./Mojo-Server.pl get "/?method=move&gameid=${game}&playerid=${toMove}&position=${i}" 1>> output.txt`
	if [ $toMove == $p1 ]; then
		toMove=$p2;
	elif [ $toMove == $p2 ]; then
		toMove=$p1;
	fi
done

cat output.txt
rm output.txt

# X 0 X
# 0 X 0
# X _ _

# X Wins
