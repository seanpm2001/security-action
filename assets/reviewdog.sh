#!/bin/bash -xe
# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
export SCRIPTPATH=`dirname $SCRIPT`
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
export DEBUG=$DEBUG

RUNNERS="safesvg tfsec semgrep sveltegrep brakeman npm-audit pip-audit"

if [ -n "${GITHUB_BASE_REF+set}" ]; then
    for runner in $RUNNERS; do
        reviewdog -reporter=local -runners=$runner -conf="$SCRIPTPATH/reviewdog/reviewdog.yml" -diff="git diff origin/$GITHUB_BASE_REF" > $runner.log 2>> reviewdog.log || true
        cat /tmp/reviewdog.$runner.stderr.log >> reviewdog.fail.log
        [[ ${DEBUG:-false} == 'true' ]] && cat /tmp/reviewdog.$runner.stderr.log
    done

    for runner in $RUNNERS; do
        cat $runner.log | reviewdog -reporter=github-pr-review -efm='%f:%l: %m' \
          || cat $runner.log >> reviewdog.fail.log
        cat $runner.log >> reviewdog.log
        echo -n "$runner: "
        wc -l $runner.log
        [[ ${DEBUG:-false} == 'true' ]] && cat $runner.log
    done

else
    git ls-files | tr '\n' '\0' > $SCRIPTPATH/all_changed_files.txt
    reviewdog \
      -runners=$(echo "$RUNNERS" | tr ' ' ',') \
      -conf="$SCRIPTPATH/reviewdog/reviewdog.yml"  \
      -filter-mode=nofilter \
      -reporter=local \
      -tee \
      | sed 's/<br><br>Cc @brave\/sec-team[ ]*//' \
      | tee reviewdog.log
    # TODO: in the future send reviewdog.log to a database and just print out errors with
    # [[ ${DEBUG:-false} == 'true' ]] && somethingsomething
    cat /tmp/reviewdog.*.stderr.log >> reviewdog.fail.log
fi

FAIL=$(cat reviewdog.log | grep 'failed with zero findings: The command itself failed' || true)
if [[ -n "$FAIL" ]]; then
    cat reviewdog.log | grep 'failed with zero findings: The command itself failed' >> reviewdog.fail.log
fi

echo "findings=$(cat reviewdog.log | grep '^[A-Z]:[^:]*:' | wc -l)" >> $GITHUB_OUTPUT

find reviewdog.log -type f -empty -delete