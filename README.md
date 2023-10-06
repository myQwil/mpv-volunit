# mpv-volunit
mpv scripts for changing volume by decibel amounts.

`volunit-bar.lua` is a slightly altered version of `volunit.lua` that also displays its own custom volume bar to reflect linearly the dB scale.

There are no default key-bindings. This is instead left up to the user to assign keys in their input config file. For example:

`input.conf`:
```ini
# Soft Volume
9 repeatable script-message-to volunit  dB add -2
0 repeatable script-message-to volunit  dB add +2

# AO Volume
/ repeatable script-message-to volunit  ao-dB add -0.5 .1f # optional string format arg
* repeatable script-message-to volunit  ao-dB add +0.5 .1f

# Set
- repeatable script-message-to volunit  dB set -20  # 46.42%
+ repeatable script-message-to volunit  dB set -inf # 0%

# Print 
a repeatable script-message-to volunit  dB .3f # string format arg works here too
```

It is also recommended to change the max volume to a decibel value:

`mpv.conf`:
```ini
volume-max=125.892541179416721 # 10^(2 + 6/60) or +6 dB
```
