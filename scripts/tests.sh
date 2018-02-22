#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Bash script to execute the Solidity tests.
#
# The documentation for solidity is hosted at:
#
#     https://solidity.readthedocs.org
#
# ------------------------------------------------------------------------------
# This file is part of solidity.
#
# solidity is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# solidity is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with solidity.  If not, see <http://www.gnu.org/licenses/>
#
# (c) 2016 solidity contributors.
#------------------------------------------------------------------------------

set -e

REPO_ROOT="$(dirname "$0")"/..

echo "Running commandline tests..."
"$REPO_ROOT/test/cmdlineTests.sh"

# This conditional is only needed because we don't have a working Homebrew
# install for `eth` at the time of writing, so we unzip the ZIP file locally
# instead.  This will go away soon.
if [[ "$OSTYPE" == "darwin"* ]]; then
    ETH_PATH="$REPO_ROOT/eth"
elif [ -z $CI ]; then
    ETH_PATH="eth"
else
    mkdir -p /tmp/test
    # Update hash below if binary is changed.
    wget -q -O /tmp/test/eth https://github.com/ethereum/cpp-ethereum/releases/download/solidityTester/eth_byzantium2
    test "$(shasum /tmp/test/eth)" = "4dc3f208475f622be7c8e53bee720e14cd254c6f  /tmp/test/eth"
    sync
    chmod +x /tmp/test/eth
    sync # Otherwise we might get a "text file busy" error
    ETH_PATH="/tmp/test/eth"
fi

# This trailing ampersand directs the shell to run the command in the background,
# that is, it is forked and run in a separate sub-shell, as a job,
# asynchronously. The shell will immediately return the return status of 0 for
# true and continue as normal, either processing further commands in a script
# or returning the cursor focus back to the user in a Linux terminal.
$ETH_PATH --test -d /tmp/test &
ETH_PID=$!

# Wait until the IPC endpoint is available.  That won't be available instantly.
# The node needs to get a little way into its startup sequence before the IPC
# is available and is ready for the unit-tests to start talking to it.
while [ ! -S /tmp/test/geth.ipc ]; do sleep 2; done
echo "--> IPC available."
sleep 2
ERROR_CODE=0
# And then run the Solidity unit-tests in the matrix combination of optimizer / no optimizer
# and homestead / byzantium VM, # pointing to that IPC endpoint.
for optimize in "" "--optimize"
do
  for vm in homestead byzantium
  do
    echo "--> Running tests using "$optimize" --evm-version "$vm"..."
    set +e
    "$REPO_ROOT"/build/test/soltest --show-progress -- "$optimize" --evm-version "$vm" --ipcpath /tmp/test/geth.ipc
    THIS_ERR=$?
    if [ $? -ne 0 ]; then ERRO_CODE=$?; fi
  done
done
pkill "$ETH_PID" || true
sleep 4
pgrep "$ETH_PID" && pkill -9 "$ETH_PID" || true
exit $ERROR_CODE
