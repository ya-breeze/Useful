#!/bin/bash

TMX_SESSION=SS-INVITE

. ~/stuff/bin/tmux/functions

tmx_attach_if_exists
tmux new-session -d -s $TMX_SESSION  './start_A_invite.sh invite_A.xml'
tmux split-window -d -h './start_B_invite.sh invite_B.xml'
tmux attach
