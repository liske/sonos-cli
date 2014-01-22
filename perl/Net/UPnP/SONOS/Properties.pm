# sonos-cli - Command line interface to control 'Sonos ZonePlayer' 
#
# Authors:
#   Thomas Liske <thomas@fiasko-nw.net>
#
# Copyright Holder:
#   2010 - 2014 (C) Thomas Liske [http://fiasko-nw.net/~thomas/]
#
# License:
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this package; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

package Net::UPnP::SONOS::Properties;

use constant {
        SONOS_AlarmListVersion          => qq(AlarmListVersion),
        SONOS_AlarmRunSequence          => qq(AlarmRunSequence),
        SONOS_AudioInputName            => qq(AudioInputName),
        SONOS_AvailableSoftwareUpdate   => qq(AvailableSoftwareUpdate),
        SONOS_ChannelMapSet             => qq(ChannelMapSet),
        SONOS_Configuration             => qq(Configuration),
        SONOS_ContainerUpdateIDs        => qq(ContainerUpdateIDs),
        SONOS_CurrentConnectionIDs      => qq(CurrentConnectionIDs),
        SONOS_DailyIndexRefreshTime     => qq(DailyIndexRefreshTime),
        SONOS_DateFormat                => qq(DateFormat),
        SONOS_FavoritePresetsUpdateID   => qq(FavoritePresetsUpdateID),
        SONOS_FavoritesUpdateID         => qq(FavoritesUpdateID),
        SONOS_GroupCoordinatorIsLocal   => qq(GroupCoordinatorIsLocal),
        SONOS_GroupMute                 => qq(GroupMute),
        SONOS_GroupVolume               => qq(GroupVolume),
        SONOS_GroupVolumeChangeable     => qq(GroupVolumeChangeable),
        SONOS_HTSatChanMapSet           => qq(HTSatChanMapSet),
        SONOS_Icon                      => qq(Icon),
        SONOS_Invisible                 => qq(Invisible),
        SONOS_IsZoneBridge              => qq(IsZoneBridge),
        SONOS_LastChange                => qq(LastChange),
        SONOS_LeftLineInLevel           => qq(LeftLineInLevel),
        SONOS_LineInConnected           => qq(LineInConnected),
        SONOS_LocalGroupUUID            => qq(LocalGroupUUID),
        SONOS_RadioFavoritesUpdateID    => qq(RadioFavoritesUpdateID),
        SONOS_RadioLocationUpdateID     => qq(RadioLocationUpdateID),
        SONOS_RecentlyPlayedUpdateID    => qq(RecentlyPlayedUpdateID),
        SONOS_RightLineInLevel          => qq(RightLineInLevel),
        SONOS_SavedQueuesUpdateID       => qq(SavedQueuesUpdateID),
        SONOS_ServiceListVersion        => qq(ServiceListVersion),
        SONOS_SettingsReplicationState  => qq(SettingsReplicationState),
        SONOS_ShareIndexInProgress      => qq(ShareIndexInProgress),
        SONOS_ShareIndexLastError       => qq(ShareIndexLastError),
        SONOS_ShareListRefreshState     => qq(ShareListRefreshState),
        SONOS_ShareListUpdateID         => qq(ShareListUpdateID),
        SONOS_SinkProtocolInfo          => qq(SinkProtocolInfo),
        SONOS_SourceProtocolInfo        => qq(SourceProtocolInfo),
        SONOS_SystemUpdateID            => qq(SystemUpdateID),
        SONOS_ThirdPartyMediaServersX   => qq(ThirdPartyMediaServersX),
        SONOS_TimeFormat                => qq(TimeFormat),
        SONOS_TimeGeneration            => qq(TimeGeneration),
        SONOS_TimeServer                => qq(TimeServer),
        SONOS_TimeZone                  => qq(TimeZone),
        SONOS_ZoneGroupID               => qq(ZoneGroupID),
        SONOS_ZoneGroupName             => qq(ZoneGroupName),
        SONOS_ZoneGroupState            => qq(ZoneGroupState),
        SONOS_ZoneName                  => qq(ZoneName),
        SONOS_ZonePlayerUUIDsInGroup    => qq(ZonePlayerUUIDsInGroup),
};

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
        SONOS_AlarmListVersion
        SONOS_AlarmRunSequence
        SONOS_AudioInputName
        SONOS_AvailableSoftwareUpdate
        SONOS_ChannelMapSet
        SONOS_Configuration
        SONOS_ContainerUpdateIDs
        SONOS_CurrentConnectionIDs
        SONOS_DailyIndexRefreshTime
        SONOS_DateFormat
        SONOS_FavoritePresetsUpdateID
        SONOS_FavoritesUpdateID
        SONOS_GroupCoordinatorIsLocal
        SONOS_GroupMute
        SONOS_GroupVolume
        SONOS_GroupVolumeChangeable
        SONOS_HTSatChanMapSet
        SONOS_Icon
        SONOS_Invisible
        SONOS_IsZoneBridge
        SONOS_LastChange
        SONOS_LeftLineInLevel
        SONOS_LineInConnected
        SONOS_LocalGroupUUID
        SONOS_RadioFavoritesUpdateID
        SONOS_RadioLocationUpdateID
        SONOS_RecentlyPlayedUpdateID
        SONOS_RightLineInLevel
        SONOS_SavedQueuesUpdateID
        SONOS_ServiceListVersion
        SONOS_SettingsReplicationState
        SONOS_ShareIndexInProgress
        SONOS_ShareIndexLastError
        SONOS_ShareListRefreshState
        SONOS_ShareListUpdateID
        SONOS_SinkProtocolInfo
        SONOS_SourceProtocolInfo
        SONOS_SystemUpdateID
        SONOS_ThirdPartyMediaServersX
        SONOS_TimeFormat
        SONOS_TimeGeneration
        SONOS_TimeServer
        SONOS_TimeZone
        SONOS_ZoneGroupID
        SONOS_ZoneGroupName
        SONOS_ZoneGroupState
        SONOS_ZoneName
        SONOS_ZonePlayerUUIDsInGroup
);
our %EXPORT_TAGS = (
    keys => [qw(
        SONOS_AlarmListVersion
        SONOS_AlarmRunSequence
        SONOS_AudioInputName
        SONOS_AvailableSoftwareUpdate
        SONOS_ChannelMapSet
        SONOS_Configuration
        SONOS_ContainerUpdateIDs
        SONOS_CurrentConnectionIDs
        SONOS_DailyIndexRefreshTime
        SONOS_DateFormat
        SONOS_FavoritePresetsUpdateID
        SONOS_FavoritesUpdateID
        SONOS_GroupCoordinatorIsLocal
        SONOS_GroupMute
        SONOS_GroupVolume
        SONOS_GroupVolumeChangeable
        SONOS_HTSatChanMapSet
        SONOS_Icon
        SONOS_Invisible
        SONOS_IsZoneBridge
        SONOS_LastChange
        SONOS_LeftLineInLevel
        SONOS_LineInConnected
        SONOS_LocalGroupUUID
        SONOS_RadioFavoritesUpdateID
        SONOS_RadioLocationUpdateID
        SONOS_RecentlyPlayedUpdateID
        SONOS_RightLineInLevel
        SONOS_SavedQueuesUpdateID
        SONOS_ServiceListVersion
        SONOS_SettingsReplicationState
        SONOS_ShareIndexInProgress
        SONOS_ShareIndexLastError
        SONOS_ShareListRefreshState
        SONOS_ShareListUpdateID
        SONOS_SinkProtocolInfo
        SONOS_SourceProtocolInfo
        SONOS_SystemUpdateID
        SONOS_ThirdPartyMediaServersX
        SONOS_TimeFormat
        SONOS_TimeGeneration
        SONOS_TimeServer
        SONOS_TimeZone
        SONOS_ZoneGroupID
        SONOS_ZoneGroupName
        SONOS_ZoneGroupState
        SONOS_ZoneName
        SONOS_ZonePlayerUUIDsInGroup
    )]);

1;
