#!/bin/bash

refname="for"
skip=0

while [ -n "$1" ]; do
    case "$1" in
    --help)
        help=true
        ;;
    --draft|-D)
        refname="drafts"
        ;;
    -O)
        skip=1
        ;;
    -*)
        echo "Error: Invalid option \"$1\"."
        exit 2
        ;;
    *)
        # Stop parsing options on the first non-option argument.
        break
        ;;
    esac

    shift
done

if [ -n "$help" -o $# -gt 2 ]; then
    echo "Rationale"
    echo "    Push commits of the current branch to Gerrit for review."
    echo
    echo "Usage"
    echo "    $(basename $0) [options] [target] [ref]"
    echo
    echo "Example"
    echo "    $(basename $0) development HEAD^"
    echo
    echo "Options"
    echo "    --help"
    echo "        Show this help."
    echo "    --draft, -D"
    echo "        Submit changes as a draft."
    exit 1
fi

[ $# -ge 1 ] && target=$1 || target=master
[ $# -ge 2 ] && ref=$2 || ref=HEAD

remotes=$(git remote show)
if echo "$remotes" | grep -q ^gerrit$; then
    remote=gerrit
elif echo "$remotes" | grep -q ^origin$; then
    remote=origin
else
    remote=$(echo "$remotes" | head -1)
fi

revcount=$(git rev-list $ref --not $remote/$target | wc -l)
revcount=$(echo $revcount)
if [[ $? -eq 0 && $revcount -eq 0 ]]; then
    echo "Nothing to do, $ref is already merged into $remote/$target."
    exit 3
fi

# Create changes from the command line with topic and reviewers optionally set, see:
# http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/user-upload.html#push_create

# Specify a topic if we are on a branch different from the target.
topic=$(git rev-parse --abbrev-ref $ref)
topic=${topic#gerrit/}
topic=${topic#${USER-$USERNAME}/}
if [[ "$topic" != "" && "$topic" != "HEAD" && "$topic" != "$target" ]]; then
    echo "Going to push $revcount \"$topic\" commit(s) for \"$remote/$target\"."
    options="%topic=$topic"
else
    echo "Going to push $revcount commit(s) for \"$remote/$target\"."
fi

# Determine email addresses of potential reviewers (except oneself).
git help -a | grep -q " contacts "
if [[ $? -eq 0 && $skip -eq 0 ]]; then
    echo "Determining reviewers..."
    user=$(git config user.name)
    reviewers=$(git contacts $remote/$target..$ref | grep -iv "$user" | cut -d "<" -f 2 | cut -d ">" -f 1)

    if [ "$reviewers" != "" ]; then
        # Determine the reviewer count, stripping (leading) whitespace.
        count=$(echo "$reviewers" | wc -l)
        count=$(echo $count)
        echo "Found $count possible reviewer(s):"

        for email in $reviewers; do
            echo "    $email"
            if [ -n "$r" ]; then
                r="$r,"
            fi
            r="${r}r=$email"
        done
    else
        echo "No suitable reviewers found."
    fi
else
    echo "Skipping determining reviewers."
fi

if [ -n "$reviewers" ]; then
    choice="/with(o)ut reviewers"
fi
read -p "Do you want to push this review? [(Y)es$choice/(n)o] " -n 1 -r
echo

if [ "$REPLY" != "o" -a "$REPLY" != "O" ]; then
    if [ -n "$r" ]; then
        if [ -z "$options" ]; then
            options="%$r"
        else
            options="$options,$r"
        fi
    fi
fi

if [ "$REPLY" != "n" -a "$REPLY" != "N" ]; then
    git push $remote $ref:refs/$refname/$target$options
fi
