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

export WD_BOARD=${WD_BOARD:-"$WD/ASCII-board"}
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


function win_case { # $1: type  $2: player
    board_update
    >&3 echo COMPLETE by $1
    board_banner YOU $(let "$2" && echo "WON" || echo "LOSE")
    exit
}


function check_endgame {
    fail_ldia=0 fail_rdia=0
    fail_hor_array=() fail_ver_array=()

    local rindex=0 cindex=0
    local rval=0 cval=0
    local ldia=${board[0]:-"a0"}
    local rdia=${board[M]:-"a$M"}

    for ((i=0; i < BOARD_SIZE; i++)); do
        local hindex=$rindex vindex=$i
        local fail_hor=0 fail_ver=0
        htile=${board[rindex]:-"a$rindex"}
        vtile=${board[i]:-"a$i"}

        for ((j=0; j < BOARD_SIZE; j++)); do
            ## making unique
            rval=${board[rindex]:-"a$rindex"}

            ## horizontals: board[i][0] <cmp> board[i][j]
            [[ "$htile" != $rval ]] && {
                # >&3 echo hor $htile == $rval $rindex
                let fail_hor++
                htile=${board[hindex]:-"$rval"}
            }

            # verticle: board[0][i] <cmp> board[j][i]
            let cindex="j * BOARD_SIZE + i"
            cval=${board[cindex]:-"a$cindex"}
            [[ "$vtile" != $cval ]] && {
                let fail_ver++
                vtile=${board[vindex]:-"$cval"}
            }

            ## left diagonal: board[0][0] <cmp> board[i][j]
            (( i == j )) &&  [[ "$ldia" != $rval ]] && {
                let fail_ldia++
                ldia=${board[0]:-"$rval"}
            }

            ## right diagonal: board[0][max] <cmp> board[i][BOARD_SIZE-j]
            (( i == M - j )) && [[ "$rdia" != $rval ]] && {
                let fail_rdia++
                rdia=${board[0]:-"$rval"}
            }

            let rindex++
        done
        (( fail_hor == 0 )) && win_case "HORZONTAL $i" $rval
        (( fail_ver == 0 )) && win_case "VERTICLE $i" $cval
        let fail_hor_array[i]=fail_hor
        let fail_ver_array[i]=fail_ver
     done
    (( fail_ldia == 0 )) && win_case "LEFT DIAGONAL" $ldia
    (( fail_rdia == 0 )) && win_case "RIGHT DIAGONAL" $rdia
}


function random_move {
    while (( tiles < N )); do
        local index=$((RANDOM%N))
        # >&3 echo $index
        [[ ${board[index]} == "" ]] && {
            let board[index]=0
            let tiles++
            break
        }
    done
}


function check_almost { #$1: count $2: index_func $3: msg
    # block or complete
    local count=$1 index_func=$2 msg=$3
    if (( count == 1 )); then
        >&3 echo "almost $msg"
        for ((i=0; i < BOARD_SIZE; i++)); do
            local index=$(($index_func))
            >&3 echo $index
            test -z ${board[index]} && {
                let board[index]=0
                let tiles++
                return 0
            }
        done
    fi
    return 1
}


function computer {
    check_almost $fail_ldia "BOARD_SIZE*i+i" "LEFT DIAGONAL" && return
    check_almost $fail_rdia "BOARD_SIZE*i+M-i" "RIGHT DIAGONAL" && return
    for ((c=0; c < BOARD_SIZE; c++)); do
        check_almost ${fail_hor_array[c]} "BOARD_SIZE*$c+i" "HORIZONTAL $c" && return
        check_almost ${fail_ver_array[c]} "BOARD_SIZE*i+$c" "VERTICLE $c" && return
    done
    random_move
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
        computer
        >&3 echo
        check_endgame
        test $tiles == $N && {
            board_update
            board_banner 'DRAW'
            exit
        }
    done
}


declare moves=0 tiles=0
trap "board_banner 'GAME OVER'; exit" INT #handle INTERRUPT
N=$((BOARD_SIZE*BOARD_SIZE))
M=$((BOARD_SIZE-1))
board_init $BOARD_SIZE
echo -n $'\e'"[?9h" # enable-mouse
exec 2>&3 # redirecting errors

echo -e $header
status
board_print $BOARD_SIZE
game_loop
