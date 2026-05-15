#!/bin/bash

# put this script in /opt/racecapture

cd /opt/racecapture
./race_capture -c graphics:show_cursor:0 -a -m cursor -c kivy:keyboard_mode:systemandmulti -c graphics:rotation:90
