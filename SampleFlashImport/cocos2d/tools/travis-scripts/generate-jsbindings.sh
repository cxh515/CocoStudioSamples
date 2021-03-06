#!/bin/bash

# Generate JS and Lua bindings for Cocos2D-X
# ... using Android NDK system headers
# ... and automatically update submodule references
# ... and push these changes to remote repos

# Dependencies
#
# For bindings generator:
# (see ../../../tojs/genbindings.py and ../../../tolua/genbindings.py
# ... for the defaults used if the environment is not customized)
#
#  * $PYTHON_BIN
#  * $CLANG_ROOT
#  * $NDK_ROOT
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COCOS2DX_ROOT="$DIR"/../..
TOJS_ROOT=$COCOS2DX_ROOT/tools/tojs
TOLUA_ROOT=$COCOS2DX_ROOT/tools/tolua
GENERATED_WORKTREE="$COCOS2DX_ROOT"/cocos/scripting/auto-generated
COMMITTAG="[AUTO]"

# Exit on error
set -e

if [ "$PLATFORM"x = "ios"x ]; then
    mkdir -p $HOME/bin
    pushd $HOME/bin
    curl -O http://pyyaml.org/download/pyyaml/PyYAML-3.10.zip
    unzip PyYAML-3.10.zip 2> /dev/null > /dev/null
    cd PyYAML-3.10
    sudo python setup.py install 2> /dev/null > /dev/null
    cd ..
    curl -O https://pypi.python.org/packages/source/C/Cheetah/Cheetah-2.4.4.tar.gz
    tar xzf Cheetah-2.4.4.tar.gz
    cd Cheetah-2.4.4
    sudo python setup.py install 2> /dev/null > /dev/null
    popd
elif [ $(command -v apt-get) ]; then
    sudo apt-get --force-yes --yes install python-yaml python-cheetah
fi

generate_bindings_glue_codes()
{
    echo "Create auto-generated jsbinding glue codes."
    pushd "$TOJS_ROOT"
    ./genbindings.py
    popd

    echo "Create auto-generated luabinding glue codes."
    pushd "$TOLUA_ROOT"
    ./genbindings.py
    popd
}

if [ "$GEN_JSB"x != "YES"x ]; then
    generate_bindings_glue_codes
    exit 0
fi

pushd "$COCOS2DX_ROOT"
#Set git user for cocos2d-x repo
git config user.email ${GH_EMAIL}
git config user.name ${GH_USER}
popd

# Update submodule of auto-gen Binding repo.
pushd "$GENERATED_WORKTREE"

git checkout -B master
echo "Set git user for the submodule of ${GENERATED_WORKTREE}"
git config user.email ${GH_EMAIL}
git config user.name ${GH_USER}
#Set remotes
git remote add upstream https://${GH_USER}:${GH_PASSWORD}@github.com/cocos2d-x/bindings-auto-generated.git 2> /dev/null > /dev/null

echo "Delete all directories and files except '.git' and 'README.md'."
ls -a | grep -E -v ^\[.\]\{1,2\}$ | grep -E -v ^\.git$ | grep -E -v ^README\.md$ | xargs -I{} rm -rf {}
echo "Show files in ${GENERATED_WORKTREE} folder."
ls -a
popd



# 1. Generate JS bindings
generate_bindings_glue_codes

echo
echo Bindings generated successfully
echo


if [ -z "${COMMITTAG+aaa}" ]; then
# ... if COMMITTAG is not set, use this machine's hostname
    COMMITTAG=`hostname -s`
fi

echo
echo Using "'$COMMITTAG'" in the commit messages
echo

ELAPSEDSECS=`date +%s`
echo Using "$ELAPSEDSECS" in the branch names for pseudo-uniqueness

GENERATED_BRANCH=autogeneratedbindings_"$ELAPSEDSECS"


# 2. In Bindings repo, Check if there are any files that are different from the index

pushd "$GENERATED_WORKTREE"

# Run status to record the output in the log
git status

echo
echo Comparing with HEAD ...
echo

# Don't exit on non-zero return value
set +e
git diff --stat --exit-code

DIFF_RETVAL=$?
if [ $DIFF_RETVAL -eq 0 ]
then
    echo
    echo "No differences in generated files"
    echo "Exiting with success."
    echo
    exit 0
else
    echo
    echo "Generated files differ from HEAD. Continuing."
    echo
fi

# Exit on error
set -e

# 3. In Bindings repo, Check out a branch named "autogeneratedbindings" and commit the auto generated bindings to it
git checkout -b "$GENERATED_BRANCH"
git add --verbose .
git add --verbose -u .
git commit --verbose -m "$COMMITTAG : autogenerated bindings"

# 4. In Bindings repo, Push the commit with generated bindings to "master" of the auto generated bindings repository
git push -fq upstream "$GENERATED_BRANCH":${TRAVIS_BRANCH}_${ELAPSEDSECS} 2> /dev/null

popd


COCOS_BRANCH=updategeneratedsubmodule_"$ELAPSEDSECS"

pushd "${DIR}"

# 5. In Cocos2D-X repo, Checkout a branch named "updategeneratedsubmodule" Update the submodule reference to point to the commit with generated bindings
cd "${COCOS2DX_ROOT}"
git add ${GENERATED_WORKTREE}
git checkout -b "$COCOS_BRANCH"
git commit -m "$COMMITTAG : updating submodule reference to latest autogenerated bindings"
#Set remotes
git remote add upstream https://${GH_USER}:${GH_PASSWORD}@github.com/${GH_USER}/cocos2d-x.git 2> /dev/null > /dev/null
# 6. In Cocos2D-X repo, Push the commit with updated submodule to "master" of the cocos2d-x repository
echo "Pushing to Robot's repo ..."
git push -fq upstream "$COCOS_BRANCH" 2> /dev/null


# 7. 
echo "Sending Pull Request to base repo ..."
curl --user "${GH_USER}:${GH_PASSWORD}" --request POST --data "{ \"title\": \"$COMMITTAG : updating submodule reference to latest autogenerated bindings\", \"body\": \"\", \"head\": \"${GH_USER}:${COCOS_BRANCH}\", \"base\": \"${TRAVIS_BRANCH}\"}" https://api.github.com/repos/cocos2d/cocos2d-x/pulls 2> /dev/null > /dev/null

popd
