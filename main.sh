#!/usr/bin/bash

__PKG_NAME__="ttt"

function Usage {
    echo -e "Usage: $__PKG_NAME__ [OPTIONS] [BOARD_SIZE]";
    echo -e "\t-b | --board\tboard size"
    echo -e "\t-d | --debug [FILE]\tdebug info to file provided"
    echo -e "\t-h | --help\tDisplay this message"
    echo -e "\t-v | --version\t\tversion information"
}

GETOPT=$(getopt -o b:d:hv \
                -l board:,debug:,help,version \
                -n "$__PKG_NAME__" \
                -- "$@")

[[ $? != "0" ]] && exit 1

eval set -- "$GETOPT"

export WD="$(dirname $(readlink $0 || echo $0))"
BOARD_SIZE=3
exec 3>/dev/null

while true; do
    case $1 in
        -b|--board)   BOARD_SIZE=$2; shift 2;;
        -d|--debug)   exec 3>$2; shift 2;;
        -h|--help)    Usage; exit;;
        -v|--version) cat $WD/.version; exit;;
        --)           shift; break
    esac
done

# extra argument
for arg do
    BOARD_SIZE=$arg
    break
done

#----------------------------------------------------------------------
# game LOGIC

header="\033[1m$__PKG_NAME__\033[m (https://github.com/rhoit/ttt)"

export WD_BOARD="$WD/ASCII-board"
source $WD_BOARD/board.sh

# modifying board
declare board_LCORN=(" " " " " " " ")
declare board_RCORN=(" " " " " " " ")
declare board_LINES=(" " "─" " " " ")
declare board_CROSS=(" " "┼" " " "│")


function key_react {
    read -d '' -sn 1
    test "$REPLY" == $'\e' && {
        read -d '' -sn 1 -t1
        test "$REPLY" == "[" && {
            read -d '' -sn 1 -t1
            case $REPLY in
                M) mouse_read_pos;;
            esac
        }
    }
}


function mouse_read_pos {
    IFS= read -r -d '' -sn1 -t1 _MOUSE1 || break 2
    IFS= read -r -d '' -sn1 -t1 _MOUSE2 || break 2
    IFS= read -r -d '' -sn1 -t1 _MOUSE3 || break 2
    # echo -n "$_MOUSE1" | od -An -tuC >&3
    let mouse_x="$(echo -n "$_MOUSE2" | od -An -tuC) - 32"
    let mouse_y="$(echo -n "$_MOUSE3" | od -An -tuC) - 32"
    >&3 echo "mouse: ($_MOUSE1 $mouse_x $mouse_y)"
}


function win_case {
    board_update
    board_banner "YOU WON"
    >&3 echo YOU WON
    exit
}


function check_endgame {
    local rindex=0 cindex=0
    local fail_ldia=0 fail_rdia=0
    local rval=0 cval=0

    local ldia="${board[0]}" rdia
    let rdia="board[BOARD_SIZE-1]"

    for ((i=0; i < BOARD_SIZE; i++)); do
        local itile=${board[rindex]}
        local fail_hor=0 fail_ver=0
        for ((j=0; j < BOARD_SIZE; j++)); do
            ## making unique
            test -z ${board[rindex]} && rval="a$i$j" || rval=${board[rindex]}

            ## horizontals: board[i][0] <cmp> board[i][j]
            [[ $itile != $rval ]] && let fail_hor++

            # verticle: board[0][i] <cmp> board[j][i]
            let cindex="j * BOARD_SIZE + i"
            test -z ${board[cindex]} && cval="a$j$i" || cval=${board[cindex]}
            [[ "" != $cval ]] && let fail_ver++

            ## left diagonal: board[0][0] <cmp> board[i][j]
            (( i == j )) &&  [[ "$ldia" != $rval ]] && let fail_ldia++

            ## right diagonal: board[0][max] <cmp> board[i][BOARD_SIZE-j]
            (( i + 1 == BOARD_SIZE - j )) && [[ "$rdia" != $rval ]] && let fail_rdia++

            let rindex++
        done
        (( fail_hor == 0 )) && win_case
        (( fail_ver == 0 )) && win_case
    done
    (( fail_ldia == 0 )) && win_case
    (( fail_rdia == 0 )) && win_case
}


function status {
	printf "moves: %-9d" "$moves"
	echo
}


function game_loop {
    while true; do
        board_update
        key_react
        (( mouse_x < offset_x + 2 )) && continue
        (( mouse_x > _max_x )) && continue
        (( mouse_y < offset_y + 1 )) && continue
        (( mouse_y > _max_y - 1 )) && continue

        local row=$(( (mouse_y - offset_y - 1) / (_tile_height + 1) ))
        local col=$(( (mouse_x - offset_x - 1) / (_tile_width + 1) ))
        local index=$(( row * BOARD_SIZE + col ))
        >&3 echo row: $row col: $col index: $index
        [[ ${board[index]} != "" ]] && continue

        let board[index]=1
        let moves++
        let tiles++
        board_tput_status; status
        check_endgame
        test $moves == $N && {
            board_update
            board_banner 'DRAW'
            exit
        }
    done
}

declare moves=0 tiles=0
trap "board_banner 'GAME OVER'; exit" INT #handle INTERRUPT
let N="BOARD_SIZE * BOARD_SIZE"
board_init $BOARD_SIZE
echo -n $'\e'"[?9h" # enable-mouse
exec 2>&3 # redirecting errors

echo -e $header
status
board_print $BOARD_SIZE
game_loop
