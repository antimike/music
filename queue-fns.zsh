#!/bin/zsh -f

q=./itunes-library-dirs.json
mus="/media/iTunes/iTunes Media/Music"
log=${log:-./import.log}
typeset -A beet_opts=(
    [-g]="Group tracks within the same directory into separate albums"
    [-p]="Automatically resume interrupted imports"
)

update_album_attribute() {
    local album=$1
    local -A fail_opts=(
        [leave]="Leave path attribute in queue as-is"
        [fail]="Set path attribute in queue to -1"
        [succeed]="Set path attribute in queue to +1 (appropriate if album has already been successfully imported)"
    )
    print -u2 ""
    select opt (${(v)fail_opts}); do
        case "$opt" in
            ${(b)fail_opts[leave]}) ;;
            ${(b)fail_opts[fail]}) set_path $album -1 ;;
            ${(b)fail_opts[succeed]}) set_path $album 1 ;;
        esac
        return $?
    done
}

__confirm() {
    local prompt=$1; shift
    read $@ -qs "?$prompt"
    local -i stat=$?
    print ""
    return $stat
} >&2

beet_import_albums() {
    local -aU opts
    print "Enter desired options for Beets import:"
    print -aC2 -- ${(kv)beet_opts}
    read -A opts
    for album ($@); do
        local -i stat=$(get_path $album)
        (( stat != 0 )) && continue
        print -u2 "Importing album $album (current status=$stat)"
        __confirm "(Press [yY] to abort and break the loop...)" -t 2 && break
        print -u2 ""
        beet import ${(k)opts} -l $log $album
        if [[ $? -eq 0 ]]; then
            print -u2 "Album $album processed successfully."
            __confirm "Continue [yY] or modify path attribute?" &&
                set_path $album 1 ||
                update_album_attribute $album
        else
            print -u2 "Import of album $album failed."
            update_album_attribute $album
        fi
    done
    print -u2 "Import loop finished!"
}

update_queue() {
    local -i idx=${@[(i)--*arg*]}
    cp "${q}" "${q}~" &&
        jq ${@[1,${idx}-1]} "${q}~" ${@[${idx},-1]} >"${q}" ||
        cp "${q}~" "${q}"
}

set_path() {
    update_queue '
        ([$root]+($dir|split("/"))) as $path |
            getpath($path) as $curr |
            if $curr != null
            then setpath($path; $val|tonumber)
            else error("Path \($path|join("/")) not found")
            end
    ' --arg dir ${1#${mus}/} --arg val $2 --arg root $mus
}

get_path() {
    jq 'getpath([$root]+($dir|split("/")))' $q \
        --arg dir ${1#${mus}/} --arg root $mus
}

get_paths() {
    jq -r '($arg|tonumber) as $val | path(..|scalars|select(.==$val)) | join("/")' $q \
        --arg arg $1
}

find_album_paths() {
    jq -r 'paths(scalars)|join("/")' $q | rg $@
}
