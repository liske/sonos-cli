Using sonos-cli
===============

The old `sonos-cli` command is currently broken. You are required to run
the new backend and use the frontend (interactive) shell.

sonos-backend
-------------

This is the backend daemon, looking for ZonePlayers and tracking there state.

```shell
$ ./sonos-backend -f -d
[notice] listening on 0.0.0.0:58127...
[info] enter event loop...
[info] subscribed to urn:upnp-org:serviceId:AlarmClock on 000E5824C988
[info] subscribed to urn:upnp-org:serviceId:MusicServices on 000E5824C988
...
[info] subscribed to urn:sonos-com:serviceId:Queue on 000E5824C988
[info] subscribed to urn:upnp-org:serviceId:GroupRenderingControl on 000E5824C988
[info] finished async search
[notice] topology update, found 3 zones in 1 groups
```

sosh
----

The SONOS shell is the frontend.

```sh
$ ./sosh
$VAR1 = {
          'retval' => undef,
          'status_code' => 200,
          'status_msg' => 'READY'
        };
led on
$VAR1 = {
          'retval' => undef,
          'status_msg' => 'OK',
          'status_code' => 200
        };
help
$VAR1 = {
          'status_code' => 200,
          'status_msg' => 'OK',
          'retval' => 'Global Commands:
 LED            Enable, disable or toggles zone\'s white status LED.
 exit           Terminate current connection.
 help           Show command list.
 members        Get group members.
 mute           Mute or unmute a zone.
 next           Switch to the next track in a group.
 pause          Pauses a group.
 play           Plays a group.
 previous       Switch to the previous track in a group.
 select         Select (group of) zones to apply commands.
 status         Get zone status.
 stop           Stops a group.
'
        };
```
