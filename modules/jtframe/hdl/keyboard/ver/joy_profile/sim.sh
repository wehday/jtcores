#!/bin/bash
# Simulate jtframe_joy_profile with Icarus Verilog
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o sim.vvp test.v ../../jtframe_joy_profile.v
vvp -n sim.vvp
