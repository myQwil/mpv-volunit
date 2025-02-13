# mpv-volunit
mpv scripts for changing volume by decibel amounts.

There are no default key-bindings. They need to be set manually in the input config file. For example:

`input.conf`:
```ini
# Add
# args: value [precision]
# default precision is the same as value
9 repeatable script-message-to volunit  dB add -2 0.5
0 repeatable script-message-to volunit  dB add +2 0.5

# Add With AO Volume
/ repeatable script-message-to volunit  ao-dB add -0.5
* repeatable script-message-to volunit  ao-dB add +0.5

# Set
# args: value [format]
# default format is 'g' (most compact form)
- repeatable script-message-to volunit  dB set -20 .1f  # 46.42%
+ repeatable script-message-to volunit  dB set -inf     # 0%

# Print 
# args: [format]
# default format is 'g' (most compact form)
a repeatable script-message-to volunit  dB .3f
```

It is also recommended to change the max volume to a decibel value:

`mpv.conf`:
```ini
volume-max=125.892541179416721 # 10^(2 + 6/60) or +6 dB
```
