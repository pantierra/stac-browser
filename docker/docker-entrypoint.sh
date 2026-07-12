#!/bin/sh
set -eu

PLACEHOLDER="/__SB_PATH_PREFIX__/"

normalize_path_prefix() {
    value="${1:-/}"
    case "$value" in
        *[!a-zA-Z0-9/_.-]*)
            echo "Error: SB_pathPrefix contains invalid characters: $value" >&2
            exit 1
            ;;
    esac
    case "$value" in
        /*) ;;
        *) value="/$value" ;;
    esac
    if [ "$value" = "/" ]; then
        printf '%s' "/"
        return
    fi
    case "$value" in
        */) ;;
        *) value="${value}/" ;;
    esac
    printf '%s' "$value"
}

export SB_pathPrefix="$(normalize_path_prefix "${SB_pathPrefix:-/}")"

if grep -rqF "$PLACEHOLDER" /usr/share/nginx/html/ 2>/dev/null; then
    grep -rlF "$PLACEHOLDER" /usr/share/nginx/html/ | xargs sed -i "s|${PLACEHOLDER}|${SB_pathPrefix}|g"
fi

cp /etc/nginx/templates/default.conf /etc/nginx/conf.d/default.conf
barePrefix=$(printf '%s' "${SB_pathPrefix}" | sed 's|/*$||')
if [ -n "${barePrefix}" ]; then
    sed -i "s|<prefixRedirect>|    location = ${barePrefix} { return 301 ${barePrefix}/; }|" /etc/nginx/conf.d/default.conf
else
    sed -i '/<prefixRedirect>/d' /etc/nginx/conf.d/default.conf
fi
sed -i "s|<pathPrefix>|${SB_pathPrefix}|g" /etc/nginx/conf.d/default.conf

# echo a string, handling different types
safe_echo() {
    # $1 = value
    if [ -z "$1" ]; then
        echo -n "null"
    elif printf '%s\n' "$1" | grep -qE '\n.+\n$'; then
        echo -n "\`$1\`"
    else
        echo -n "'$1'"
    fi
}

#  handle boolean
bool() {
    # $1 = value
    case "$1" in
        true | TRUE | yes | t | True)
            echo -n true ;;
        false | FALSE | no | n | False)
            echo -n false ;;
        *)
            echo "Err: Unknown boolean value \"$1\"" >&2
            exit 1 ;;
    esac
}

# handle array values
array() {
    # $1 = value
    # $2 = arraytype
    if [ -z "$1" ]; then
        echo -n "[]"
    else
        case "$2" in
            string)
                echo -n "['$(echo "$1" | sed "s/,/', '/g")']"
                ;;
            *)
                echo -n "[$1]"
                ;;
        esac
    fi
}

# handle object values
object() {
    # $1 = value
    if [ -z "$1" ]; then
        echo -n "null"
    else
        echo -n "$1"
    fi
}

config_schema=$(cat /etc/nginx/conf.d/config.schema.json)

# Iterate over environment variables with "SB_" prefix
env -0 | cut -f1 -d= | tr '\0' '\n' | grep "^SB_" | {
    echo "window.STAC_BROWSER_CONFIG = {"
    while IFS='=' read -r name; do
        # Strip the prefix
        argname="${name#SB_}"
        # Read the variable's value
        value="$(eval "echo \"\$$name\"")"

        # Get the argument type from the schema
        argtype="$(echo "$config_schema" | jq -r ".properties.$argname.type[0]")"
        arraytype="$(echo "$config_schema" | jq -r ".properties.$argname.items.type[0]")"

        # Encode key/value
        echo -n "  $argname: "
        case "$argtype" in
            string)
                safe_echo "$value"
                ;;
            boolean)
                bool "$value"
                ;;
            integer | number | object)
                object "$value"
                ;;
            array)
                array "$value" "$arraytype"
                ;;
            *)
                safe_echo "$value"
                ;;
        esac
        echo ","
    done
    echo "}"
} > /usr/share/nginx/html/runtime-config.js
